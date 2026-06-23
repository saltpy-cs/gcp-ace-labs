# Lab 08 — Serverless & PaaS

> **Cost warning:** Cloud Run and Cloud Functions have generous free tiers (2M requests/month
> free). App Engine has a free tier (28 instance-hours/day free for F1 instances). Estimated:
> **< $0.01** for this lab if destroyed promptly. The Cloud SQL instance in exercise 9
> costs ~$0.015/hr while running — delete it immediately after that exercise.

---

## Objectives

After completing this lab you will be able to:

- Deploy containerised applications to Cloud Run using `gcloud run deploy`
- Observe and measure cold start behaviour in Cloud Run
- Split traffic between Cloud Run revisions to implement canary deployments
- Configure Cloud Run min/max instances and concurrency settings to eliminate cold starts
- Deploy Cloud Functions (Gen 2) with HTTP triggers
- Deploy Cloud Functions (Gen 2) with Pub/Sub triggers
- Deploy an App Engine Standard application
- Configure App Engine traffic splitting between versions
- Connect Cloud Run to Cloud SQL via a Unix socket
- Choose the right serverless product for a given workload

---

## Concepts

### The Serverless Spectrum

"Serverless" means you do not manage the underlying infrastructure — no VMs to patch, no
clusters to resize, no operating systems to update. GCP offers four managed compute
options that sit above raw Compute Engine VMs. Understanding when to choose each one is
one of the most frequently tested topics in the ACE exam.

The key question to ask is: **what is the unit of deployment?**

| Feature | Cloud Run | Cloud Functions Gen 2 | App Engine Standard | App Engine Flexible |
|---|---|---|---|---|
| Unit of deployment | Container image | Source code (single function) | Source code (app/version) | Container image |
| Invocation | HTTP / gRPC / events | HTTP / events | HTTP only | HTTP only |
| Cold start | Yes (configurable) | Yes (configurable) | Yes | No (min 1 instance always warm) |
| Scales to zero | Yes | Yes | Yes | No |
| Max timeout per request | 60 minutes | 60 minutes | 10 minutes | No enforced limit |
| Supported runtimes | Any (container) | Node.js, Python, Go, Java, Ruby, PHP, .NET | Fixed per-version runtimes | Any (container) |
| Language version flexibility | Full (you define the image) | GCP-maintained buildpacks | Pinned to supported runtime versions | Full (you define the image) |
| Price model | Per request + CPU/memory while handling requests | Per invocation + CPU/memory during execution | Per instance-hour (F1/B1 etc.) | Per vCPU/memory-hour |
| Built-in queue / cron support | No (use Cloud Tasks / Cloud Scheduler) | No | Yes (native Tasks, Cron, Memcache) | Yes |
| VPC connectivity | Yes (Serverless VPC Access) | Yes (Serverless VPC Access) | Yes | Yes (directly in VPC) |
| Concurrent requests per instance | Configurable (default 80, max 1000) | 1 (Gen 1) / configurable (Gen 2) | Configurable per runtime | Configurable |

On AWS, the rough equivalents are:
- Cloud Run → **AWS Fargate** (container-based, no cluster management)
- Cloud Functions → **AWS Lambda**
- App Engine Standard → **AWS Elastic Beanstalk** (managed PaaS, less serverless)
- App Engine Flexible → **AWS Elastic Beanstalk** with custom platform branches

The table above hides a subtle point: **Cloud Functions Gen 2 is built on Cloud Run**.
Every Gen 2 function is actually a Cloud Run service under the hood — GCP provisions it
for you from your source code, but the execution environment is identical. This means
Gen 2 functions inherit Cloud Run's longer timeouts, larger memory limits, and ability to
handle multiple concurrent requests per instance.

### Cloud Run

Cloud Run is the recommended default for new serverless workloads on GCP. You package
your application as a container image, push it to Artifact Registry (or Container
Registry), and Cloud Run handles everything else: provisioning, scaling, load balancing,
TLS termination, and health checking.

**The contract:** your container must listen for HTTP (or gRPC) requests on the port
defined by the `PORT` environment variable (default: 8080). Cloud Run sends requests to
that port and will scale your container from zero to thousands of instances depending on
traffic.

```
Request arrives
    │
    ▼
Cloud Run ingress (GCP-managed HTTPS endpoint)
    │  TLS terminated, forwarded as HTTP internally
    ▼
Container instance (your code, listening on $PORT)
    │
    ▼
Response
```

### Cloud Run Revisions

Every deployment to Cloud Run creates a new **revision** — an immutable snapshot of your
container image plus all the configuration at that moment (environment variables, memory
limits, concurrency, etc.). Revisions are never modified. When you redeploy, a new
revision is created.

This is the same immutability philosophy as Compute Engine instance templates (lab 06).
Immutability makes rollbacks trivial: to roll back, redirect traffic to an earlier revision.

**Traffic splitting** lets you send a percentage of traffic to each revision. This enables:
- **Canary deployment:** 5% to new revision, 95% to stable revision
- **Blue/green deployment:** switch 100% instantly from one revision to another
- **A/B testing:** 50/50 split to measure which revision performs better

```bash
# Example: 90% to v3 (stable), 10% to v4 (canary)
gcloud run services update-traffic my-service \
  --to-revisions=my-service-00003-abc=90,my-service-00004-def=10 \
  --region=us-central1
```

### Cold Starts

A **cold start** occurs when Cloud Run needs to start a new container instance to handle
a request. The user's request waits while the container boots, your application
initialises, and the process starts listening. For a typical containerised Go or Node.js
app this is 100–500ms; for JVM-based apps it can be several seconds.

Cold starts happen:
1. When the first request arrives after the service has been idle (scaled to zero)
2. When traffic spikes and new instances must be added

**Min instances** (`--min-instances`) keeps a configurable number of container instances
warm at all times — they are running and ready to accept requests even when there is no
traffic. This eliminates cold starts but costs money at idle because Cloud Run bills for
CPU and memory even when the instance is receiving no requests.

> **ACE exam tip:** Setting `--min-instances=1` is the standard way to eliminate cold
> starts for latency-sensitive services. The trade-off is that you pay for one idle
> instance continuously. For batch or low-traffic services, accepting cold starts and
> setting min-instances to 0 (the default) is more cost-efficient.

### Cloud Run Concurrency

By default, a single Cloud Run instance handles up to **80 concurrent requests**. This is
a fundamental difference from Cloud Functions Gen 1, where each function instance handles
exactly one request at a time.

