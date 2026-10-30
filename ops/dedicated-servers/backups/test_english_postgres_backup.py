import fcntl
import datetime
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("backup", Path(__file__).with_name("english-postgres-backup.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class FakeS3:
    def __init__(self):
        self.objects = {"prod-en/automatic/latest.sql.gz": (b"previous valid backup", {})}
        self.corrupt = False
        self.fail_upload = False
        self.fail_copy = False
        self.modified = datetime.datetime(2020, 1, 1, tzinfo=datetime.timezone.utc)

    def upload_file(self, filename, bucket, key, ExtraArgs, Config):
        if self.fail_upload:
            raise OSError("synthetic unavailable storage")
        self.objects[key] = (Path(filename).read_bytes(), ExtraArgs["Metadata"])

    def head_object(self, Bucket, Key):
        data, metadata = self.objects[Key]
        return {"ContentLength": len(data), "Metadata": metadata, "LastModified": self.modified}

    def get_object(self, Bucket, Key):
        data, _ = self.objects[Key]
        return {"Body": io.BytesIO(b"corrupt" if self.corrupt else data)}

    def put_object(self, Bucket, Key, Body, ContentType):
        self.objects[Key] = (Body, {})

    def copy(self, source, bucket, key, Config, ExtraArgs=None):
        if self.fail_copy:
            raise OSError("synthetic failed latest copy")
        # Model providers which do not preserve metadata on multipart copies.
        self.objects[key] = (self.objects[source["Key"]][0], (ExtraArgs or {}).get("Metadata", {}))


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.work = self.base / "runs" / "synthetic"
        self.work.mkdir(parents=True)
        self.archive = self.work / "synthetic.sql.gz"
        self.archive.write_bytes(b"synthetic compressed archive bytes")
        self.manifest = {"archive": str(self.archive), "legacy_date": "2026-01-01",
                         "s3_key": "prod-en/automatic/synthetic.sql.gz"}
        self.path = self.work / "manifest.json"
        m.save(self.path, self.manifest)
        self.config = {"bucket": "aof-postgres-dumps", "prefix": "prod-en/automatic"}
        self.s3 = FakeS3()
        self.patches = [patch.object(m, "BASE", self.base), patch.object(m, "LOG", self.base / "test.log"),
                        patch.object(m, "client", return_value=self.s3)]
        for item in self.patches:
            item.start()

    def tearDown(self):
        for item in reversed(self.patches):
            item.stop()
        self.temp.cleanup()

    def test_success_publishes_latest_after_readback(self):
        m.upload(self.config, self.archive, self.manifest, self.path)
        saved = json.loads(self.path.read_text())
        self.assertTrue(saved["s3_verified"] and saved["latest_verified"])
        self.assertEqual(self.s3.objects["prod-en/automatic/latest.sql.gz"][0], self.archive.read_bytes())
        self.assertIn(self.manifest["s3_key"] + ".sha256", self.s3.objects)

    def test_corrupt_readback_preserves_archive_and_previous_latest(self):
        self.s3.corrupt = True
        with self.assertRaises(RuntimeError):
            m.upload(self.config, self.archive, self.manifest, self.path)
        self.assertTrue(self.archive.exists())
        self.assertEqual(self.s3.objects["prod-en/automatic/latest.sql.gz"][0], b"previous valid backup")
        self.assertFalse(json.loads(self.path.read_text()).get("s3_verified", False))

    def test_upload_failure_retains_archive(self):
        self.s3.fail_upload = True
        with self.assertRaises(OSError):
            m.upload(self.config, self.archive, self.manifest, self.path)
        self.assertTrue(self.archive.exists())
        self.assertEqual(self.s3.objects["prod-en/automatic/latest.sql.gz"][0], b"previous valid backup")

    def test_latest_failure_retains_verified_timestamped_object(self):
        self.s3.fail_copy = True
        with self.assertRaises(OSError):
            m.upload(self.config, self.archive, self.manifest, self.path)
        self.assertTrue(json.loads(self.path.read_text())["s3_verified"])
        self.assertTrue(self.archive.exists())

    def test_later_legacy_retry_does_not_roll_latest_back(self):
        m.upload(self.config, self.archive, self.manifest, self.path)
        latest = "prod-en/automatic/latest.sql.gz"
        self.s3.objects[latest] = (b"newer valid backup", {"sha256": "newer"})
        m.upload(self.config, self.archive, self.manifest, self.path)
        self.assertEqual(self.s3.objects[latest][0], b"newer valid backup")

    def test_unpublished_old_recovery_does_not_replace_newer_latest(self):
        self.manifest["created_at"] = "2021-01-01T00:00:00+00:00"
        self.s3.modified = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
        with self.assertRaises(RuntimeError):
            m.upload(self.config, self.archive, self.manifest, self.path)
        self.assertEqual(self.s3.objects["prod-en/automatic/latest.sql.gz"][0], b"previous valid backup")

    def test_scp_failure_still_attempts_s3_and_retains_archive(self):
        with patch.object(m, "copy_legacy", return_value=["legacy_1"]), patch.object(m, "bounded_command") as command:
            self.assertEqual(m.complete(self.config, self.archive, self.manifest, self.path, self.work), 1)
            command.assert_called_once()
        self.assertTrue(self.archive.exists())

    def test_s3_failure_after_copies_retains_archive(self):
        with patch.object(m, "copy_legacy", return_value=[]), patch.object(m, "bounded_command", side_effect=subprocess.TimeoutExpired("worker", 1)):
            self.assertEqual(m.complete(self.config, self.archive, self.manifest, self.path, self.work), 1)
        self.assertTrue(self.archive.exists())

    def test_cleanup_requires_all_destination_flags(self):
        with patch.object(m, "copy_legacy", return_value=[]), patch.object(m, "bounded_command"):
            with self.assertRaises(RuntimeError):
                m.complete(self.config, self.archive, self.manifest, self.path, self.work)
        self.assertTrue(self.archive.exists())

    def test_success_records_manifest_then_cleans_archive(self):
        self.manifest.update(legacy_1=True, legacy_2=True, s3_verified=True,
                             latest_verified=True, size=34, sha256="synthetic")
        m.save(self.path, self.manifest)
        with patch.object(m, "copy_legacy", return_value=[]), patch.object(m, "bounded_command"):
            self.assertEqual(m.complete(self.config, self.archive, self.manifest, self.path, self.work), 0)
        self.assertFalse(self.archive.exists())
        self.assertTrue((self.base / "last-success.json").exists())

    def test_failed_dump_does_not_publish_valid_archive(self):
        real_popen = subprocess.Popen
        def popen(args, **kwargs):
            if args[0] == "/usr/bin/pg_dump":
                args = [sys.executable, "-c", "import sys;sys.stdout.write('partial SQL');sys.exit(1)"]
            return real_popen(args, **kwargs)
        config = {"postgres": {"password": "synthetic", "user": "synthetic", "host": "127.0.0.1", "port": 1, "database": "synthetic"}}
        self.archive.unlink()
        with patch.object(m.subprocess, "Popen", side_effect=popen):
            with self.assertRaises(RuntimeError):
                m.dump(config, self.archive, self.work)
        self.assertFalse(self.archive.exists())
        self.assertTrue(self.archive.with_suffix(".gz.partial").exists())

    def test_overlap_lock_prevents_any_dump(self):
        config = dict(self.config, postgres={"host": "127.0.0.1", "port": 5432, "database": "aof"})
        config_path = self.base / "config.json"
        config_path.write_text(json.dumps(config))
        lock_path = self.base / "lock"
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.object(m, "LOCK", lock_path), patch.object(m.socket, "gethostname", return_value="mland"), patch.object(sys, "argv", ["backup.py", "run", "--config", str(config_path)]), patch.object(m, "dump") as dump:
                self.assertEqual(m.main(), 0)
                dump.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
