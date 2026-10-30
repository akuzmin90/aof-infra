import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location("snapshot", Path(__file__).with_name("host_snapshot.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class SnapshotTests(unittest.TestCase):
    def test_cpu_counts_busy_and_iowait_correctly(self):
        self.assertEqual(m.cpu_percent([0]*8, [20, 0, 10, 60, 10, 0, 0, 0], True), 30)

    def test_first_sample_reboot_and_counter_reset_are_unknown(self):
        self.assertIsNone(m.cpu_percent(None, [1]*8, True))
        self.assertIsNone(m.cpu_percent([0]*8, [1]*8, False))
        self.assertIsNone(m.cpu_percent([2]*8, [1]*8, True))
        self.assertIsNone(m.cpu_percent([1]*8, [1]*8, True))

    def test_memory_uses_available_not_free(self):
        d=m.memory_values('MemTotal: 1000 kB\nMemAvailable: 600 kB\nMemFree: 10 kB\nSwapTotal: 20 kB\nSwapFree: 15 kB\n')
        self.assertEqual(d['memory_used_percent'],40)
        self.assertEqual(d['memory_available_bytes'],600*1024)
        self.assertEqual(d['swap_used_bytes'],5*1024)

    def test_disk_accounts_for_reserved_blocks_and_inodes(self):
        s=SimpleNamespace(f_blocks=100,f_bfree=30,f_bavail=20,f_frsize=4096,f_files=100,f_ffree=80)
        d=m.disk_values('/',s)
        self.assertAlmostEqual(d['disk_used_percent'],77.778,places=3)
        self.assertEqual(d['disk_available_bytes'],20*4096)
        self.assertEqual(d['inode_used_percent'],20)

    def test_stopped_failed_and_pidless_services_are_not_up(self):
        for state,pid in [('failed',0),('inactive',0),('activating',5),('active',0)]:
            text='Id=tomcat.service\nActiveState={}\nMainPID={}\n'.format(state,pid)
            self.assertEqual(m.service_values(text,['tomcat.service'])[0]['active'],0)
        self.assertEqual(m.service_values('Id=tomcat.service\nActiveState=active\nMainPID=5\n',['tomcat.service'])[0]['active'],1)

    def test_unavailable_status_is_unknown_not_healthy(self):
        d=m.service_values('', ['tomcat.service'])[0]
        self.assertEqual(d['collection_ok'],0)
        self.assertEqual(d['active'],-1)

    def test_rotation_preserves_records_and_bounds_file_count(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'samples.jsonl'
            for i in range(10):m.append_records(p,[{'sample':i}],maximum=15)
            self.assertEqual(len(list(Path(folder).glob('samples.jsonl*'))),3)
            self.assertEqual(json.loads(p.read_text())['sample'],9)
            self.assertEqual(json.loads(p.with_name(p.name+'.1').read_text())['sample'],8)

    def test_oversized_snapshot_does_not_write(self):
        with tempfile.TemporaryDirectory() as folder:
            p=Path(folder)/'samples.jsonl'
            with self.assertRaises(RuntimeError):m.append_records(p,[{'too_large':'x'*17000}])
            self.assertFalse(p.exists())


if __name__ == '__main__':unittest.main(verbosity=2)