Concurrency means fewer instances are needed to absorb traffic spikes, which reduces
cold starts and costs. You should set concurrency based on how much memory and CPU your
application uses per request:

```
Traffic: 400 requests/second

Default concurrency (80):  400 / 80 =  5 instances needed
Concurrency set to 1:      400 /  1 = 400 instances needed (Lambda-style)
Concurrency set to 200:    400 / 200 =  2 instances needed
```

Languages with a global interpreter lock (Python's CPython, Ruby's MRI) may not benefit
from high concurrency for CPU-bound work. I/O-bound workloads (database calls, API
calls) benefit greatly because threads spend most of their time waiting rather than
computing.

### Cloud Functions Gen 2 vs Gen 1

| Feature | Gen 1 | Gen 2 |
|---|---|---|
| Max timeout | 9 minutes | 60 minutes |
| Max memory | 8 GB | 32 GB |
| Max vCPUs | 1 | 4 |
| Concurrency | 1 | Configurable (up to 1000) |
| Trigger source | HTTP / Pub/Sub / Storage / etc. | HTTP / Eventarc (all events) |
| Runtime | Cloud Functions runtime | Cloud Run (identical environment) |
| Recommended for new deployments | No — use Gen 2 | Yes |

Gen 2 functions use **Eventarc** for event triggers. Eventarc is GCP's unified eventing
bus — it routes events from over 90 GCP services to Cloud Run and Cloud Functions using
CloudEvents format. This replaces the older per-product trigger system in Gen 1.

### App Engine: Standard vs Flexible

App Engine is GCP's original PaaS offering, predating Cloud Run by several years. While
Cloud Run is preferred for new workloads, App Engine remains the right choice when:
- Your team is already running an App Engine application
- You need App Engine-specific features: native task queues, scheduled tasks (cron), or
  the memcache service
- You want per-request billing with zero infrastructure management and do not need custom runtimes

**App Engine Standard** runs your code in a sandboxed runtime managed by GCP. You pick
a runtime (Python 3.11, Java 21, Go 1.22, Node.js 20, PHP 8.2, Ruby 3.2) and upload
your source code. GCP handles everything. Standard scales to zero and bills per
instance-hour.

**App Engine Flexible** runs your code in a Docker container on a Compute Engine VM that
GCP manages. It gives you full control over the runtime environment (you can install
system packages, use custom runtimes) but always keeps at least one instance running,
making it more expensive than Standard for low-traffic services.

```
App Engine Flexible ≈ Cloud Run without the "scales to zero" capability
```

For the ACE exam, know the key differences:

| | Standard | Flexible |
|---|---|---|
| Scales to zero | Yes | No (min 1 VM) |
| Request timeout | 10 minutes | 60 minutes |
| Runtime | Fixed GCP-maintained runtimes | Any (custom Dockerfile) |
| Background threads | Limited | Yes |
| Pricing | Per instance-hour (very cheap F1/B1 classes) | Per vCPU/memory-hour (Compute Engine rates) |
| SSH into instance | No | Yes |

### When to Choose What

This decision framework covers the most common ACE exam scenarios:

| Scenario | Best choice | Why |
|---|---|---|
| Deploy a stateless HTTP API in a container | **Cloud Run** | Container portability, scales to zero, no cluster management |
| Run a Python function triggered by a Pub/Sub message | **Cloud Functions Gen 2** | Event-driven, single purpose, managed runtime |
| Small function, <9min timeout, simple event triggers | **Cloud Functions Gen 2** | Less operational overhead than Cloud Run for simple functions |
| App needs built-in task queues and scheduled jobs | **App Engine Standard** | Native queue and cron support |
| App requires a custom OS-level package | **App Engine Flex or Cloud Run** | Both support custom containers |
| Stateful workload, need persistent disk or GPU | **Compute Engine** | Full VM control |
| Multiple microservices, service mesh, non-HTTP protocols | **GKE** | Kubernetes features needed |
| Long-running background job (>60 minutes) | **Compute Engine** or **Cloud Batch** | Serverless options have 60-minute max |

> **ACE exam tip:** If the question mentions "no server management" and a **container**,
> the answer is Cloud Run. If it mentions "no server management" and a **function** or
> **event trigger**, the answer is Cloud Functions. If it mentions App Engine-specific
> features like task queues or memcache, the answer is App Engine.

---

## Setup

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
echo "Project: ${PROJECT_ID}, Number: ${PROJECT_NUMBER}, Region: ${REGION}"
```

### App Engine Initialisation

App Engine requires a one-time initialisation that sets the region for your app. This
cannot be changed later — choose your region carefully. `us-central` (without the `1`)
is the App Engine region identifier for `us-central1`:

```bash
# This only needs to be done once per project
# Skip if your project already has an App Engine app
gcloud app create --region=us-central --project="${PROJECT_ID}"
```

Expected output:
```
Creating App Engine application in project [YOUR_PROJECT] and region [us-central]....done.
```

If App Engine is already initialised you will see:
```
ERROR: (gcloud.app.create) The project [YOUR_PROJECT] already contains an App Engine application.
```

That error is fine — proceed.

---

## Exercises

### Exercise 1 — Deploy a Container to Cloud Run

Cloud Run deploys any container that listens on HTTP. For this exercise you will deploy
a small Python Flask application included in this repository (`cold-start-demo/`). It
has a deliberate 5-second startup delay to simulate real-world initialisation work
(database connection pools, model loading, etc.), which makes cold starts clearly
observable.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

# Create an Artifact Registry repository to store the built container image
gcloud artifacts repositories create lab08 \
  --repository-format=docker \
  --location="${REGION}" \
  --description="Lab 08 container images" \
  --project="${PROJECT_ID}"

gcloud run deploy lab08-hello \
  --source=cold-start-demo \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/lab08/lab08-hello" \
  --platform=managed \
  --region="${REGION}" \
  --allow-unauthenticated \
  --project="${PROJECT_ID}"
```

The `--allow-unauthenticated` flag makes this service publicly accessible without a
bearer token. Without it, all requests return HTTP 403 unless the caller has the
`roles/run.invoker` IAM role. For internal services you would omit this flag and use
service-to-service authentication.

