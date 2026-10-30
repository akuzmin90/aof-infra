"""Render real OpenTofu locals; check job triggers, pins, and both agent pools."""
import base64
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

MODULE=Path(__file__).resolve().parents[1]
@unittest.skipUnless(shutil.which('tofu'),'OpenTofu is required to render configuration')
class ConfigurationTests(unittest.TestCase):
 def test_jobs_and_agent_templates(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   source=(MODULE/'main.tf').read_text()
   (root/'main.tf').write_text(source[:source.index('resource "kubernetes_namespace"')])
   shutil.copy(MODULE/'variables.tf',root/'variables.tf')
   for name in ['backend','charts','parameters','agents']: (root/name).symlink_to(MODULE/name,target_is_directory=True)
   for instances in [['dev','feature','release'],['feature']]:
    r=subprocess.run(['tofu',f'-chdir={root}','console','-var=admin_password=test','-var=backend_job_name=aof-back','-var=frontend_instances='+json.dumps(instances)],input='jsonencode(local.backend_job_scripts)\n',text=True,capture_output=True,check=True)
    scripts=json.loads(json.loads(r.stdout));self.assertEqual(len(scripts),1+len(instances))
    for script in scripts:
     name=re.search(r"pipelineJob\('([^']+)'",script)[1]
     encoded=re.search(r"new String\('([A-Za-z0-9+/=]+)'\.decodeBase64",script)[1]
     pipeline=base64.b64decode(encoded).decode()
     self.assertIn("lock(resource: 'aof-back-' + instance",pipeline)
     self.assertEqual(pipeline.count("lock(resource: 'aof-stand-' + instance"),1)
     deploy=pipeline.index("stage('Deploy')")
     self.assertLess(deploy,pipeline.index("lock(resource: 'aof-stand-' + instance"))
     self.assertLess(pipeline.index("stage('Build and Push Image')"),deploy)
     self.assertIn('showRawYaml: false',pipeline)
     self.assertIn('archiveArtifacts',pipeline)
     self.assertIn('CauseOfInterruption.UserInterruption',pipeline)
     self.assertNotIn('isActualInterruption()',pipeline)
     self.assertEqual('pollSCM' in script,name in ['aof-back-dev','aof-back-release'])
     if name!='aof-back':
      self.assertEqual(re.findall(r"stringParam\('([^']+)'",script),['GIT_BRANCH','DEPLOY_TIMEOUT'] if name=='aof-back-feature' else ['DEPLOY_TIMEOUT'])
      self.assertNotIn('params.INSTANCE',pipeline)
      if name=='aof-back-feature':
       self.assertIn('params.GIT_BRANCH?.trim()',pipeline)
       self.assertIn("stringParam('GIT_BRANCH', 'develop'",script)
      else:
       self.assertNotIn('params.GIT_BRANCH',pipeline)
      self.assertIn("def instance = '"+name.removeprefix('aof-back-')+"'",pipeline)
     else:
      self.assertIn('params.INSTANCE',pipeline)
     for pool in ['regular','emergency']:
      agent=re.search(r"def "+pool+"Yaml = "+"'"*3+r"(.*?)"+"'"*3,pipeline,re.S)[1]
      self.check_agent(agent,pool)
     self.assertIn('!deploymentStarted',pipeline)
 def test_frontend_jobs(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   source=(MODULE/'main.tf').read_text()
   (root/'main.tf').write_text(source[:source.index('resource "kubernetes_namespace"')])
   shutil.copy(MODULE/'variables.tf',root/'variables.tf')
   for name in ['backend','charts','parameters','agents']: (root/name).symlink_to(MODULE/name,target_is_directory=True)
   for instances in [['dev','feature','release'],['feature']]:
    r=subprocess.run(['tofu',f'-chdir={root}','console','-var=admin_password=test','-var=frontend_job_name=aof-front','-var=frontend_s3_endpoint_url=https://s3.example.invalid','-var=frontend_instances='+json.dumps(instances)],input='jsonencode(local.frontend_job_scripts)\n',text=True,capture_output=True,check=True)
    scripts=json.loads(json.loads(r.stdout))
    self.assertEqual(len(scripts),1+len(instances))
    for script in scripts:
     name=re.search(r"pipelineJob\('([^']+)'",script)[1]
     self.assertEqual('pollSCM' in script,name in ['aof-front-dev','aof-front-release'])
     self.assertIn("lock(resource: 'aof-front-' + instance",script)
     self.assertNotIn("lock(resource: 'aof-stand-'",script)
     self.assertEqual(script.count('"value": "https://s3.example.invalid"'),2)
     for pool in ['regular','emergency']:
      agent=re.search('def '+pool+'Yaml = """(.*?)"""',script,re.S)[1]
      self.check_agent(agent,pool)
     self.assertNotIn('minio.minio.svc.cluster.local',script)
     if name=='aof-front':
      self.assertIn('params.INSTANCE',script)
      self.assertIn('params.BUILD_COMMAND',script)
      continue
     instance=name.removeprefix('aof-front-')
     self.assertIn("def instance = '"+instance+"'",script)
     self.assertNotIn('params.INSTANCE',script)
     self.assertNotIn('params.GIT_CREDENTIALS_ID',script)
     self.assertNotIn('params.BUILD_COMMAND',script)
     self.assertIn('disableConcurrentBuilds()',script)
     self.assertEqual(re.findall(r"stringParam\('([^']+)'",script),['GIT_BRANCH'] if instance=='feature' else [])
     if instance=='feature':
      self.assertIn('params.GIT_BRANCH?.trim()',script)
     else:
      self.assertNotIn('params.GIT_BRANCH',script)
      self.assertIn("def gitBranch = '"+{'dev':'develop','release':'test'}[instance]+"'",script)
 def test_database_and_diagnostic_agents(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   source=(MODULE/'main.tf').read_text()
   (root/'main.tf').write_text(source[:source.index('resource "kubernetes_namespace"')])
   shutil.copy(MODULE/'variables.tf',root/'variables.tf')
   for name in ['backend','charts','parameters','agents']: (root/name).symlink_to(MODULE/name,target_is_directory=True)
   r=subprocess.run(['tofu',f'-chdir={root}','console','-var=admin_password=test'],input='jsonencode(local.database_agent_yaml)\n',text=True,capture_output=True,check=True)
   pools=json.loads(json.loads(r.stdout))
   import yaml
   for pool,modes in pools.items():
    for mode,raw in modes.items():
     self.check_agent(raw,pool)
     spec=yaml.safe_load(raw)['spec']
     if mode=='restore':
      self.assertEqual(spec['securityContext']['fsGroup'],1000)
      self.assertEqual(spec['volumes'][0]['configMap']['name'],'aof-db-restore-script')
 def check_agent(self,raw,pool):
  # Parse the rendered Pod, so admission-relevant placement and resources are tested.
  import yaml
  pod=yaml.safe_load(raw);spec=pod['spec']
  self.assertNotIn('initContainers',spec)
  for container in spec['containers']:
   self.assertNotIn('resources',container)
  if pool=='regular':
   self.assertNotIn('nodeSelector',spec)
   rule=spec['affinity']['nodeAffinity']['requiredDuringSchedulingIgnoredDuringExecution']['nodeSelectorTerms'][0]['matchExpressions'][0]
   self.assertEqual(rule,{'key':'workload','operator':'NotIn','values':['ci']})
   self.assertEqual(spec['tolerations'],[{'key':'dedicated','operator':'Exists','effect':'NoSchedule'}])
  else:
   self.assertEqual(spec['nodeSelector'],{'workload':'ci'})
   self.assertEqual(spec['tolerations'],[{'key':'dedicated','operator':'Equal','value':'ci','effect':'NoSchedule'}])
if __name__=='__main__':unittest.main()
