# Lab 06 — Load Balancing & Managed Instance Groups

> **Cost warning:** This lab creates a regional Managed Instance Group (2 × e2-micro VMs)
> and a global HTTP(S) Load Balancer. Forwarding rules cost ~$0.025/hr; each e2-micro costs
> ~$0.008/hr. Estimated: **~$0.06/hr** (~$0.12 if completed in 2 hours). Run the Cleanup
> section promptly when you are done.

---

## Objectives

After completing this lab you will be able to:

- Create instance templates as immutable blueprints for VM fleets
- Create regional Managed Instance Groups (MIGs) spanning multiple zones
- Configure health checks and attach autohealing policies so MIGs self-repair
- Observe autohealing in action by deleting instances and watching them recreate
- Configure CPU-based autoscaling with min/max replica bounds
- Build a global HTTP(S) Load Balancer from the ground up using gcloud
- Explain every component of the HTTP(S) LB stack: forwarding rule, target proxy, URL map, backend service, health check
- Test load balancer traffic distribution and simulate a zone failure
- Perform a rolling update (canary pattern) on a live MIG without downtime

---

## Concepts

### Instance Templates

An **instance template** is an immutable, version-controlled blueprint that defines every
attribute of a VM: machine type, boot disk image, network tags, service account, metadata,
and startup script. Instance templates are global resources — they are not tied to a zone
or region.

The immutability constraint is intentional. Once you create a template, you cannot modify
it. Any change — even a minor one, like updating an environment variable in the startup
script — requires creating a new template. This forces you into an explicit versioning
discipline: every running fleet is traceable back to a named template version.

```bash
# Inspect a template's full definition
gcloud compute instance-templates describe TEMPLATE_NAME --format=yaml
```

On AWS, the equivalent is a **Launch Template** (or the older Launch Configuration). GCP
instance templates were designed at roughly the same time and serve the same purpose, but
they are global rather than regional.

### Managed vs Unmanaged Instance Groups

| Feature | Managed Instance Group (MIG) | Unmanaged Instance Group |
|---|---|---|
| Instance creation | Automatically from a template | You add VMs manually |
| Auto-healing | Yes — uses health check to detect and replace unhealthy instances | No |
| Autoscaling | Yes | No |
| Rolling updates | Yes — controlled rollout with max surge/unavailable | No |
| Load balancer backend | Yes (recommended) | Yes (but limited) |
| Use case | Stateless services, web tiers, batch workers | Legacy groupings, stateful VMs with varying configs |

The ACE exam almost always means MIG when it asks about load-balanced instance groups.
Unmanaged groups exist for backward compatibility — you will rarely create one from scratch.

### Zonal vs Regional MIGs

A **zonal MIG** places all instances in a single zone (e.g. `us-central1-a`). If that zone
has an outage, all your instances go down together.

A **regional MIG** spreads instances across multiple zones within a region (e.g.
`us-central1-a`, `us-central1-b`, `us-central1-c`). GCP automatically distributes instances
evenly. A zone outage takes out only a fraction of your capacity, and the load balancer
routes traffic away from the failed zone automatically.

```
Regional MIG (us-central1):
  ├── us-central1-a:  2 instances
  ├── us-central1-b:  2 instances
  └── us-central1-c:  2 instances
```

For production workloads, always use a regional MIG unless you have a specific reason for
zone affinity (e.g. GPU availability, data locality for local SSDs).

### Autoscaling

Autoscaling lets a MIG grow and shrink its instance count in response to load. The
autoscaler evaluates a target metric at a configurable interval (default: 60 seconds) and
adds or removes instances to keep the metric at the target value.

**Scale-out** (adding instances) happens when the metric is above the target.
**Scale-in** (removing instances) happens when the metric is below the target, but only
after the **cooldown period** (default: 60 seconds) and a **stabilization window** (default:
10 minutes) have elapsed. The stabilization window prevents rapid oscillation — GCP will
not scale in until the signal has been consistently low for the full window.

```
Metric: CPU utilization, target: 60%
Current avg CPU: 85%  → autoscaler adds instances
Current avg CPU: 25%  → autoscaler waits stabilization window, then removes instances
```

Common autoscaling signals:
- **CPU utilization** — most common, good for compute-bound workloads
- **HTTP load balancing serving capacity** — based on requests per second (RPS) relative to a per-instance maximum
- **Cloud Monitoring custom metric** — Pub/Sub queue depth, application-level metrics
- **Schedule-based** — add capacity before known peak times (e.g. market open, nightly batch)