Expected output:
```
Deploying container to Cloud Run service [lab08-hello] in project [YOUR_PROJECT] region [us-central1]
✓ Deploying new service... Done.
  ✓ Creating Revision...
  ✓ Routing traffic...
  ✓ Setting IAM Policy...
Done.
Service [lab08-hello] revision [lab08-hello-00001-xyz] has been deployed and is serving 100 percent of traffic.
Service URL: https://lab08-hello-xxxxxxxxxx-uc.a.run.app
```

> If the output shows `serving 0 percent of traffic` (which can happen if you have
> redeployed over a service with a custom traffic split), route traffic to the latest
> revision:
> ```bash
> gcloud run services update-traffic lab08-hello \
>   --to-latest \
>   --region="${REGION}" \
>   --project="${PROJECT_ID}"
> ```

Capture the service URL and make a test request:

```bash
SERVICE_URL=$(gcloud run services describe lab08-hello \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

echo "Service URL: ${SERVICE_URL}"
curl -s "${SERVICE_URL}" | head -5
```

Expected output:
```
Service URL: https://lab08-hello-xxxxxxxxxx-uc.a.run.app
<h1>Hello from Cloud Run!</h1>
```

Inspect the revision that was created:

```bash
gcloud run revisions list \
  --service=lab08-hello \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="table(name,status.conditions[0].type,spec.containerConcurrency,spec.containers[0].image)"
```

Expected output:
```
NAME                   CONDITION  CONTAINER_CONCURRENCY  IMAGE
lab08-hello-00001-xyz  Ready      80                     us-central1-docker.pkg.dev/YOUR_PROJECT/lab08/lab08-hello
```

Notice the `CONTAINER_CONCURRENCY` of 80 — each instance will handle up to 80 concurrent
requests before Cloud Run spins up an additional instance.

> **ACE exam tip:** Cloud Run services have a URL in the format
> `https://SERVICE_NAME-HASH-REGION_CODE.a.run.app`. This URL is stable across revisions.
> Traffic splitting routes between revisions behind this single URL — callers never need
> to change their endpoint.

---

### Exercise 2 — Observe Cold Start Behaviour

Cloud Run scales to zero when there is no traffic. After a period of inactivity (typically
a few minutes), all instances are shut down. The next request must wait for a new instance
to start — this is the cold start penalty.

This exercise measures that penalty. First, force the service to scale down by waiting
for it to go idle, or by deploying with `--min-instances=0` (the default):

```bash
# Ensure the service can scale to zero (required to observe cold starts)
gcloud run services update lab08-hello \
  --region="${REGION}" \
  --min-instances=0 \
  --project="${PROJECT_ID}"
```

Rather than blindly sleeping, use the helper script which polls until the service has actually scaled to zero and then fires the timed request automatically:

```bash
./observe-cold-start.sh
```

Expected output (cold start — first request after idle):
```
HTTP 200 — Total time: 1.243s
real    0m1.247s
```

Now immediately send a second request (the instance is now warm):

```bash
echo "Sending warm request..."
time curl -s -o /dev/null -w "HTTP %{http_code} — Total time: %{time_total}s\n" "${SERVICE_URL}"
```

Expected output (warm — instance already running):
```
HTTP 200 — Total time: 0.089s
real    0m0.091s
```

The difference between cold and warm response times is entirely determined by what your
application does at startup — loading configuration, opening database connection pools,
warming caches, importing large libraries, etc. The demo app uses an artificial
`time.sleep(5)` to make this visible, but in production the same pattern applies: a Java
service initialising Spring context, a Python service loading an ML model, or a Node
service connecting to Redis will all show a measurable cold start penalty. For
latency-sensitive workloads (payment processing, interactive APIs) this is unacceptable.
The solution is minimum instances, which you will configure in exercise 4.

You can also observe cold starts in Cloud Logging. Cloud Run gen2 logs a
`"Starting new instance"` message in its system log each time it spins up a
new container instance:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="lab08-hello" AND textPayload:"Starting new instance"' \
  --project="${PROJECT_ID}" \
  --limit=5 \
  --format="table(timestamp,resource.labels.revision_name,textPayload)"
```

Expected output:
```
TIMESTAMP                      REVISION_NAME           TEXT_PAYLOAD
2024-01-15T10:23:41.123456789Z lab08-hello-00001-xyz   Starting new instance. Reason: SCALE_UP - Instance started due to increased traffic.
```

---

### Exercise 3 — Traffic Splitting: Canary Deployment

Deploy a second revision with a different image (simulating a v2 deployment), then split
traffic between the two revisions. You will send 80% of traffic to the stable revision
and 20% to the canary.

Deploy a new revision by updating the service with a new environment variable. Any
configuration change creates a new revision:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

# Get the name of the current (stable) revision before deploying the new one
STABLE_REVISION=$(gcloud run revisions list \
  --service=lab08-hello \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(name)" \
  --limit=1)

echo "Stable revision: ${STABLE_REVISION}"

# Deploy a new revision by setting an environment variable
# (In a real deployment you would change the --source or --image to a new version)
gcloud run deploy lab08-hello \
  --source=cold-start-demo \
  --image="${REGION}-docker.pkg.dev/${PROJECT_ID}/lab08/lab08-hello" \
  --platform=managed \
  --region="${REGION}" \
  --allow-unauthenticated \
  --set-env-vars="VERSION=v2" \
  --no-traffic \
  --project="${PROJECT_ID}"
```

The `--no-traffic` flag deploys the revision but does not send any traffic to it yet.
This is the safe way to deploy a canary — get the revision ready before exposing it to users.

Expected output:
```
Building using Buildpacks and deploying container to Cloud Run service [lab08-hello] in project [YOUR_PROJECT] region [us-central1]
✓ Building and deploying... Done.
  ✓ Validating configuration...
  ✓ Uploading sources...
  ✓ Building Container...
  ✓ Creating Revision...
  ✓ Routing traffic...
  ✓ Setting IAM Policy...
Done.
Service [lab08-hello] revision [lab08-hello-00002-abc] has been deployed and is serving 0 percent of traffic.
```

Get the names of both revisions:

```bash
CANARY_REVISION=$(gcloud run revisions list \
  --service=lab08-hello \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(name)" \
  --sort-by="~creationTimestamp" \
  --limit=1)

STABLE_REVISION=$(gcloud run revisions list \
  --service=lab08-hello \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(name)" \
  --sort-by="~creationTimestamp" \
  --limit=2 | tail -1)

echo "Canary revision: ${CANARY_REVISION}"
echo "Stable revision: ${STABLE_REVISION}"
```

Now split traffic 80/20 between the stable and canary revisions:

