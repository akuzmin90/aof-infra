This small Jenkins plugin condenses only backend-job scheduling chatter and
routine Git command echoes. Other jobs and unrecognized/error lines pass through.
It uses Pipeline's supported TaskListenerDecorator extension, not global log-level
changes or monkey-patching the Kubernetes plugin. The job name prefix is configured
by the Jenkins init script (`aof.backendJobName`).

Build with `build.sh` using a JDK and the same Jenkins WAR and workflow-api jars as
the controller. The checked-in HPI is installed by the managed Jenkins init script.
Rebuild and increment Plugin-Version for Java changes; upgrades of this helper
require a controller restart, so avoid replacing it during an active build.
