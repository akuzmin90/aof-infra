# Agent VPN egress

Standalone Helm release for the AmneziaWG HTTPS proxy. This does not modify the
dev, feature or release stands, node routing, or existing application releases.
The image source is `aof-agent/vpn`. Build from the `aof-agent` repository root:

```bash
docker buildx create --name aof-vpn-build --driver docker-container \
  --driver-opt memory=1536m,cpu-period=100000,cpu-quota=200000,cpuset-cpus=0-1
docker buildx build --builder aof-vpn-build --load -f vpn/Dockerfile -t aof-agent-vpn:BUILD_TAG .
```

Push a reviewed image to the registry and provision its pull credential separately.
Use a unique image tag or digest. Do not put credentials or VPN files in Git or images.

## Configuration and deployment

Amnezia Premium users can download native AmneziaWG configurations from the
Personal Dashboard, Configuration Files section. Use dedicated configurations for
the gateway, not a peer concurrently used by another device. Optional backup
should use another location/server. The subscription `vpn://` key is not an `awg`
configuration.

An original Premium connection code can instead be stored as Secret key
`connection-key` in `aof-agent-vpn-config`. The operator tool in `aof-agent`
provisions a dedicated device and writes native settings to `aof-agent-vpn-state`:

```bash
# Run from aof-agent, using a Python environment with vpn/requirements.txt installed.
python3 vpn/subscription.py --context admin@aof-k8s
```

The source subscription Secret is unchanged and is never mounted in the gateway.
Private device keys are generated locally and saved in the state Secret before
registering the device. Repeated provisioning reuses that identity. The operator
uses HTTPS and Amnezia's encrypted gateway protocol; the public gateway key comes
from the official AmneziaVPN 5.1.0.6 release. No Qt/desktop application is required.
Run `--refresh` to explicitly renew configuration with the same identity, then
restart this gateway deployment. Provider limits, expiry, or revocation can still
prevent a connection; reconnecting does not renew a subscription.

## Automatic country recovery

Enable `failover.enabled=true` and set `failover.apiCidrs` to the Kubernetes Service
IP and actual API endpoint IPs (/32 CIDRs). The separate unprivileged watchdog can
reach the provider even while the gateway tunnel is unavailable. Its Role grants
get on the two VPN Secrets and patch on the state Secret only. It cannot execute
in pods, restart deployments, or access other namespace Secrets. It reuses the
pre-provisioned device identity and never generates a replacement identity.

Both required HTTPS targets are checked every 15 seconds (plus request time).
Three failed rounds reconnect the same configuration. If that connection attempt
also fails, the watchdog requests another provider-advertised AWG location using
the existing public key and installation ID. A five-minute country-change cooldown
prevents flapping. Successful reconnects stop escalation. Authentication/rate-limit
responses (401/429) count as reachable; 403 and server errors trigger recovery.

The watchdog persists its pending country request before calling the provider and
uses Secret resource versions to avoid overwriting concurrent changes. Restarts
resume the same operation and device identity. Updated configuration and country
metadata arrive through Kubernetes' atomic Secret projection; the gateway detects
the new generation and reconnects without a pod restart. During this projection
delay the watchdog does not request another country. The current configuration is
preserved if provisioning fails. Subscription expiration still needs operator action.

Automatic country recovery uses `primary.conf`; the optional manual `backup.conf`
mechanism is used only when automatic country recovery is disabled.

```bash
kubectl --context admin@aof-k8s -n default get service kubernetes -o wide
kubectl --context admin@aof-k8s -n default get endpointslice \
  -l kubernetes.io/service-name=kubernetes -o wide
helm --kube-context admin@aof-k8s upgrade --install aof-agent-vpn ./k8s/agent-vpn \
  --namespace aof-agent-network --set image.tag=BUILD_TAG \
  --set 'imagePullSecrets[0].name=selectel-registry' --set failover.enabled=true \
  --set 'failover.apiCidrs[0]=SERVICE_IP/32' --set 'failover.apiCidrs[1]=API_ENDPOINT_IP/32' \
  --wait --timeout 5m
```

The internal health Service remains available while the VPN is unready, but only
the watchdog can reach its port under NetworkPolicy. It returns a filtered status
document, never VPN settings. The normal proxy Service still requires readiness.

After explicit authorization for a brief VPN outage, run the bounded live check
from `aof-agent`:

```bash
python3 vpn/verify_country_failover.py --context admin@aof-k8s --inject-outage
```

This blocks only the gateway pod's current encrypted UDP endpoint, observes the
failed reconnect before country change, and checks recovery, a different public
egress IP and unchanged device identity. Its fault rule is removed in `finally`;
the test never changes node or cluster-wide routing. Default timeout is 8 minutes.