```bash
gcloud run services update-traffic lab08-hello \
  --region="${REGION}" \
  --to-revisions="${STABLE_REVISION}=80,${CANARY_REVISION}=20" \
  --project="${PROJECT_ID}"
```

Expected output:
```
✓ Updating traffic... Done.
Traffic:
  80% lab08-hello-00001-xyz
  20% lab08-hello-00002-abc
```

Verify the split by checking the service description:

```bash
gcloud run services describe lab08-hello \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(status.traffic)"
```

Expected output:
```yaml
status:
  traffic:
  - percent: 80
    revisionName: lab08-hello-00001-xyz
  - percent: 20
    revisionName: lab08-hello-00002-abc
```

Send several requests to observe both revisions serving traffic:

```bash
SERVICE_URL=$(gcloud run services describe lab08-hello \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

for i in $(seq 1 10); do
  curl -s "${SERVICE_URL}"
done
```

Expected output (mix of both revisions — exact distribution varies):
```
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00002-abc)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00002-abc)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
<h1>Hello from Cloud Run! (revision: lab08-hello-00001-xyz)</h1>
```

> **Note on traffic splitting:** The 80/20 split is approximate over many requests — each
> individual request is routed based on a random draw weighted by the percentages. You
> will not see exactly 8 requests to v1 and 2 to v2 in every batch of 10, but over
> hundreds of requests the ratio will converge on 80/20.

To complete the rollout and send all traffic to the canary (now promoted to stable):

```bash
gcloud run services update-traffic lab08-hello \
  --region="${REGION}" \
  --to-latest \
  --project="${PROJECT_ID}"
```

Expected output:
```
✓ Updating traffic... Done.
Traffic:
  100% lab08-hello-00002-abc (currently LATEST)
```

---

### Exercise 4 — Minimum Instances: Eliminating Cold Starts

Set `--min-instances=1` on the service. Cloud Run will now keep at least one instance warm
at all times, eliminating cold starts. This creates a new revision with the new configuration.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud run services update lab08-hello \
  --region="${REGION}" \
  --min-instances=1 \
  --max-instances=10 \
  --concurrency=80 \
  --project="${PROJECT_ID}"
```

Expected output:
```
✓ Updating...
  ✓ Creating Revision...
  ✓ Routing traffic...