### Auto-Healing

Auto-healing is separate from autoscaling. Where autoscaling controls _how many_ instances
exist, auto-healing controls _which_ instances exist — it replaces unhealthy ones.

The process:
1. A health check polls each instance on a configured port and path.
2. If an instance fails `unhealthyThreshold` consecutive checks, the MIG marks it `UNHEALTHY`.
3. After the `initialDelaySec` grace period (to allow slow startup), the MIG deletes the
   unhealthy instance and recreates it from the template.
4. The replacement instance starts fresh — same template, new VM.

```
Health check: HTTP GET /healthz every 10s, timeout 5s
unhealthyThreshold: 3 consecutive failures → instance is deleted and replaced
initialDelaySec: 120 (give the VM 2 minutes to boot before checking)
```

> **ACE exam tip:** The `initialDelaySec` grace period is on the _autohealing policy_, not
> on the health check itself. The health check's `check-interval` and `timeout` are about
> how quickly you _detect_ a failure; `initialDelaySec` is about how long you wait before
> _acting_ on it.

### Load Balancer Types

GCP has multiple load balancer products. Choosing the right one is a common exam topic.

| Load Balancer | Layer | Scope | Protocols | Key Features | Use When |
|---|---|---|---|---|---|
| Global external HTTP(S) LB | 7 | Global | HTTP, HTTPS, HTTP/2, gRPC | Cloud CDN, Cloud Armor, URL routing, global anycast IP | Public web apps, APIs needing CDN or WAF |
| Global external SSL Proxy LB | 4 | Global | SSL/TLS (non-HTTP) | Global anycast, SSL offload | Non-HTTP SSL traffic (e.g. IMAP, MQTT) |
| Global external TCP Proxy LB | 4 | Global | TCP (non-SSL) | Global anycast, TCP offload | Non-SSL TCP traffic at global scale |
| Regional external HTTP(S) LB | 7 | Regional | HTTP, HTTPS | URL routing, no CDN | Regional APIs, lower latency regional routing |
| Regional internal HTTP(S) LB | 7 | Regional | HTTP, HTTPS | VPC-internal only, no public IP | Internal microservices, east-west traffic |
| External passthrough Network LB | 4 | Regional | Any TCP/UDP | Preserves source IP, ultra-low latency | Gaming, VOIP, protocols needing real client IP |
| Internal passthrough Network LB | 4 | Regional | Any TCP/UDP | VPC-internal only, source IP preserved | Internal services needing any protocol |

> **ACE exam tip:** The passthrough Network LB is the only load balancer that preserves
> the client's source IP address all the way to the backend. If an exam question mentions
> "real client IP" or "source IP preservation," the answer is Network LB (passthrough).

### HTTP(S) Load Balancer Component Stack

The global HTTP(S) LB is not a single resource — it is a chain of five distinct GCP
resources. Understanding each one is required for the exam and for debugging real deployments.

```
Internet → [Forwarding Rule] → [Target HTTP(S) Proxy] → [URL Map] → [Backend Service] → [MIG + Health Check]
```

| Component | What it does | Analogy |
|---|---|---|
| **Forwarding rule** | Binds a global IP address + port to a target proxy. Traffic enters here. | The "listener" in AWS ALB terms |
| **Target HTTP(S) proxy** | Terminates SSL (for HTTPS), then evaluates the URL map. One proxy per LB. | The SSL termination layer |
| **URL map** | Routes requests to different backend services based on host header and URL path. | ALB listener rules / path-based routing |
| **Backend service** | Holds one or more backend groups (MIGs), a health check, session affinity policy, CDN policy, and timeout. | ALB target group (but more powerful) |
| **Health check** | Used by the backend service to probe backend instances and determine readiness. | ALB target group health check |

The URL map is the routing brain. A single URL map can route:
- `example.com/api/*` → backend-service-api (MIG running API servers)
- `example.com/static/*` → backend-service-cdn (Cloud CDN-enabled bucket)
- `app.example.com/*` → backend-service-app (MIG running app servers)

### SSL Certificates

For HTTPS you need an SSL certificate attached to the target HTTPS proxy.

