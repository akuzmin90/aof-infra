import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

SCRIPT=Path(__file__).resolve().parents[1]/'backend/build.sh'
class BuildTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  executor=self.root/'executor'
  executor.write_text('''#!/bin/sh
while [ "$#" -gt 0 ]; do
 if [ "$1" = --digest-file ]; then digest=$2; shift; fi
 shift
done
echo $$ > "$WORKSPACE/executor-pid"
case "$CASE" in
 fail) echo 'ERROR: registry push rejected';exit 42;;
 slow) sleep 30;;
esac
echo '[INFO] BUILD SUCCESS'
printf 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' > "$digest"
''');executor.chmod(0o755)
  self.env=dict(os.environ,WORKSPACE=str(self.root),IMAGE_REPOSITORY='test/image',IMAGE_TAG='test',REGISTRY_SERVER='test',REGISTRY_USERNAME='username',REGISTRY_PASSWORD='password-do-not-log',KANIKO_EXECUTOR=str(executor),DOCKER_CONFIG_DIR=str(self.root/'auth'))
 def tearDown(self):self.temp.cleanup()
 def test_success_and_secret_cleanup(self):
  self.env['CASE']='success';r=subprocess.run(['sh',str(SCRIPT)],env=self.env,capture_output=True,text=True,timeout=15)
  self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('Image published',r.stdout);self.assertIn('BUILD SUCCESS',r.stdout)
  self.assertEqual((self.root/'ci-logs/image-digest.txt').stat().st_mode & 0o777, 0o644);self.assertNotIn('password-do-not-log',r.stdout+r.stderr);self.assertFalse((self.root/'auth/config.json').exists())
 def test_failure_exit_and_context(self):
  self.env['CASE']='fail';r=subprocess.run(['sh',str(SCRIPT)],env=self.env,capture_output=True,text=True,timeout=15)
  self.assertEqual(r.returncode,42,r.stdout+r.stderr);self.assertIn('registry push rejected',r.stdout);self.assertFalse((self.root/'auth/config.json').exists())
 def test_cancel_stops_build(self):
  self.env['CASE']='slow';p=subprocess.Popen(['sh',str(SCRIPT)],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  for _ in range(100):
   if (self.root/'executor-pid').exists():break
   time.sleep(.05)
  p.send_signal(signal.SIGTERM);out,err=p.communicate(timeout=15)
  self.assertEqual(p.returncode,130,out+err);self.assertFalse((self.root/'auth/config.json').exists())
  with self.assertRaises(ProcessLookupError):os.kill(int((self.root/'executor-pid').read_text()),0)
if __name__=='__main__':unittest.main()