Done.
Service [lab08-hello] revision [lab08-hello-00003-def] has been deployed and is serving 100 percent of traffic.
```

Wait several minutes (enough time for the service to have scaled to zero previously), then
measure the response time for a cold-start scenario. With min-instances=1, there should be
no cold start penalty:

```bash
SERVICE_URL=$(gcloud run services describe lab08-hello \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

echo "Request with min-instances=1 (should be consistently fast):"
for i in $(seq 1 3); do
  time curl -s -o /dev/null -w "HTTP %{http_code} — Time: %{time_total}s\n" "${SERVICE_URL}"
  sleep 2
done
```

Expected output (all requests are consistently fast — no cold start spikes):
```
HTTP 200 — Time: 0.092s
HTTP 200 — Time: 0.087s
HTTP 200 — Time: 0.094s
```

Verify the current configuration of the service:

```bash
gcloud run services describe lab08-hello \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(spec.template.metadata.annotations)"
```

Expected output (additional gcloud annotations may also appear):
```yaml
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/maxScale: '10'
        autoscaling.knative.dev/minScale: '1'
        run.googleapis.com/startup-cpu-boost: 'true'
```

> **ACE exam tip:** `--min-instances=1` costs money even at zero traffic because the
> instance is running and Cloud Run bills for CPU and memory during idle time. For a
> small `lab08-hello` revision this is negligible (the F1-micro equivalent of Cloud Run
> costs fractions of a cent per hour), but for a memory-heavy service with multiple
> revisions this adds up. Always set `--min-instances=0` for dev/staging services and
> reserve `--min-instances=1` (or higher) for production services with latency SLOs.

---

### Exercise 5 — Cloud Function with HTTP Trigger

Cloud Functions (Gen 2) is ideal for single-purpose event handlers. You write a function,
GCP wraps it in an HTTP endpoint, and charges per invocation.

This exercise deploys a Python function that converts a temperature from Celsius to
Fahrenheit. It is a deliberately simple example to keep the focus on the deployment
mechanics rather than the application logic.

First create a working directory and write the function source:

```bash
mkdir -p /tmp/lab08-function-http
cat > /tmp/lab08-function-http/main.py << 'PYEOF'
import functions_framework
import json

@functions_framework.http
def convert_temperature(request):
    """HTTP Cloud Function: converts Celsius to Fahrenheit."""
    request_json = request.get_json(silent=True)
    request_args = request.args

    if request_json and "celsius" in request_json:
        celsius = float(request_json["celsius"])
    elif request_args and "celsius" in request_args:
        celsius = float(request_args["celsius"])
    else:
        return json.dumps({"error": "Missing 'celsius' parameter"}), 400

    fahrenheit = (celsius * 9 / 5) + 32
    return json.dumps({
        "celsius": celsius,
        "fahrenheit": fahrenheit,
        "message": f"{celsius}°C is {fahrenheit}°F"
    })
PYEOF

cat > /tmp/lab08-function-http/requirements.txt << 'EOF'
functions-framework==3.*
EOF
```

Deploy the function:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud functions deploy lab08-temp-convert \
  --gen2 \
  --runtime=python311 \
  --region="${REGION}" \
  --source=/tmp/lab08-function-http \
  --entry-point=convert_temperature \
  --trigger-http \
  --allow-unauthenticated \
  --memory=128Mi \
  --timeout=30s \
  --project="${PROJECT_ID}"
```

This takes 60–120 seconds — Cloud Build compiles the function and creates a container image
behind the scenes:

Expected output:
```
Preparing function...done.
✓ Deploying function...
  ✓ [Build] Logs are available at [...]
  ✓ [Service] Updated service [lab08-temp-convert]
Done.
state: ACTIVE
url: https://us-central1-YOUR_PROJECT.cloudfunctions.net/lab08-temp-convert
```

Get the function URL and test it:

```bash
FUNCTION_URL=$(gcloud functions describe lab08-temp-convert \
  --gen2 \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(serviceConfig.uri)")

echo "Function URL: ${FUNCTION_URL}"

# Test with a query parameter
curl -s "${FUNCTION_URL}?celsius=100"

# Test with a JSON body
curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"celsius": 37}' \
  "${FUNCTION_URL}"
```

Expected output:
```json
{"celsius": 100.0, "fahrenheit": 212.0, "message": "100.0°C is 212.0°F"}
{"celsius": 37.0, "fahrenheit": 98.6, "message": "37.0°C is 98.6°F"}
```

Test the error case by omitting the required parameter:

```bash
curl -s "${FUNCTION_URL}"
```

Expected output:
```json
{"error": "Missing 'celsius' parameter"}
```

Notice that even though this is a Cloud Function, it has a Cloud Run URL
(`*.run.app` or similar). Gen 2 functions are Cloud Run services — you can see the
underlying service:

```bash
gcloud run services list \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --filter="name:lab08-temp-convert"
```

Expected output:
```
SERVICE               REGION       URL                                          LAST DEPLOYED BY  LAST DEPLOYED AT
lab08-temp-convert    us-central1  https://lab08-temp-convert-xxxx-uc.a.run.app  you@example.com   2024-01-15T10:30:00Z
```

---

### Exercise 6 — Cloud Function with Pub/Sub Trigger

Event-driven functions respond to messages on a Pub/Sub topic rather than direct HTTP
calls. This pattern is common for asynchronous processing: an upstream service publishes
a message, and the function processes it without the publisher needing to know anything
about the processing logic.

Create a Pub/Sub topic that will trigger the function:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud pubsub topics create lab08-events \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created topic [projects/YOUR_PROJECT/topics/lab08-events].
```

Write the Pub/Sub function. It receives a base64-encoded message body and logs the decoded
content:

```bash
mkdir -p /tmp/lab08-function-pubsub
cat > /tmp/lab08-function-pubsub/main.py << 'PYEOF'
import functions_framework
import base64
import json
import logging

@functions_framework.cloud_event
def handle_event(cloud_event):
    """Pub/Sub Cloud Function: logs incoming event data."""
    # The Pub/Sub message data is base64-encoded in the CloudEvent
    message_data = base64.b64decode(
        cloud_event.data["message"]["data"]
    ).decode("utf-8")

    try:
        payload = json.loads(message_data)
        logging.info(f"Received structured event: {json.dumps(payload, indent=2)}")
        print(f"Processed event: type={payload.get('type', 'unknown')}, "
              f"value={payload.get('value', 'N/A')}")
    except json.JSONDecodeError:
        logging.info(f"Received plain text event: {message_data}")
        print(f"Processed plain message: {message_data}")
PYEOF

cat > /tmp/lab08-function-pubsub/requirements.txt << 'EOF'
functions-framework==3.*
EOF
```

Deploy the function with a Pub/Sub trigger via Eventarc:

```bash
REGION="us-central1"

gcloud functions deploy lab08-event-handler \
  --gen2 \
  --runtime=python311 \
  --region="${REGION}" \
  --source=/tmp/lab08-function-pubsub \
  --entry-point=handle_event \
  --trigger-topic=lab08-events \
  --memory=128Mi \
  --timeout=60s \
  --project="${PROJECT_ID}"
```

Expected output:
```
Preparing function...done.
✓ Deploying function...
  ✓ [Build] Logs are available at [...]
  ✓ [Service] Updated service [lab08-event-handler]
  ✓ [Trigger] Updated trigger [projects/YOUR_PROJECT/locations/us-central1/triggers/...]
Done.
state: ACTIVE
```

Test the function by publishing a message to the topic:

```bash
gcloud pubsub topics publish lab08-events \
  --message='{"type": "temperature_reading", "value": 23.5, "sensor": "lab08-sensor-01"}' \
  --project="${PROJECT_ID}"
```

Expected output:
```
messageIds:
- '1234567890123456'
```

Wait about 10 seconds for the function to process the message, then check the logs:

```bash
gcloud functions logs read lab08-event-handler \
  --gen2 \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --limit=10
```

Expected output:
```
LEVEL  NAME                  EXECUTION_ID  TIME_UTC                 LOG
       lab08-event-handler   abc123        2024-01-15 10:35:12 UTC  Processed event: type=temperature_reading, value=23.5
```

Publish several more messages to confirm the function processes each one:

```bash
for sensor in 01 02 03; do
  gcloud pubsub topics publish lab08-events \
    --message="{\"type\": \"alert\", \"sensor\": \"lab08-sensor-${sensor}\", \"value\": $((RANDOM % 100))}" \
    --project="${PROJECT_ID}"
  echo "Published message for sensor-${sensor}"
done
```

Wait 15 seconds then check the logs again — you should see three new log lines, one per
message.

> **Why Pub/Sub over HTTP triggers for async work?** Pub/Sub provides at-least-once
> delivery with automatic retries. If your function fails (crashes, times out, returns a
> non-2xx status), Pub/Sub will redeliver the message. An HTTP trigger returns an error
> directly to the caller with no automatic retry. For processing that must complete
> reliably, Pub/Sub triggers are the better choice.

---

### Exercise 7 — Deploy an App Engine Standard Application

App Engine Standard requires a configuration file (`app.yaml`) alongside your application
code. The `app.yaml` defines the runtime, scaling behaviour, and environment variables.

Write a simple Python Flask application:

```bash
mkdir -p /tmp/lab08-appengine
cat > /tmp/lab08-appengine/main.py << 'PYEOF'
from flask import Flask, request
import os
import platform

app = Flask(__name__)

@app.route("/")
def index():
    return f"""
<!DOCTYPE html>
<html>
<head><title>Lab 08 - App Engine</title></head>
<body>
<h1>App Engine Standard — Lab 08</h1>
<p>Version: {os.environ.get('VERSION', '1.0')}</p>
<p>Python: {platform.python_version()}</p>
<p>Instance: {os.environ.get('GAE_INSTANCE', 'local')}</p>
<p>Service: {os.environ.get('GAE_SERVICE', 'default')}</p>
</body>
</html>
"""

@app.route("/health")
def health():
    return {"status": "ok", "version": os.environ.get("VERSION", "1.0")}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
PYEOF

cat > /tmp/lab08-appengine/requirements.txt << 'EOF'
Flask==3.0.0
EOF

cat > /tmp/lab08-appengine/app.yaml << 'EOF'
runtime: python311

env_variables:
  VERSION: "1.0"

automatic_scaling:
  min_instances: 0
  max_instances: 5
  target_cpu_utilization: 0.65

instance_class: F1
EOF
```

Deploy the application. The first deployment to a project creates the default App Engine
service. Subsequent deployments create new versions:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud app deploy /tmp/lab08-appengine/app.yaml \
  --project="${PROJECT_ID}" \
  --quiet
```

Expected output (takes 2–3 minutes for the first deploy):
```
Services to deploy:
  descriptor:      [/tmp/lab08-appengine/app.yaml]
  source:          [/tmp/lab08-appengine]
  target project:  [YOUR_PROJECT]
  target service:  [default]
  target version:  [20240115t103000]
  target url:      [https://YOUR_PROJECT.appspot.com]

Beginning deployment of service [default]...
Created .gcloudignore file. See `gcloud topic gcloudignore` for details.
╔════════════════════════════════════════════════════════════╗
╠═ Uploading 3 files to Google Cloud Storage                ═╣
╚════════════════════════════════════════════════════════════╝
File upload done.
Updating service [default]...done.
Deployed service [default] to [https://YOUR_PROJECT.appspot.com]
```

Test the application:

```bash
APP_URL="https://${PROJECT_ID}.appspot.com"
echo "App Engine URL: ${APP_URL}"
curl -s "${APP_URL}"
```

Expected output:
```html
<!DOCTYPE html>
<html>
<head><title>Lab 08 - App Engine</title></head>
<body>
<h1>App Engine Standard — Lab 08</h1>
<p>Version: 1.0</p>
<p>Python: 3.11.x</p>
...
</body>
</html>
```

List the deployed versions:

```bash
gcloud app versions list \
  --service=default \
  --project="${PROJECT_ID}" \
  --format="table(id,service,traffic_split,last_deployed_time,serving_status)"
```

Expected output:
```
VERSION            SERVICE  TRAFFIC_SPLIT  LAST_DEPLOYED                   SERVING_STATUS
20240115t103000    default  1.00           2024-01-15T10:30:00+00:00       SERVING
```

> **App Engine URLs:** Your application is automatically served at
> `https://PROJECT_ID.appspot.com`. Each version also gets its own URL:
> `https://VERSION-dot-SERVICE-dot-PROJECT_ID.appspot.com`. This lets you test a new
> version at its direct URL before shifting traffic to it.

---

### Exercise 8 — App Engine Traffic Splitting Between Versions

Deploy a v2 of the App Engine application and split traffic between the two versions.
App Engine traffic splitting works the same conceptual way as Cloud Run revision splitting —
but the mechanics are slightly different.

Update the `app.yaml` to mark this as version 2 and redeploy:

```bash
PROJECT_ID=$(gcloud config get-value project)

# Record the current (v1) version ID
V1_VERSION=$(gcloud app versions list \
  --service=default \
  --project="${PROJECT_ID}" \
  --format="value(id)" \
  --sort-by="~last_deployed_time" \
  --limit=1)

echo "V1 version: ${V1_VERSION}"

# Update the app to version 2
sed -i 's/VERSION: "1.0"/VERSION: "2.0"/' /tmp/lab08-appengine/app.yaml

# Deploy but do not promote to receive traffic yet
gcloud app deploy /tmp/lab08-appengine/app.yaml \
  --project="${PROJECT_ID}" \
  --no-promote \
  --quiet
```

`--no-promote` deploys the new version but keeps all traffic on the existing version.
This is the App Engine equivalent of Cloud Run's `--no-traffic` flag.

Expected output:
```
Deployed service [default] to [https://20240115t110000-dot-default-dot-YOUR_PROJECT.appspot.com]
(not promoted)
```

Get the new version ID:

```bash
V2_VERSION=$(gcloud app versions list \
  --service=default \
  --project="${PROJECT_ID}" \
  --format="value(id)" \
  --sort-by="~last_deployed_time" \
  --limit=1)

echo "V1 version: ${V1_VERSION}"
echo "V2 version: ${V2_VERSION}"
```

Test the v2 version directly at its version-specific URL before exposing it to general
traffic:

```bash
V2_URL="https://${V2_VERSION}-dot-default-dot-${PROJECT_ID}.appspot.com"
echo "V2 direct URL: ${V2_URL}"
curl -s "${V2_URL}" | grep "Version:"
```

Expected output:
```
<p>Version: 2.0</p>
```

Now split traffic 75/25 between v1 and v2:

```bash
gcloud app services set-traffic default \
  --splits="${V1_VERSION}=75,${V2_VERSION}=25" \
  --split-by=random \
  --project="${PROJECT_ID}"
```

`--split-by=random` sends each request randomly weighted by the splits. The alternatives
are `cookie` (sticky sessions using a cookie) and `ip` (sticky per client IP address).

Expected output:
```
Setting traffic split for service [default]...done.
```

Verify the traffic split:

```bash
gcloud app versions list \
  --service=default \
  --project="${PROJECT_ID}" \
  --format="table(id,traffic_split,serving_status)"
```

Expected output:
```
VERSION            TRAFFIC_SPLIT  SERVING_STATUS
20240115t103000    0.75           SERVING
20240115t110000    0.25           SERVING
```

Test the main URL multiple times to see both versions responding:

```bash
APP_URL="https://${PROJECT_ID}.appspot.com"

for i in $(seq 1 8); do
  curl -s "${APP_URL}" | grep "Version:"
done
```

Expected output (approximately 75/25 split):
```
<p>Version: 1.0</p>
<p>Version: 1.0</p>
<p>Version: 2.0</p>
<p>Version: 1.0</p>
<p>Version: 2.0</p>
<p>Version: 1.0</p>
<p>Version: 1.0</p>
<p>Version: 1.0</p>
```

Promote v2 to receive all traffic to complete the rollout:

```bash
gcloud app services set-traffic default \
  --splits="${V2_VERSION}=100" \
  --project="${PROJECT_ID}"
```

Stop the old v1 version to avoid incurring instance-hour charges (stopped versions do not
serve traffic or consume compute):

```bash
gcloud app versions stop "${V1_VERSION}" \
  --service=default \
  --project="${PROJECT_ID}" \
  --quiet
```

Expected output:
```
Stopping version [default/20240115t103000]....done.
```

> **ACE exam tip:** App Engine versions can be in one of three states: SERVING, STOPPED,
> or DISABLED. STOPPED versions exist and can be re-started instantly (useful for instant
> rollback), but consume no compute. DELETED versions are gone permanently. Always
> STOP rather than DELETE if you might need to roll back.

---

### Exercise 9 — Cloud Run with Cloud SQL Connection

Production Cloud Run services often need a relational database. Cloud Run connects to
Cloud SQL using a **Unix socket** via the Cloud SQL Auth Proxy — a sidecar that handles
IAM-based authentication and encrypts the connection. You do not need to manage connection
credentials; the proxy uses the service account identity.

This exercise creates a Cloud SQL PostgreSQL instance, connects to it from Cloud Run, and
verifies the connection.

> **Cost reminder:** Cloud SQL db-f1-micro costs ~$0.015/hr. Delete it promptly after
> this exercise.

#### Step 9a — Create a Cloud SQL PostgreSQL Instance

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud sql instances create lab08-pg \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region="${REGION}" \
  --no-backup \
  --project="${PROJECT_ID}"
```

This takes 3–5 minutes. Expected output:
```
Creating Cloud SQL instance for POSTGRES_15...done.
Created [https://sqladmin.googleapis.com/sql/v1beta4/projects/YOUR_PROJECT/instances/lab08-pg].
NAME      DATABASE_VERSION  LOCATION       TIER         PRIMARY_ADDRESS  PRIVATE_ADDRESS  STATUS
lab08-pg  POSTGRES_15       us-central1-b  db-f1-micro  34.xxx.xxx.xxx                    RUNNABLE
```

Create a database and a user:

```bash
gcloud sql databases create lab08db \
  --instance=lab08-pg \
  --project="${PROJECT_ID}"

gcloud sql users create lab08user \
  --instance=lab08-pg \
  --password=lab08password \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created database [lab08db].
Created user [lab08user].
```

Get the instance connection name — this is used by the Cloud SQL Auth Proxy to identify
the instance:

```bash
INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe lab08-pg \
  --project="${PROJECT_ID}" \
  --format="value(connectionName)")

echo "Instance connection name: ${INSTANCE_CONNECTION_NAME}"
# Format: PROJECT_ID:REGION:INSTANCE_NAME
```

#### Step 9b — Grant the Cloud Run Service Account Access to Cloud SQL

Cloud Run uses a service account to authenticate. The default service account is the
Compute Engine default service account. Grant it the `cloudsql.client` role:

```bash
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

echo "Cloud Run service account: ${SA_EMAIL}"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/cloudsql.client"
```

Expected output:
```
Updated IAM policy for project [YOUR_PROJECT].
```

#### Step 9c — Deploy a Cloud Run Service with Cloud SQL Connection

Write a simple Python application that connects to PostgreSQL and returns database
information:

```bash
mkdir -p /tmp/lab08-cloudsql
cat > /tmp/lab08-cloudsql/main.py << 'PYEOF'
import os
from flask import Flask
import pg8000.native

app = Flask(__name__)

def get_db_connection():
    """Connect to Cloud SQL via Unix socket (Cloud SQL Auth Proxy)."""
    db_user = os.environ.get("DB_USER", "lab08user")
    db_pass = os.environ.get("DB_PASS", "lab08password")
    db_name = os.environ.get("DB_NAME", "lab08db")
    # Cloud SQL Auth Proxy socket path
    db_socket = os.environ.get("DB_SOCKET", "/cloudsql")
    instance_connection = os.environ.get("INSTANCE_CONNECTION_NAME", "")

    unix_socket = f"{db_socket}/{instance_connection}"

    conn = pg8000.native.Connection(
        user=db_user,
        password=db_pass,
        database=db_name,
        unix_sock=unix_socket
    )
    return conn

@app.route("/")
def index():
    try:
        conn = get_db_connection()
        result = conn.run("SELECT version(), current_database(), current_user")
        conn.close()
        pg_version, db_name, db_user = result[0]
        return f"""
<html><body>
<h1>Cloud Run + Cloud SQL</h1>
<p><strong>Connected to:</strong> {db_name}</p>
<p><strong>User:</strong> {db_user}</p>
<p><strong>PostgreSQL:</strong> {pg_version[:50]}...</p>
<p><strong>Status:</strong> Connected successfully</p>
</body></html>
"""
    except Exception as e:
        return f"<html><body><h1>Connection failed</h1><p>{e}</p></body></html>", 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
PYEOF

cat > /tmp/lab08-cloudsql/requirements.txt << 'EOF'
Flask==3.0.0
pg8000==1.30.4
EOF
```

Deploy the Cloud Run service with the Cloud SQL connection configured. The
`--add-cloudsql-instances` flag tells Cloud Run to mount the Cloud SQL Auth Proxy socket:

```bash
INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe lab08-pg \
  --project="${PROJECT_ID}" \
  --format="value(connectionName)")