| Type | Management | Renewal | Use When |
|---|---|---|---|
| Google-managed | GCP creates and renews automatically | Auto | You own the domain and can set DNS; easiest option |
| Self-managed (uploaded) | You upload a cert + private key | Manual (you must rotate before expiry) | You have an existing certificate, or need wildcard certs |
| Self-managed (Certificate Manager) | Managed through Certificate Manager service | Can be automated | Large fleets, multiple domains, complex issuance |

Google-managed certificates require your domain to be publicly resolvable and point at the
load balancer's IP before GCP will issue the cert. For this lab we use HTTP only (no cert
needed) to keep things simple.

---

## Setup

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE_A="us-central1-a"
export ZONE_B="us-central1-b"
echo "Project: ${PROJECT_ID}, Region: ${REGION}"
```

### Network

This lab deploys instances into the default VPC. If you completed lab 05 and want to use
the custom VPC you built there, substitute `--network=lab05-vpc --subnet=lab05-web-subnet`
in the instance template command. Using the default VPC is fine for this lab.

---

## Exercises

### Exercise 1 — Create an Instance Template with an nginx Startup Script

An instance template defines a startup script in its metadata. Every VM the MIG creates
will execute this script on first boot. The script installs nginx and serves a simple page
that identifies which VM and zone is responding — this makes it easy to verify the load
balancer is distributing traffic across instances.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud compute instance-templates create lab06-web-template \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --network=default \
  --tags=http-server \
  --metadata-from-file=startup-script=startup-script-v1.sh \
  --project="${PROJECT_ID}"
```

> Run this command from the `lab-06-load-balancing/` directory so that `startup-script-v1.sh` resolves correctly. The script source is at [`startup-script-v1.sh`](./startup-script-v1.sh).

Verify the template was created:

```bash
gcloud compute instance-templates describe lab06-web-template \
  --format="table(name,properties.machineType,properties.tags.items)"
```

Expected output:
```
NAME                MACHINE_TYPE  TAGS
lab06-web-template  e2-micro      http-server
```

Also create a firewall rule to allow HTTP traffic to VMs with the `http-server` tag (if
you do not already have one from lab 02 or lab 05):

```bash
gcloud compute firewall-rules create default-allow-http \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Rule already exists — skipping."
```

> **Why tags matter here:** The firewall rule uses `--target-tags=http-server`. The instance
> template sets `--tags=http-server`. When the MIG creates VMs from this template, each VM
> automatically inherits the tag and becomes reachable on port 80. This is the same
> tag-based firewall pattern introduced in lab 05.

---

### Exercise 2 — Create a Regional MIG from the Template

A regional MIG distributes instances across zones automatically. You specify a target size
(total instances across all zones) and which zones to use. GCP divides the instances as
evenly as possible.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud compute instance-groups managed create lab06-web-mig \
  --template=lab06-web-template \
  --size=2 \
  --region="${REGION}" \
  --zones="us-central1-a,us-central1-b" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/regions/us-central1/instanceGroupManagers/lab06-web-mig].
NAME           LOCATION     SCOPE   BASE_INSTANCE_NAME  SIZE  TARGET_SIZE  INSTANCE_TEMPLATE   AUTOSCALED
lab06-web-mig  us-central1  region  lab06-web-mig       0     2            lab06-web-template  no
```

The `SIZE` starts at 0 and climbs to `TARGET_SIZE` as GCP provisions the VMs. Watch
instance status until both show `RUNNING` (takes ~60-90 seconds), then Ctrl+C:

```bash
watch -n 5 "gcloud compute instance-groups managed list-instances lab06-web-mig \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format='table(name,zone,status,instanceStatus)'"
```

Expected output once stable:
```
NAME                 ZONE           STATUS   INSTANCE_STATUS
lab06-web-mig-xxxx   us-central1-a  RUNNING  RUNNING
lab06-web-mig-yyyy   us-central1-b  RUNNING  RUNNING
```

> **ACE exam tip:** `--size` in the `create` command sets the _initial_ target size, not
> a fixed size. Once you attach an autoscaler (exercise 5), the autoscaler takes over control
> of the target size. Without an autoscaler the MIG simply maintains whatever target size
> you set.

---

### Exercise 3 — Configure a Health Check for Auto-Healing

A health check for auto-healing is an HTTP probe that hits each instance on port 80 at the
path `/`. If an instance fails 3 consecutive checks (with a 10-second interval), the MIG
marks it unhealthy and schedules a replacement.

First, create the health check:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute health-checks create http lab06-health-check \
  --port=80 \
  --request-path=/ \
  --check-interval=10s \
  --timeout=5s \
  --healthy-threshold=2 \
  --unhealthy-threshold=3 \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/healthChecks/lab06-health-check].
NAME                PROTOCOL
lab06-health-check  HTTP
```

