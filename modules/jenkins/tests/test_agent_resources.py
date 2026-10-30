"""Only Kubernetes resource evidence can start an emergency agent."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'agents/resource-failure.sh'


class AgentResourceTests(unittest.TestCase):
    def diagnose(self, status='', events='', api_error=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            kubectl = root / 'kubectl'
            kubectl.write_text('''#!/bin/bash
set -eu
if [ "$API_ERROR" = 1 ]; then exit 1; fi
case "$*" in
  *"get pod "*) printf '%s' "$POD_STATUS" ;;
  *"get events "*) printf '%s' "$POD_EVENTS" ;;
  *) exit 2 ;;
esac
''')
            kubectl.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + ':' + os.environ['PATH'],
                       FAILED_POD='failed-build-agent', KUBERNETES_SERVICE_HOST='10.96.0.1',
                       POD_STATUS=status, POD_EVENTS=events, API_ERROR=str(int(api_error)))
            return subprocess.run(['bash', str(SCRIPT)], env=env, capture_output=True, text=True)

    def test_resource_evidence_allows_emergency(self):
        for status, events in [
            ('OOMKilled', ''),
            ('Evicted\nThe node was low on resource: memory.', ''),
            ('', 'Evicted: The node had condition: [DiskPressure].'),
        ]:
            with self.subTest(status=status, events=events):
                result = self.diagnose(status, events)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_unrelated_failure_does_not_start_emergency(self):
        for status, events in [
            ('Running', ''),
            ('Evicted\nThe node is shutting down.', ''),
            ('', 'Failed: Error pulling image'),
            ('', 'Unhealthy: connection refused'),
        ]:
            with self.subTest(status=status, events=events):
                self.assertEqual(self.diagnose(status, events).returncode, 1)

    def test_unavailable_evidence_does_not_start_emergency(self):
        self.assertEqual(self.diagnose(api_error=True).returncode, 1)


if __name__ == '__main__':
    unittest.main()