gcloud run deploy lab08-cloudsql \
  --source=/tmp/lab08-cloudsql \
  --platform=managed \
  --region="${REGION}" \
  --allow-unauthenticated \
  --add-cloudsql-instances="${INSTANCE_CONNECTION_NAME}" \
  --set-env-vars="INSTANCE_CONNECTION_NAME=${INSTANCE_CONNECTION_NAME},DB_USER=lab08user,DB_PASS=lab08password,DB_NAME=lab08db" \
  --project="${PROJECT_ID}"
```

This uses `--source` instead of `--image` — Cloud Build builds the container automatically
from the source directory. Expected output (after 2–3 minutes):

```
Building using Buildpacks and deploying container to Cloud Run service [lab08-cloudsql]...
✓ Building and deploying new service... Done.
  ✓ Creating Container Repository...
  ✓ Uploading sources...
  ✓ Building Container...
  ✓ Creating Revision...
  ✓ Routing traffic...
Done.
Service [lab08-cloudsql] revision [lab08-cloudsql-00001-abc] has been deployed and is serving 100 percent of traffic.
Service URL: https://lab08-cloudsql-xxxxxxxxxx-uc.a.run.app
```

Test the connection:

```bash
CLOUDSQL_URL=$(gcloud run services describe lab08-cloudsql \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

curl -s "${CLOUDSQL_URL}"
```

Expected output:
```html
<html><body>
<h1>Cloud Run + Cloud SQL</h1>
<p><strong>Connected to:</strong> lab08db</p>
<p><strong>User:</strong> lab08user</p>
<p><strong>PostgreSQL:</strong> PostgreSQL 15.x on x86_64-pc-linux-gnu...</p>
<p><strong>Status:</strong> Connected successfully</p>
</body></html>
```

#### How the Cloud SQL Auth Proxy Works

When you use `--add-cloudsql-instances`, Cloud Run automatically runs the Cloud SQL Auth
Proxy as a sidecar container alongside your application container. The proxy:

1. Authenticates to Cloud SQL using the service account (no passwords stored in the proxy)
2. Creates a Unix socket at `/cloudsql/PROJECT:REGION:INSTANCE`
3. Your application connects to that local socket using the database password
4. The proxy encrypts the connection over the internet to Cloud SQL

```
Your container
    │
    │ connects to Unix socket /cloudsql/PROJECT:REGION:INSTANCE
    ▼
Cloud SQL Auth Proxy (sidecar)
    │
    │ encrypted TCP (TLS) using IAM service account credentials
    ▼
Cloud SQL instance (in Google's managed network)
```

This is significantly more secure than embedding a public IP and password in your
application. The IAM role (`roles/cloudsql.client`) controls which service accounts can
connect at all — the database password is a second factor, not the primary authentication
mechanism.

> **ACE exam tip:** Never expose a Cloud SQL instance's public IP directly to the internet
> if you can avoid it. Use the Cloud SQL Auth Proxy for Cloud Run, Cloud Functions, and
> App Engine Standard. For Compute Engine VMs with private IPs, use the private IP
> directly via VPC peering.

---

## Key Takeaways

- **Cloud Run** is the preferred default for new serverless workloads on GCP. It runs any
  container, scales from zero, and supports HTTP, gRPC, and event-driven workloads via
  Eventarc.

- **Cloud Functions Gen 2** is built on Cloud Run. It is the right choice for simple
  event-driven functions where you want the deployment complexity of writing a single
  function rather than a full container. Gen 1 functions are legacy — always use Gen 2
  for new deployments.

- **Cloud Run revisions** are immutable — any configuration or container change creates a
  new revision. Traffic splitting lets you send a percentage to each revision, enabling
  canary and blue/green deployments.

- **Cold starts** occur when Cloud Run scales from zero to handle a new request. Set
  `--min-instances=1` for latency-sensitive services to eliminate cold starts. This costs
  money at idle.

- **Concurrency** is a key Cloud Run differentiator: each instance handles up to 80
  concurrent requests by default (configurable up to 1000). This reduces instance count
  and cold starts compared to the Lambda/Gen 1 model of one request per instance.

- **App Engine Standard** is the right choice when you need App Engine-specific features:
  task queues, cron jobs, and memcache. For new workloads without those requirements,
  Cloud Run is preferred.

- **App Engine versions** can be STOPPED (no compute, instant restart) or DELETED
  (permanent). Always STOP rather than DELETE if you might roll back.

- **App Engine traffic splitting** supports three modes: `random` (default, no affinity),
  `cookie` (sticky session via cookie), and `ip` (sticky per client IP).

- **Cloud SQL Auth Proxy** is the correct way to connect Cloud Run and Cloud Functions to
  Cloud SQL. It uses IAM authentication (no credentials in the proxy) and encrypts the
  connection. Your app connects to a local Unix socket — no public IP needed.

- For the exam, know the **max timeout** differences: Cloud Run = 60 minutes, Cloud
  Functions Gen 2 = 60 minutes, App Engine Standard = 10 minutes. Anything needing
  more than 60 minutes requires Compute Engine or Cloud Batch.

- **Pub/Sub triggers** for Cloud Functions provide at-least-once delivery with automatic
  retry. HTTP triggers return errors directly to the caller with no retry. Use Pub/Sub
  for reliable asynchronous processing.

---

## Cleanup

Run all of these commands to destroy every resource created in this lab. Cloud SQL is
the most expensive resource — delete it first.

```bash
# Check what exists before cleanup
../status.sh 8
```

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

echo "=== Deleting Cloud SQL instance (most expensive) ==="
gcloud sql instances delete lab08-pg \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud Run services ==="
gcloud run services delete lab08-hello \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

gcloud run services delete lab08-cloudsql \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud Functions ==="
gcloud functions delete lab08-temp-convert \
  --gen2 \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

gcloud functions delete lab08-event-handler \
  --gen2 \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Pub/Sub topic ==="
gcloud pubsub topics delete lab08-events \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Stopping App Engine versions ==="
# List all versions and stop them
ALL_VERSIONS=$(gcloud app versions list \
  --service=default \
  --project="${PROJECT_ID}" \
  --format="value(id)")

for VERSION in ${ALL_VERSIONS}; do
  echo "Stopping App Engine version: ${VERSION}"
  gcloud app versions stop "${VERSION}" \
    --service=default \
    --project="${PROJECT_ID}" \
    --quiet
done

echo "=== Removing IAM binding for Cloud SQL ==="
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)")
SA_EMAIL="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/cloudsql.client"

echo "=== Cleaning up local temp files ==="
rm -rf /tmp/lab08-function-http /tmp/lab08-function-pubsub /tmp/lab08-appengine /tmp/lab08-cloudsql

echo "=== Cleanup complete ==="
```

Verify Cloud Run services are deleted:

```bash
echo "--- Cloud Run services ---"
gcloud run services list \
  --region="${REGION}" \
  --filter="name:lab08" \
  --project="${PROJECT_ID}"

echo "--- Cloud Functions ---"
gcloud functions list \
  --gen2 \
  --region="${REGION}" \
  --filter="name:lab08" \
  --project="${PROJECT_ID}"

echo "--- Cloud SQL instances ---"
gcloud sql instances list \
  --filter="name:lab08" \
  --project="${PROJECT_ID}"

echo "--- Pub/Sub topics ---"
gcloud pubsub topics list \
  --filter="name:lab08" \
  --project="${PROJECT_ID}"

../status.sh 8
```

All sections should be empty (App Engine stopped versions remain visible but are not billable).

> **Note on App Engine:** You cannot delete an App Engine application once created. You can
> only stop or disable versions. The application itself persists in your project. If you
> want to stop all App Engine billing, stop all versions as shown above — stopped App Engine
> versions have no compute cost.
>
> **Note on Artifact Registry:** Cloud Build creates container images in Artifact Registry
> when you use `--source` with Cloud Run or deploy Cloud Functions. These images are very
> small and incur negligible storage costs (fractions of a cent per month), but if you want
> to clean them up completely:
> ```bash
> gcloud artifacts repositories delete cloud-run-source-deploy \
>   --location="${REGION}" \
>   --quiet \
>   --project="${PROJECT_ID}" 2>/dev/null || echo "Repository not found or already deleted."
> ```
