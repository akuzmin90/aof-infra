#!/bin/sh
# Run in a disposable directory with JDK 17+ and the installed Jenkins/plugin jars.
set -eu
: "${JENKINS_WAR:=/usr/share/jenkins/jenkins.war}"
: "${JENKINS_PLUGINS:=/var/jenkins_home/plugins}"
mkdir -p api classes bundle/WEB-INF/lib
(cd api && jar xf "$JENKINS_WAR" WEB-INF/lib)
cp="api/WEB-INF/lib/*:$JENKINS_PLUGINS/workflow-api/WEB-INF/lib/*:$JENKINS_PLUGINS/workflow-step-api/WEB-INF/lib/*"
javac --release 17 -cp "$cp" -processor net.java.sezpoz.impl.Indexer -d classes src/com/hitmakers/jenkins/BackendConsoleFactory.java
jar cf bundle/WEB-INF/lib/aof-backend-console.jar -C classes .
cat > manifest <<EOF
Manifest-Version: 1.0
Short-Name: aof-backend-console
Long-Name: AOF backend console formatting
Plugin-Version: 1.0.0
Jenkins-Version: 2.479.3
Plugin-Dependencies: workflow-api:1413.v2ff1a_5e720fa_
Support-Dynamic-Loading: true

EOF
jar cfm aof-backend-console.hpi manifest -C bundle .