Now attach the health check to the MIG as an autohealing policy. The `--initial-delay=120`
gives each new VM 2 minutes to boot and start nginx before health checks can trigger a
replacement — without this grace period, slow-starting VMs would be deleted before they
finish starting up:

```bash
REGION="us-central1"

gcloud compute instance-groups managed update lab06-web-mig \
  --region="${REGION}" \
  --health-check=lab06-health-check \
  --initial-delay=120 \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/regions/us-central1/instanceGroupManagers/lab06-web-mig].
```

Verify the autohealing policy is attached:

```bash
gcloud compute instance-groups managed describe lab06-web-mig \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(autoHealingPolicies)"
```

Expected output:
```yaml
autoHealingPolicies:
- healthCheck: https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/healthChecks/lab06-health-check
  initialDelaySec: 120
```

Now allow health check probes to reach your instances. GCP health checkers originate from
the ranges `130.211.0.0/22` and `35.191.0.0/16`:

```bash
gcloud compute firewall-rules create allow-health-checks \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=130.211.0.0/22,35.191.0.0/16 \
  --target-tags=http-server \
  --project="${PROJECT_ID}"
```

> **ACE exam tip:** If you forget to add this firewall rule, your backend service will show
> all instances as `UNHEALTHY` in the load balancer — even though the VMs are running. This
> is a very common misconfiguration and a frequent exam scenario.

---

### Exercise 4 — Watch Auto-Healing: Delete an Instance and Observe Recreation

This exercise deliberately breaks something to demonstrate auto-healing. You will manually
delete one of the MIG's instances and watch the MIG detect the missing instance and
create a replacement.

Get the name of one of your instances:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

INSTANCE_TO_DELETE=$(gcloud compute instance-groups managed list-instances lab06-web-mig \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(name)" | head -1)

echo "Will delete: ${INSTANCE_TO_DELETE}"
```

Delete the instance directly (bypassing the MIG — notice you are deleting the VM, not
the MIG itself):

```bash
# Extract zone from the full instance URL
INSTANCE_ZONE=$(gcloud compute instances list \
  --filter="name=${INSTANCE_TO_DELETE}" \
  --format="value(zone)" \
  --project="${PROJECT_ID}")

echo "Instance zone: ${INSTANCE_ZONE}"

gcloud compute instances delete "${INSTANCE_TO_DELETE}" \
  --zone="${INSTANCE_ZONE}" \
  --quiet \
  --project="${PROJECT_ID}"
```

Expected output:
```
Deleted [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/zones/us-central1-a/instances/lab06-web-mig-xxxx].
```

Watch the MIG notice the instance count dropped below target and create a replacement.
Ctrl+C once both instances show `RUNNING`:

```bash
watch -n 5 "gcloud compute instance-groups managed list-instances lab06-web-mig \
  --region=${REGION} \
  --project=${PROJECT_ID} \
  --format='table(name,zone,status,instanceStatus,currentAction)'"
```

You will see the MIG cycle through states before settling:

```
NAME                 ZONE           STATUS   INSTANCE_STATUS  CURRENT_ACTION
lab06-web-mig-yyyy   us-central1-b  RUNNING  RUNNING          NONE
lab06-web-mig-zzzz   us-central1-a  RUNNING  RUNNING          NONE
```

Notice the new instance has a different random suffix — it is a brand-new VM created from
the template, not the old one restored.

> **What about the `initialDelaySec` from exercise 3?** When you _manually delete_ an
> instance, the MIG replaces it immediately without waiting for `initialDelaySec`. The grace
> period only applies to _health-check-triggered_ replacements — i.e. when an instance is
> running but failing health checks. This distinction matters: a crashed VM gets replaced
> right away; a degraded-but-alive VM gets the grace period before replacement.

---

### Exercise 5 — Configure Autoscaling

Add a CPU-based autoscaler to the MIG. The autoscaler will add instances when average CPU
utilization across the group exceeds 60%, and remove them when it stays below that threshold
for the stabilization window. Set min=2 and max=5 replicas.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud compute instance-groups managed set-autoscaling lab06-web-mig \
  --region="${REGION}" \
  --min-num-replicas=2 \
  --max-num-replicas=5 \
  --target-cpu-utilization=0.60 \
  --cool-down-period=60 \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/regions/us-central1/autoscalers/lab06-web-mig].
---
autoscalingPolicy:
  coolDownPeriodSec: 60
  cpuUtilization:
    utilizationTarget: 0.6
  maxNumReplicas: 5
  minNumReplicas: 2
  mode: ON
```

Describe the autoscaler to see its current recommendation:

```bash
gcloud compute instance-groups managed describe lab06-web-mig \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(autoscaler)"
```

The autoscaler will show `recommendedSize: 2` because the instances are idle. You are not
going to generate artificial load in this lab (that would cost extra time), but you can
verify the configuration is in place and understand the scaling logic.

> **Cooldown period vs stabilization window:** The `--cool-down-period` (60 seconds here)
> is the time the autoscaler waits after adding instances before it evaluates the metric
> again. This prevents it from over-provisioning by acting on transient spikes that the
> newly added instances have not yet absorbed. The separate stabilization window (not
> configurable via gcloud, defaults to 10 minutes) controls scale-in — the autoscaler
> will not remove instances until load has been consistently low for that window.

---

### Exercise 6 — Create a Global HTTP(S) Load Balancer

Building a global HTTP(S) load balancer requires creating each component of the stack
individually. Work through them in order from backend to front-end.

#### Step 6a — Reserve a Global Static IP Address

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute addresses create lab06-lb-ip \
  --ip-version=IPV4 \
  --global \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/addresses/lab06-lb-ip].