Requires one IPv4 full-tunnel peer with a numeric IPv4 endpoint per file. AWG 3.1
userspace tools are pinned in the image. Address, MTU and AWG parameters are read
from the configuration; DNS comes from Helm `dnsServers`. IPv6 egress is blocked.
Executable hooks, custom route tables and SaveConfig are rejected. Unsupported
files fail without logging their contents. The `.conf` is still a secret: do not
paste its contents, comments or subscription keys into logs or tickets.

Confirm the cluster explicitly before making changes. The commands deliberately
require an explicitly supplied kubeconfig rather than the current default context.

```bash
export AOF_AGENT_KUBECONFIG=/absolute/path/to/approved-kubeconfig.yaml
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" config current-context
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" create namespace aof-agent-network
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" -n aof-agent-network create secret generic aof-agent-vpn-state \
  --from-file=primary.conf=/absolute/path/to/primary.conf
```

For two configurations, create the Secret with both `--from-file` arguments:

```bash
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" -n aof-agent-network create secret generic aof-agent-vpn-state \
  --from-file=primary.conf=/absolute/path/to/primary.conf \
  --from-file=backup.conf=/absolute/path/to/backup.conf
```

```bash
helm --kubeconfig "$AOF_AGENT_KUBECONFIG" upgrade --install aof-agent-vpn ./k8s/agent-vpn \
  --namespace aof-agent-network --set image.tag=BUILD_TAG \
  --set 'imagePullSecrets[0].name=selectel-registry' --wait --timeout 5m
```

The gateway needs NET_ADMIN and the host TUN character device, but not privileged
mode, SYS_MODULE, host networking, or Kubernetes API access. Confirm that the node
device permissions/runtime device policy and admission policy permit this mount.
Do not relax cluster-wide security policies to accommodate it. The proxy sidecar
runs as a nonroot user without capabilities and cannot read VPN configurations.
The CNI must enforce NetworkPolicy; test this before admitting real clients.

Routing changes stay inside the gateway pod. Its original main routing table is
preserved for encrypted endpoint traffic and replies to cluster clients; other
outbound connections use a separate tunnel table. No node or cluster-wide routes
are changed.

## Verification

```bash
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" -n aof-agent-network rollout status deployment/aof-agent-vpn
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" -n aof-agent-network logs deployment/aof-agent-vpn -c vpn
kubectl --kubeconfig "$AOF_AGENT_KUBECONFIG" -n aof-agent-network exec deployment/aof-agent-vpn -c vpn -- cat /status/health.json
```

Readiness requires a recent tunnel handshake plus HTTPS transport to both OpenAI
and Telegram through the proxy. Logs report the selected profile and public egress
IP when connected. HTTP 401/403/429 responses prove transport only; verify actual
account access separately. Compare egress IP with the expected provider location.

Liveness checks the supervisor heartbeat, not provider availability. After three
failed connectivity rounds, the tunnel is recreated with exponential backoff and
jitter (up to 63 seconds). Two consecutive failed connection attempts switch to the
other profile. A working backup stays selected; there is no disruptive periodic
failback. Failure of only one HTTPS service degrades readiness without repeatedly
restarting a working tunnel. Keepalive is set to 25 seconds. The firewall stays in
place while connecting, reconnecting, and shutting down.

Before accepting: verify primary connectivity, break the tunnel, confirm direct
HTTPS/DNS/IPv6 are blocked, restore it and observe recovery. With a backup, make
primary unreachable and verify backup selection and its egress IP. Also exercise
process death, pod restart, invalid/rotated configuration and partial provider
outage. Logs and pod readiness alone do not establish these properties.

Clients use `HTTPS_PROXY=http://aof-agent-vpn.aof-agent-network.svc.cluster.local:8888`.
Their pods need `app.kubernetes.io/part-of: aof-agent` in the `aof-agent` namespace.
Libraries must support HTTP CONNECT; verify the actual client library. For an
interactive local check, port-forward the Service and use `curl --proxy`.
The proxy only permits exact allowlisted hostnames on port 443, validates public
IPv4 destinations, and does not decrypt TLS. Add hosts deliberately when required.

Gateway policies do not prevent a client from bypassing its proxy. The eventual
agent deployment also needs its own enforced egress policy allowing this proxy
and explicitly approved internal services, with direct external access denied.

Secret updates are read on reconnect; adding/removing a backup or forcing an
immediate reload requires a rollout restart. Restarting interrupts active requests;
application retries must respect each API operation's idempotency semantics.
