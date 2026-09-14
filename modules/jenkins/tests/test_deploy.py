"""Run the real deploy wrapper against controlled kubectl/Helm processes."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'backend'
KUBECTL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
scenario = os.environ['SCENARIO']
if 'secret' in args or 'namespace' in args: sys.exit(0)
if scenario == 'api_error': print('API unavailable',file=sys.stderr); sys.exit(1)
if 'deployment' in args:
 p=Path(os.environ['COUNT_FILE']); count=int(p.read_text())+1 if p.exists() else 1; p.write_text(str(count))
 observed = scenario != 'old_revision'
 ready = scenario not in ['crash','restart','pull','config','oom','slow']
 d={'metadata':{'uid':'deployment','generation':2,'annotations':{'deployment.kubernetes.io/revision':'2'}},
 'spec':{'replicas':1,'template':{'metadata':{'annotations':{'ci.aof/build':'run-1' if observed else 'old'}}}},
 'status':{'observedGeneration':2,'availableReplicas':int(ready),'updatedReplicas':1}}
 print(json.dumps(d))
elif 'replicasets' in args:
 print(json.dumps({'items':[{'metadata':{'uid':uid,'ownerReferences':[{'uid':'deployment','controller':True}],'annotations':{'deployment.kubernetes.io/revision':rev}},'spec':{'template':{'metadata':{'annotations':{'ci.aof/build':build}}}}} for uid,rev,build in [('new-rs','2','run-1'),('old-rs','1','old')]]}))
elif 'pods' in args:
 if '-o' in args and args[args.index('-o')+1]=='name': print('pod/new');sys.exit(0)
 reason={'crash':'CrashLoopBackOff','pull':'ImagePullBackOff','config':'CreateContainerConfigError','oom':'OOMKilled'}.get(scenario,'')
 ready=scenario not in ['crash','restart','pull','config','oom','slow']
 def pod(name,rs,reason,restarts,ready):
  return {'metadata':{'name':name,'uid':name,'ownerReferences':[{'uid':rs,'controller':True}]},'status':{'phase':'Running','conditions':[{'type':'Ready','status':'True' if ready else 'False'}], 'containerStatuses':[{'name':'app','ready':ready,'restartCount':restarts,'state':{'waiting':{'reason':reason}} if reason else {'running':{}}}]}}
 print(json.dumps({'items':[pod('new','new-rs',reason,3 if scenario=='restart' else 0,ready),pod('old','old-rs','CrashLoopBackOff',20,False)]}))
elif 'events' in args: print(json.dumps({'items':[]}))
elif 'logs' in args:
 if os.environ.get('DIAGNOSTICS_FAIL'): print('Forbidden',file=sys.stderr);sys.exit(1)
 print('Application startup log')
else: print('{}')
'''
HELM = r'''#!/usr/bin/env python3
import os,sys,time,json
from pathlib import Path
op=sys.argv[1]
if op=='status': print(json.dumps({'info':{'status':'pending-upgrade' if os.environ['SCENARIO']=='pending' else 'deployed'}}))
elif op=='upgrade':
 Path(os.environ['HELM_PID']).write_text(str(os.getpid()))
 if os.environ['SCENARIO']=='helm_error': print('Error: UPGRADE FAILED',flush=True);sys.exit(42)
 time.sleep(.3 if os.environ['SCENARIO'] in ['success','old_revision'] else 30)
 print('Release upgraded')
elif op=='history': print('revision 2 deployed')
'''

class DeploymentTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  for name,source in [('kubectl',KUBECTL),('helm',HELM)]:
   p=self.root/name;p.write_text(source);p.chmod(0o755)
  chart=self.root/'chart';chart.mkdir()
  for f in ['Chart.yaml','values.yaml','values.schema.json','.helmignore']: (chart/f).write_text('')
  (chart/'templates').mkdir()
  (self.root/'ci-logs').mkdir();(self.root/'ci-logs/image-digest.txt').write_text('sha256:'+'a'*64)
  self.env=dict(os.environ,PATH=str(self.root)+':'+os.environ['PATH'],WORKSPACE=str(self.root),CHART_SOURCE=str(chart),STATUS_INTERVAL='0.05',DEPLOY_SECONDS='10',DEPLOY_TIMEOUT='15m',BUILD_ID='run-1',COUNT_FILE=str(self.root/'count'),HELM_PID=str(self.root/'helm-pid'),PULL_FAILURE_GRACE='0')
  for k in ['NAMESPACE','RELEASE_NAME','DB_CLUSTER','IMAGE_REPOSITORY','IMAGE_TAG','ADMIN_PVC','SPRING_PROFILE','BACKEND_MEMORY_REQUEST','BACKEND_MEMORY_LIMIT','STARTUP_FAILURE_THRESHOLD','HOST','LEGACY_HOST','TLS_SECRET','LEGACY_TLS_SECRET']:self.env[k]='test'
 def tearDown(self):self.temp.cleanup()
 def run_case(self,scenario):
  self.env['SCENARIO']=scenario
  return subprocess.run(['bash',str(TOOLS/'deploy.sh')],env=self.env,capture_output=True,text=True,timeout=20)
 def test_success_ignores_old_crashing_pod(self):
  r=self.run_case('success');self.assertEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('SUCCESS',r.stdout)
 def test_helm_exit_preserved_with_broken_diagnostics(self):
  self.env['DIAGNOSTICS_FAIL']='1';r=self.run_case('helm_error');self.assertEqual(r.returncode,42,r.stdout+r.stderr);self.assertIn('UPGRADE FAILED',r.stdout)
 def test_old_healthy_revision_cannot_pass(self):
  r=self.run_case('old_revision');self.assertNotEqual(r.returncode,0);self.assertIn('new revision is not ready',r.stdout)
 def test_startup_failures_stop_helm(self):
  for scenario in ['crash','restart','pull','config','oom']:
   with self.subTest(scenario=scenario):
    r=self.run_case(scenario);self.assertNotEqual(r.returncode,0,r.stdout+r.stderr);self.assertIn('Early failure',r.stdout)
    pid=int((self.root/'helm-pid').read_text())
    with self.assertRaises(ProcessLookupError):os.kill(pid,0)
 def test_api_failure_is_not_success(self):
  r=self.run_case('api_error');self.assertNotEqual(r.returncode,0);self.assertIn('Unable to read rollout status',r.stdout)
 def test_pending_release_not_mutated(self):
  r=self.run_case('pending');self.assertNotEqual(r.returncode,0);self.assertFalse((self.root/'helm-pid').exists())
 def test_slow_start_is_not_early_failure_and_cancel_cleans_up(self):
  self.env['SCENARIO']='slow'
  p=subprocess.Popen(['bash',str(TOOLS/'deploy.sh')],env=self.env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
  for _ in range(100):
   if (self.root/'helm-pid').exists():break
   time.sleep(.05)
  time.sleep(.2);self.assertIsNone(p.poll());p.send_signal(signal.SIGTERM)
  out,err=p.communicate(timeout=15);self.assertEqual(p.returncode,130,out+err);self.assertNotIn('Early failure',out)
  with self.assertRaises(ProcessLookupError):os.kill(int((self.root/'helm-pid').read_text()),0)
if __name__=='__main__':unittest.main()