```

Get the reserved IP address — you will need it to test the LB:

```bash
LB_IP=$(gcloud compute addresses describe lab06-lb-ip \
  --global \
  --format="value(address)" \
  --project="${PROJECT_ID}")
echo "Load balancer IP: ${LB_IP}"
```

#### Step 6b — Create the Backend Service

The backend service holds the connection between the load balancer and your MIG. It also
defines the health check used for traffic routing (separate from the autohealing health
check, though you can reuse the same resource):

```bash
REGION="us-central1"

# Create backend service
gcloud compute backend-services create lab06-backend-service \
  --protocol=HTTP \
  --port-name=http \
  --health-checks=lab06-health-check \
  --global \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/backendServices/lab06-backend-service].
NAME                    BACKENDS  PROTOCOL
lab06-backend-service             HTTP
```

Add the MIG as a backend to the backend service:

```bash
gcloud compute backend-services add-backend lab06-backend-service \
  --instance-group=lab06-web-mig \
  --instance-group-region="${REGION}" \
  --balancing-mode=UTILIZATION \
  --max-utilization=0.8 \
  --capacity-scaler=1.0 \
  --global \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/backendServices/lab06-backend-service].
```

#### Step 6c — Create the URL Map

The URL map routes all incoming requests to the backend service. In this lab you will use a
simple default route (all requests go to one backend). In production you would add path
matchers to route `/api/*` and `/static/*` to different backends.

```bash
gcloud compute url-maps create lab06-url-map \
  --default-service=lab06-backend-service \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/urlMaps/lab06-url-map].
NAME            DEFAULT_SERVICE
lab06-url-map   backendServices/lab06-backend-service
```

#### Step 6d — Create the Target HTTP Proxy

The target proxy links the URL map to the forwarding rule:

```bash
gcloud compute target-http-proxies create lab06-http-proxy \
  --url-map=lab06-url-map \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/targetHttpProxies/lab06-http-proxy].
NAME              URL_MAP
lab06-http-proxy  lab06-url-map
```

#### Step 6e — Create the Forwarding Rule

The forwarding rule is the entry point: it binds the global IP to port 80 and sends
traffic to the target proxy:

```bash
gcloud compute forwarding-rules create lab06-forwarding-rule \
  --address=lab06-lb-ip \
  --global \
  --target-http-proxy=lab06-http-proxy \
  --ports=80 \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/forwardingRules/lab06-forwarding-rule].
NAME                    REGION  IP_ADDRESS      IP_PROTOCOL  TARGET
lab06-forwarding-rule           34.xxx.xxx.xxx  TCP          lab06-http-proxy
```

The load balancer stack is now complete. Confirm the full chain by describing the URL map:

```bash
gcloud compute url-maps describe lab06-url-map \
  --project="${PROJECT_ID}" \
  --format="yaml(name,defaultService)"
```

> **ACE exam tip:** The five resources (forwarding rule, target proxy, URL map, backend
> service, health check) are all separate gcloud resource types. The exam may ask which
> resource you would modify to change routing logic (URL map), which to change SSL
> termination (target HTTPS proxy + certificate), or which to change timeout
> (backend service).

---

### Exercise 7 — Test the Load Balancer and Verify Traffic Distribution

The load balancer takes 2–3 minutes to fully propagate after creation. Global anycast IP
provisioning is not instantaneous — GCP needs to program its edge points of presence.

Wait for the backend service to report healthy backends:

```bash
PROJECT_ID=$(gcloud config get-value project)

# Poll backend health — wait for HEALTHY status
gcloud compute backend-services get-health lab06-backend-service \
  --global \
  --project="${PROJECT_ID}"
```

Initially you may see `UNKNOWN` or `UNHEALTHY` while the LB warms up:

```yaml
---
backend: https://www.googleapis.com/compute/v1/projects/.../instanceGroups/lab06-web-mig
status:
  healthStatus:
  - healthState: UNKNOWN
    instance: https://.../instances/lab06-web-mig-xxxx
```

After 2–3 minutes it should show `HEALTHY`:

```yaml
status:
  healthStatus:
  - healthState: HEALTHY
    instance: https://.../instances/lab06-web-mig-xxxx
  - healthState: HEALTHY
    instance: https://.../instances/lab06-web-mig-yyyy
```

Get the load balancer IP and test it:

```bash
LB_IP=$(gcloud compute addresses describe lab06-lb-ip \
  --global \
  --format="value(address)" \
  --project="${PROJECT_ID}")

echo "Testing load balancer at: http://${LB_IP}"
curl -s "http://${LB_IP}"
```

Expected output (shows instance name and zone from the startup script):

```html
<!DOCTYPE html>
<html>
<head><title>Lab 06 - Load Balancing</title></head>
<body>
<h1>Hello from lab06-web-mig-xxxx</h1>
<p>Zone: us-central1-a</p>
<p>Served by: nginx on Compute Engine (MIG)</p>
</body>
</html>
```

Hit the LB multiple times to observe traffic distribution across instances. Because HTTP
is stateless and the LB uses round-robin by default, you should see responses from
different instances and zones:

```bash
# Send 10 requests and capture the instance name from each response
for i in $(seq 1 10); do
  curl -s "http://${LB_IP}" | grep "Hello from"
done
```

Expected output (instance names and zones will vary):

```
<h1>Hello from lab06-web-mig-xxxx</h1>
<h1>Hello from lab06-web-mig-yyyy</h1>
<h1>Hello from lab06-web-mig-xxxx</h1>
<h1>Hello from lab06-web-mig-yyyy</h1>
...
```

You should see responses alternating between your two instances in different zones.

> **Note on session affinity:** By default the HTTP(S) LB uses no session affinity
> (pure round-robin per connection). You can enable `CLIENT_IP`, `CLIENT_IP_PORT`,
> or `GENERATED_COOKIE` affinity on the backend service if your application needs
> sticky sessions. For stateless apps, no affinity is preferred.

---

### Exercise 8 — Simulate a Zone Failure

Real zone failures are rare but impactful. This exercise simulates one by setting the
per-zone instance count to zero for one zone, forcing all traffic onto the surviving zone.

First check how many instances are in each zone:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud compute instance-groups managed list-instances lab06-web-mig \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="table(name,zone,status)"
```

Now use `set-target-pools` — actually you will resize the MIG to simulate zone depletion
by abandoning the instances in one zone. The cleaner approach is to use
`resize-advanced` to pin a zone to zero:

```bash
# Set us-central1-a to 0 instances, keep us-central1-b at 2
# This simulates losing an entire zone
gcloud compute instance-groups managed resize-advanced lab06-web-mig \
  --region="${REGION}" \
  --target-size-per-zone="us-central1-a=0,us-central1-b=2" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/regions/us-central1/instanceGroupManagers/lab06-web-mig].
```

Wait for the resize to complete:

```bash
gcloud compute instance-groups managed wait-until lab06-web-mig \
  --stable \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Now test the load balancer — all traffic should be routed to `us-central1-b` only:

```bash
LB_IP=$(gcloud compute addresses describe lab06-lb-ip \
  --global \
  --format="value(address)" \
  --project="${PROJECT_ID}")

for i in $(seq 1 6); do
  curl -s "http://${LB_IP}" | grep "Zone:"
done
```

Expected output — all responses from `us-central1-b`:

```
<p>Zone: us-central1-b</p>
<p>Zone: us-central1-b</p>
<p>Zone: us-central1-b</p>
<p>Zone: us-central1-b</p>
<p>Zone: us-central1-b</p>
<p>Zone: us-central1-b</p>
```

The load balancer automatically detected that `us-central1-a` has no healthy backends and
routed all traffic to the available zone. This happened with zero downtime because the
global HTTP(S) LB health checks continuously probe each backend and drain traffic from
failing backends before removing them from rotation.

Restore the original distribution before proceeding:

```bash
gcloud compute instance-groups managed resize-advanced lab06-web-mig \
  --region="${REGION}" \
  --target-size-per-zone="us-central1-a=1,us-central1-b=1" \
  --project="${PROJECT_ID}"

gcloud compute instance-groups managed wait-until lab06-web-mig \
  --stable \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

---

### Exercise 9 — Rolling Update: Canary Deployment Pattern

A rolling update lets you push a new instance template (and therefore a new application
version) to a live MIG without downtime. The canary pattern deploys the new version to a
small percentage of instances first, lets you verify it works, then rolls it out to
the rest.

#### Step 9a — Create a New Template Version

Create a v2 template with an updated HTML page. In a real deployment this would reference
a new container image or startup script that pulls a new application artifact:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute instance-templates create lab06-web-template-v2 \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --network=default \
  --tags=http-server \
  --metadata-from-file=startup-script=startup-script-v2.sh \
  --project="${PROJECT_ID}"
```

> Run this command from the `lab-06-load-balancing/` directory so that `startup-script-v2.sh` resolves correctly. The script source is at [`startup-script-v2.sh`](./startup-script-v2.sh).

#### Step 9b — Start a Canary Rollout

Use `rolling-action start-update` with `--canary-version` to deploy v2 to exactly 1
instance (50% of a 2-instance MIG) while keeping v1 on the remaining instance:

```bash
REGION="us-central1"

gcloud compute instance-groups managed rolling-action start-update lab06-web-mig \
  --region="${REGION}" \
  --version="template=lab06-web-template" \
  --canary-version="template=lab06-web-template-v2,target-size=1" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/regions/us-central1/instanceGroupManagers/lab06-web-mig].
```

Wait for the canary instance to be replaced:

```bash
gcloud compute instance-groups managed wait-until lab06-web-mig \
  --stable \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

#### Step 9c — Verify the Canary

Hit the load balancer several times. You should see roughly half the responses showing
`[v2]`:

```bash
LB_IP=$(gcloud compute addresses describe lab06-lb-ip \
  --global \
  --format="value(address)" \
  --project="${PROJECT_ID}")

for i in $(seq 1 8); do
  curl -s "http://${LB_IP}" | grep -E "(Hello from|Version)"
done
```

Expected output (mix of v1 and v2):

```
<h1>Hello from lab06-web-mig-aaaa</h1>
<h1>Hello from lab06-web-mig-bbbb [v2]</h1>
<p>Version: 2.0 - Green deployment</p>
<h1>Hello from lab06-web-mig-aaaa</h1>
<h1>Hello from lab06-web-mig-bbbb [v2]</h1>
...
```

#### Step 9d — Complete the Rollout (Promote Canary)

Once you are confident v2 is healthy, promote it to all instances:

```bash
gcloud compute instance-groups managed rolling-action start-update lab06-web-mig \
  --region="${REGION}" \
  --version="template=lab06-web-template-v2" \
  --project="${PROJECT_ID}"

gcloud compute instance-groups managed wait-until lab06-web-mig \
  --stable \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Verify all responses now show v2:

```bash
for i in $(seq 1 6); do
  curl -s "http://${LB_IP}" | grep -E "(Hello from|Version)"
done
```

Expected output:

```
<h1>Hello from lab06-web-mig-cccc [v2]</h1>
<p>Version: 2.0 - Green deployment</p>
<h1>Hello from lab06-web-mig-dddd [v2]</h1>
<p>Version: 2.0 - Green deployment</p>
...
```

> **ACE exam tip:** Rolling updates use two key parameters: `--max-surge` (extra instances
> created above target size during update, default=1) and `--max-unavailable` (instances
> that can be down during update, default=1). Setting `--max-surge=1` and
> `--max-unavailable=0` gives a zero-downtime update: GCP creates a new instance with the
> new template, waits for it to pass health checks, then deletes an old instance, and
> repeats. This is the safest option for production; it temporarily costs one extra VM.

---

## Key Takeaways

- Instance templates are **immutable** — any change requires a new template. This is a
  feature, not a limitation: it enforces version discipline and makes rollbacks trivial.

- **Managed Instance Groups (MIGs)** provide auto-healing, autoscaling, and rolling
  updates. Unmanaged instance groups provide none of these — prefer MIGs for all new
  workloads.

- **Regional MIGs** span multiple zones within a region and are required for
  high-availability deployments. A zone outage affects only a fraction of capacity.

- **Auto-healing** is triggered by health check failures, not by instance deletion.
  When you manually delete an instance, the MIG replaces it immediately. The
  `initialDelaySec` grace period only applies to health-check-triggered repairs.

- The global HTTP(S) LB stack has five distinct resources: forwarding rule → target proxy
  → URL map → backend service → (MIG + health check). Each one is independently
  configurable.

- **Health check firewall rules** must allow traffic from `130.211.0.0/22` and
  `35.191.0.0/16`. Forgetting this rule causes all backends to appear `UNHEALTHY`.

- The **passthrough Network LB** (layer 4, regional) is the only GCP load balancer that
  preserves the client's source IP address. All other load balancers use SNAT or proxy
  the connection.

- **Google-managed SSL certificates** auto-renew — attach them to a target HTTPS proxy
  and GCP handles issuance and renewal. Your domain must resolve to the LB IP before
  Google will issue the certificate.

- **Rolling updates** use `--max-surge` and `--max-unavailable` to control the trade-off
  between speed, cost, and downtime. `max-surge=1, max-unavailable=0` is zero-downtime
  at the cost of one extra VM during the update.

- **Autoscaler cooldown period** prevents thrashing on scale-out. The separate
  **stabilization window** (default 10 min) prevents premature scale-in. Both exist to
  avoid oscillation.

- The global HTTP(S) LB supports **Cloud CDN** and **Cloud Armor** (WAF) — these are
  configured at the backend service level. The Network LB does not support either.

---

## Cleanup

Run all of these commands to destroy every resource created in this lab. The commands are
ordered to satisfy dependency constraints (you must delete the forwarding rule before the
proxy, the proxy before the URL map, etc.).

```bash
# Check what exists before cleanup
../status.sh 6
```

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

echo "=== Deleting forwarding rule ==="
gcloud compute forwarding-rules delete lab06-forwarding-rule \
  --global \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting target HTTP proxy ==="
gcloud compute target-http-proxies delete lab06-http-proxy \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting URL map ==="
gcloud compute url-maps delete lab06-url-map \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting backend service ==="
gcloud compute backend-services delete lab06-backend-service \
  --global \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting health check ==="
gcloud compute health-checks delete lab06-health-check \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting MIG ==="
gcloud compute instance-groups managed delete lab06-web-mig \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting instance templates ==="
gcloud compute instance-templates delete lab06-web-template \
  --quiet \
  --project="${PROJECT_ID}"

gcloud compute instance-templates delete lab06-web-template-v2 \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Releasing static IP address ==="
gcloud compute addresses delete lab06-lb-ip \
  --global \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting firewall rule ==="
gcloud compute firewall-rules delete allow-health-checks \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Cleanup complete ==="
```

Verify nothing remains:

```bash
echo "--- MIGs ---"
gcloud compute instance-groups managed list \
  --filter="name:lab06" \
  --project="${PROJECT_ID}"

echo "--- Instance templates ---"
gcloud compute instance-templates list \
  --filter="name:lab06" \
  --project="${PROJECT_ID}"

echo "--- Backend services ---"
gcloud compute backend-services list \
  --filter="name:lab06" \
  --global \
  --project="${PROJECT_ID}"

echo "--- Forwarding rules ---"
gcloud compute forwarding-rules list \
  --filter="name:lab06" \
  --global \
  --project="${PROJECT_ID}"

../status.sh 6
```

All sections should be empty. If any resources remain, delete them individually
using the resource type and name shown.

> If you created the `default-allow-http` firewall rule in exercise 1 and did not have it
> before this lab, you may want to delete it as well:
> ```bash
> gcloud compute firewall-rules delete default-allow-http --quiet --project="${PROJECT_ID}"
> ```
> If this rule existed before lab 06, leave it in place — other labs use it.
