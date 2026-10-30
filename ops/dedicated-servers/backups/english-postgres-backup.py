#!/usr/bin/env python3
"""Single English-production dump, legacy copies, and verified S3 upload."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent / "vendor"))
import boto3
from boto3.s3.transfer import TransferConfig
from botocore.config import Config
from botocore.exceptions import ClientError

BASE = Path("/var/lib/aof-backup")
CONFIG = Path("/etc/aof-backup/config.json")
LOG = Path("/var/log/aof-backup.log")
LOCK = Path("/run/lock/aof-en-backup.lock")
RATE = 8 * 1024 * 1024


def bounded_command(command, timeout, **kwargs):
    child = subprocess.Popen(command, start_new_session=True, **kwargs)
    try:
        code = child.wait(timeout=timeout)
    except BaseException:
        os.killpg(child.pid, signal.SIGTERM)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
        raise
    if code:
        raise subprocess.CalledProcessError(code, command)


def event(stage, status, **fields):
    record = dict(time=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  host="mland", stage=stage, status=status, **fields)
    with LOG.open("a") as out:
        out.write(json.dumps(record, sort_keys=True) + "\n")
    print(json.dumps(record, sort_keys=True), flush=True)


def save(path, data):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as out:
        json.dump(data, out, sort_keys=True)
        out.flush()
        os.fsync(out.fileno())
    os.replace(str(temporary), str(path))


def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def database_preflight(config):
    pg = config["postgres"]
    env = os.environ.copy()
    env.update(PGPASSWORD=pg["password"], PGCONNECT_TIMEOUT="5",
               PGOPTIONS="-c default_transaction_read_only=on -c statement_timeout=5000 -c lock_timeout=1000")
    query = ("SELECT current_database(),current_user,current_setting('server_version_num'),"
             "pg_database_size(current_database()),pg_is_in_recovery()")
    result = subprocess.run(["/usr/bin/psql", "-X", "-A", "-t", "-F", "|", "-w",
                             "-h", pg["host"], "-p", str(pg["port"]), "-U", pg["user"],
                             "-d", pg["database"], "-v", "ON_ERROR_STOP=1", "-c", query],
                            env=env, capture_output=True, text=True, check=True, timeout=10)
    name, role, version, size, replica = result.stdout.strip().split("|")
    if name != "aof" or role != pg["user"] or int(version) // 10000 != 11 or replica != "f":
        raise RuntimeError("Database identity/version changed")
    if shutil.disk_usage(BASE).free < max(50 * 1024 ** 3, 2 * int(size)):
        raise RuntimeError("Insufficient free space for bounded backup staging")
    event("preflight", "success", database=name, role=role, database_bytes=int(size))


def client(config):
    return boto3.client(
        "s3", endpoint_url=config["endpoint"], region_name=config["region"],
        aws_access_key_id=config["access_key"], aws_secret_access_key=config["secret_key"],
        config=Config(signature_version="s3v4", connect_timeout=5, read_timeout=20,
                      retries={"mode": "standard", "total_max_attempts": 3},
                      s3={"addressing_style": "path"},
                      request_checksum_calculation="when_required",
                      response_checksum_validation="when_required"))


def verify_remote(s3, bucket, key, size, expected, rate=RATE):
    head = s3.head_object(Bucket=bucket, Key=key)
    if head["ContentLength"] != size or head.get("Metadata", {}).get("sha256") != expected:
        raise RuntimeError("S3 object metadata mismatch")
    response = s3.get_object(Bucket=bucket, Key=key)
    digest = hashlib.sha256()
    count = 0
    started = time.monotonic()
    try:
        while True:
            block = response["Body"].read(1024 * 1024)
            if not block:
                break
            count += len(block)
            digest.update(block)
            delay = count / rate - (time.monotonic() - started)
            if delay > 0:
                time.sleep(delay)
    finally:
        response["Body"].close()
    if count != size or digest.hexdigest() != expected:
        raise RuntimeError("S3 downloaded bytes do not match local SHA256")
    return head


def upload(config, archive, manifest, manifest_path):
    s3 = client(config)
    size = archive.stat().st_size
    digest = digest_file(archive)
    if manifest.get("sha256") and manifest["sha256"] != digest:
        raise RuntimeError("Retained archive changed since previous attempt")
    manifest.update(size=size, sha256=digest)
    save(manifest_path, manifest)
    bucket, key = config["bucket"], manifest["s3_key"]
    event("s3_upload", "started", object=key, bytes=size)
    transfer = TransferConfig(multipart_threshold=64 * 1024 * 1024,
                              multipart_chunksize=16 * 1024 * 1024,
                              max_concurrency=1, max_io_queue=4,
                              max_bandwidth=RATE, use_threads=True)
    if not manifest.get("s3_verified"):
        # A retry may replace only this run's immutable, unique key with identical bytes.
        s3.upload_file(str(archive), bucket, key,
                       ExtraArgs={"ContentType": "application/gzip", "Metadata": {"sha256": digest}},
                       Config=transfer)
        verify_remote(s3, bucket, key, size, digest)
        manifest["s3_verified"] = True
        save(manifest_path, manifest)
    else:
        verify_remote(s3, bucket, key, size, digest)
    sidecar = (digest + "  " + archive.name + "\n").encode("ascii")
    s3.put_object(Bucket=bucket, Key=key + ".sha256", Body=sidecar, ContentType="text/plain")
    # Publish latest only after independent GET+SHA256 verification of the immutable object.
    latest = config["prefix"].rstrip("/") + "/latest.sql.gz"
    if not manifest.get("latest_verified"):
        previous = None
        try:
            previous = s3.head_object(Bucket=bucket, Key=latest)
        except ClientError as error:
            if error.response["Error"]["Code"] not in ("404", "NoSuchKey", "NotFound"):
                raise
        identical = (previous is not None and previous["ContentLength"] == size
                     and previous.get("Metadata", {}).get("sha256") == digest)
        created = datetime.datetime.fromisoformat(manifest.get(
            "created_at", datetime.datetime.now(datetime.timezone.utc).isoformat()))
        if (previous and not identical and previous.get("LastModified", created) > created):
            raise RuntimeError("Refusing to replace a newer latest object with an older recovery run")
        if not identical:
            s3.copy({"Bucket": bucket, "Key": key}, bucket, latest, Config=transfer,
                    ExtraArgs={"MetadataDirective": "REPLACE", "Metadata": {"sha256": digest},
                               "ContentType": "application/gzip"})
        head = s3.head_object(Bucket=bucket, Key=latest)
        if head["ContentLength"] != size or head.get("Metadata", {}).get("sha256") != digest:
            raise RuntimeError("Latest object metadata mismatch")
    manifest["latest_verified"] = True
    save(manifest_path, manifest)
    event("s3_upload", "success", object=key, bytes=size, sha256=digest,
          verification="full_readback_sha256", latest=latest)


def dump(config, archive, work):
    pg = config["postgres"]
    env = os.environ.copy()
    env.update(PGPASSWORD=pg["password"], PGCONNECT_TIMEOUT="5",
               PGOPTIONS="-c default_transaction_read_only=on -c lock_timeout=5000 -c statement_timeout=600000")
    args = ["/usr/bin/pg_dump", "--no-password", "--lock-wait-timeout=5s",
            "-U", pg["user"], "-h", pg["host"], "-p", str(pg["port"]), pg["database"]]
    partial = archive.with_suffix(archive.suffix + ".partial")
    event("dump", "started", file=archive.name)
    with (work / "dump.stderr").open("wb") as error, partial.open("wb") as output:
        producer = subprocess.Popen(args, env=env, stdout=subprocess.PIPE, stderr=error)
        compressor = subprocess.Popen(["/bin/gzip", "-9"], stdin=producer.stdout,
                                      stdout=output, stderr=error)
        producer.stdout.close()
        try:
            dump_code = producer.wait(timeout=2700)
            gzip_code = compressor.wait(timeout=60)
        except BaseException:
            for child in (producer, compressor):
                if child.poll() is None:
                    child.kill()
            producer.wait()
            compressor.wait()
            raise
    if dump_code or gzip_code:
        raise RuntimeError("Dump/compression failed; partial archive retained")
    subprocess.run(["/bin/gzip", "-t", str(partial)], check=True, timeout=600,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.replace(str(partial), str(archive))
    event("dump", "success", file=archive.name, bytes=archive.stat().st_size)


def copy_legacy(config, archive, manifest, manifest_path, work):
    failures = []
    for index, target in enumerate(config["copies"]):
        label = "legacy_" + str(index + 1)
        if manifest.get(label):
            continue
        destination = target["destination"].format(date=manifest["legacy_date"])
        env = os.environ.copy()
        env["SSHPASS"] = target["password"]
        event(label, "started")
        args = ["/usr/bin/sshpass", "-e", "/usr/bin/scp", "-l", "65536",
                "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15",
                "-o", "ServerAliveCountMax=2", "-o", "StrictHostKeyChecking=yes",
                str(archive), destination]
        try:
            with (work / (label + ".stderr")).open("wb") as error:
                bounded_command(args, env=env, timeout=1800,
                                stdout=subprocess.DEVNULL, stderr=error)
            manifest[label] = True
            save(manifest_path, manifest)
            event(label, "success")
        except (subprocess.SubprocessError, OSError) as error:
            event(label, "failed", error_type=type(error).__name__)
            failures.append(label)
    return failures


def complete(config, archive, manifest, manifest_path, work):
    failures = copy_legacy(config, archive, manifest, manifest_path, work)
    # Attempt S3 even if an existing remote destination is unavailable.
    try:
        command = [sys.executable, str(Path(__file__).resolve()), "upload-worker",
                   "--config", str(CONFIG), "--manifest", str(manifest_path)]
        bounded_command(command, timeout=3600)
    except (subprocess.SubprocessError, OSError) as error:
        event("s3_upload", "failed", error_type=type(error).__name__)
        failures.append("s3")
    if failures:
        event("backup", "failed", failed_stages=failures, retained_file=str(archive))
        return 1
    manifest = json.loads(manifest_path.read_text())
    if not all(manifest.get(k) for k in ("legacy_1", "legacy_2", "s3_verified", "latest_verified")):
        raise RuntimeError("Refusing cleanup without all destinations verified")
    manifest["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    save(manifest_path, manifest)
    save(BASE / "last-success.json", manifest)
    archive.unlink()
    for name in ("dump.stderr", "legacy_1.stderr", "legacy_2.stderr"):
        (work / name).unlink(missing_ok=True)
    event("backup", "success", object=manifest["s3_key"], bytes=manifest["size"],
          sha256=manifest["sha256"], legacy_copies=2)
    return 0


def main():
    global CONFIG
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["run", "resume", "upload-worker"])
    parser.add_argument("--config", type=Path, default=CONFIG)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    CONFIG = args.config
    os.umask(0o077)
    config = json.loads(CONFIG.read_text())
    if args.mode == "upload-worker":
        manifest = json.loads(args.manifest.read_text())
        upload(config, Path(manifest["archive"]), manifest, args.manifest)
        return 0
    if socket.gethostname() != "mland":
        raise RuntimeError("Wrong production host")
    if (config["postgres"]["host"], config["postgres"]["port"], config["postgres"]["database"]) != ("127.0.0.1", 5432, "aof"):
        raise RuntimeError("Unexpected database target")
    if config["bucket"] != "aof-postgres-dumps" or config["prefix"] != "prod-en/automatic":
        raise RuntimeError("Unexpected S3 target")
    with LOCK.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            event("backup", "skipped", reason="already_running")
            return 0
        if args.mode == "resume":
            path = args.manifest.resolve()
            if BASE.resolve() not in path.parents:
                raise RuntimeError("Resume manifest outside backup state")
            manifest = json.loads(path.read_text())
            return complete(config, Path(manifest["archive"]), manifest, path, path.parent)
        if shutil.disk_usage(BASE).free < 50 * 1024 ** 3:
            raise RuntimeError("Less than 50 GiB free; refusing new dump")
        # Detect an older, non-locking legacy job before switching to this pipeline.
        running = subprocess.run(["/usr/bin/pgrep", "-x", "pg_dump"], capture_output=True)
        if running.returncode == 0:
            raise RuntimeError("Another pg_dump is running")
        database_preflight(config)
        now = datetime.datetime.now(datetime.timezone.utc)
        identity = now.strftime("%Y%m%dT%H%M%SZ") + "-" + str(os.getpid())
        work = BASE / "runs" / identity
        work.mkdir(parents=True)
        archive = work / ("aof-prod-en-" + identity + ".sql.gz")
        manifest = {"archive": str(archive), "created_at": now.isoformat(),
                    "legacy_date": time.strftime("%Y-%m-%d"),
                    "s3_key": config["prefix"] + "/" + archive.name}
        manifest_path = work / "manifest.json"
        save(manifest_path, manifest)
        try:
            dump(config, archive, work)
            return complete(config, archive, manifest, manifest_path, work)
        except BaseException as error:
            event("backup", "failed", error_type=type(error).__name__, retained_directory=str(work))
            raise


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        # Do not print exception contents: SDK/command errors can contain credentials or data.
        print("Backup failed: " + type(error).__name__ + "; inspect root-only retained diagnostics.", file=sys.stderr)
        sys.exit(1)
