# Select the exact deployment generation marked for this build, then follow its
# owned ReplicaSets and pods. Never attribute old-revision failures to this run.
def owned($uid): any(.metadata.ownerReferences[]?; .uid == $uid and .controller == true);
($deploy[0]) as $d |
($d.metadata.annotations["deployment.kubernetes.io/revision"] // "") as $revision |
($d.spec.template.metadata.annotations["ci.aof/build"] == $build and
 ($d.status.observedGeneration // 0) >= $d.metadata.generation) as $observed |
[ $rs[0].items[]? | select(owned($d.metadata.uid)) |
  select(.metadata.annotations["deployment.kubernetes.io/revision"] == $revision and
         .spec.template.metadata.annotations["ci.aof/build"] == $build) | .metadata.uid ] as $owners |
[ $pods[0].items[]? | select(.metadata.deletionTimestamp == null) |
  select(any(.metadata.ownerReferences[]?; .uid as $uid | $owners | index($uid))) |
  {name:.metadata.name, uid:.metadata.uid, phase:.status.phase,
   containers:[(.status.initContainerStatuses[]?, .status.containerStatuses[]?) |
    {name, ready, restarts:.restartCount, reason:(.state.waiting.reason // .state.terminated.reason // ""),
     exitCode:.state.terminated.exitCode}],
   ready:([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0)} ] as $current |
{observed:$observed, generation:$d.metadata.generation, revision:$revision,
 desired:($d.spec.replicas // 1), available:($d.status.availableReplicas // 0),
 updated:($d.status.updatedReplicas // 0), pods:$current,
 ready:($observed and ($owners|length)>0 and ($current|length)==($d.spec.replicas // 1) and
        all($current[]; .ready) and ($d.status.updatedReplicas // 0)==($d.spec.replicas // 1) and
        ($d.status.availableReplicas // 0)>=($d.spec.replicas // 1))}
