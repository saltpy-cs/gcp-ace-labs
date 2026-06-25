# Lab 12 — Automation & CI/CD

> **Cost warning:** Cloud Build first 120 build-minutes/day are free on the default worker
> pool, then **$0.003/build-minute**. Artifact Registry is **$0.10/GB/month** after the
> first 0.5 GB free. Cloud Deploy costs **$0.03 per deployment**. Cloud Scheduler is free
> for the first three jobs, then **$0.10/job/month**. Cloud Deployment Manager is free
> (you pay only for the resources it creates). Estimated total for this lab if cleaned up
> promptly: **< $0.05**.

---

## Objectives

After completing this lab you will be able to:

- Create an Artifact Registry Docker repository and configure Docker authentication
- Build a container image locally and push it to Artifact Registry using `gcloud`
- Write a `cloudbuild.yaml` that builds, tests, and pushes a container image
- Run Cloud Build manually with `gcloud builds submit`
- Use Cloud Build substitutions and understand built-in substitution variables
- Create a Cloud Build trigger connected to a Cloud Source Repository
- Create a Cloud Scheduler job that invokes an HTTP endpoint on a schedule
- Write idiomatic gcloud scripts using `--format=value()`, `--filter`, and proper error handling
- Write a Cloud Deployment Manager configuration and deploy it declaratively
- Understand Cloud Deploy delivery pipelines and promotion (conceptually)
- Understand Pub/Sub topics and subscriptions, and explain push vs pull delivery
- Understand Eventarc and how it routes GCP events to Cloud Run or Cloud Functions

---

## Concepts

### CI/CD on GCP: The Full Picture

Continuous Integration and Continuous Delivery (CI/CD) automates the path from source code
commit to running infrastructure. On GCP the toolchain maps to four products:

```
Source code (Cloud Source Repositories / GitHub / GitLab)
    │
    │ push event triggers build
    ▼
Cloud Build  (CI — build, test, package)
    │
    │ produces container image → pushes to
    ▼
Artifact Registry  (artefact storage — Docker, Maven, npm, Python…)
    │
    │ Cloud Deploy picks up the image and manages promotion
    ▼
Cloud Deploy  (CD — delivery pipeline: dev → staging → prod)
    │
    │ deploys to
    ▼
Cloud Run / GKE / Compute Engine
```

On AWS, the rough equivalents are:
- Cloud Source Repositories → **AWS CodeCommit**
- Cloud Build → **AWS CodeBuild**
- Artifact Registry → **Amazon ECR** (for containers) / **AWS CodeArtifact** (for packages)
- Cloud Deploy → **AWS CodeDeploy** / **AWS CodePipeline**

The GCP tools are more loosely coupled than AWS CodePipeline. You do not need all four —
many teams use Cloud Build to push images directly to a Cloud Run service, skipping Cloud
Deploy entirely. Cloud Deploy adds value when you need explicit promotion gates between
environments (dev → staging → prod with manual approval).

### Cloud Build

Cloud Build is GCP's fully managed CI service. You describe a build as a sequence of
**steps** in a `cloudbuild.yaml` file. Each step runs in a Docker container. Cloud Build
pulls that container, runs the specified command, then moves on to the next step.

**Why Cloud Build instead of running CI on a VM?**

- No infrastructure to manage — GCP provisions ephemeral workers per build
- Tight IAM integration — builds run as the Cloud Build service account, not as a
  human user; you control exactly what the build can do
- Built-in integration with GCP APIs — the worker already has `gcloud` and
  application default credentials; no credential files to manage
- Parallel steps with `waitFor` — steps that do not depend on each other can run
  simultaneously, cutting build time

**The default Cloud Build service account** is:

```
PROJECT_NUMBER@cloudbuild.gserviceaccount.com
```

This service account needs IAM roles for everything it does: pushing to Artifact Registry,
deploying to Cloud Run, writing to Cloud Storage, etc. The exam frequently tests this —
if a build step fails with a permissions error, the first thing to check is the Cloud Build
service account's roles.

#### cloudbuild.yaml Structure

```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'   # the container that runs this step
    args: ['build', '-t', 'us-central1-docker.pkg.dev/$PROJECT_ID/my-repo/my-image:$SHORT_SHA', '.']
    dir: 'app'                              # working directory inside the workspace
    id: 'build-image'                       # optional step ID for waitFor references

  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-central1-docker.pkg.dev/$PROJECT_ID/my-repo/my-image:$SHORT_SHA']
    waitFor: ['build-image']                # wait for build-image step to finish

substitutions:
  _MY_ENV: 'production'                     # user-defined substitution

images:
  - 'us-central1-docker.pkg.dev/$PROJECT_ID/my-repo/my-image:$SHORT_SHA'

options:
  logging: CLOUD_LOGGING_ONLY              # or: LEGACY (default), GCS_ONLY
  machineType: 'E2_HIGHCPU_8'             # override default worker machine type
```

**Built-in substitution variables** (always available):

| Variable | Value |
|---|---|
| `$PROJECT_ID` | GCP project ID |
| `$BUILD_ID` | Unique build UUID |
| `$SHORT_SHA` | First 7 characters of the commit SHA |
| `$COMMIT_SHA` | Full commit SHA |
| `$BRANCH_NAME` | Git branch name that triggered the build |
| `$TAG_NAME` | Git tag that triggered the build |
| `$REPO_NAME` | Name of the source repository |
| `$TRIGGER_NAME` | Name of the trigger that started the build |

**User-defined substitutions** must start with an underscore and be uppercase: `_MY_VAR`.
You pass them with `--substitutions=_MY_VAR=value` on the CLI or configure them in the
trigger definition.

> **ACE exam tip:** Cloud Build substitutions use single dollar signs in `cloudbuild.yaml`
> (`$PROJECT_ID`, `$SHORT_SHA`). If you are writing a shell script _inside_ a build step
> that needs those values at runtime, you escape with double dollar signs (`$$MY_VAR`) to
> prevent Cloud Build from substituting them before the shell sees them.

#### Build Triggers

A trigger watches a source repository and fires a build when an event matches:

| Trigger type | When it fires |
|---|---|
| Push to a branch | Any commit pushed to a branch matching a regex |
| Push a new tag | Any tag pushed matching a regex |
| Pull request | PR opened or updated (GitHub App only) |
| Manual | Triggered explicitly with `gcloud builds triggers run` |
| Pub/Sub message | A message is published to a specified topic |
| Webhook | An inbound HTTP POST to a Cloud Build-managed URL |

### Artifact Registry

Artifact Registry (AR) is the recommended storage for all build artefacts on GCP. It
replaces the older Container Registry (GCR, which used a `gcr.io` hostname). GCR is
deprecated — new projects should use Artifact Registry exclusively.

**Artifact Registry supports multiple format types:**

| Format | Hostname pattern | What it stores |
|---|---|---|
| Docker | `REGION-docker.pkg.dev/PROJECT/REPO` | Container images |
| Maven | `REGION-maven.pkg.dev/PROJECT/REPO` | Java JARs, POMs |
| npm | `REGION-npm.pkg.dev/PROJECT/REPO` | Node.js packages |
| Python | `REGION-python.pkg.dev/PROJECT/REPO` | Python wheels/sdists |
| Go | `REGION-go.pkg.dev/PROJECT/REPO` | Go modules |
| Apt | `REGION-apt.pkg.dev/PROJECT/REPO` | Debian packages |
| Yum | `REGION-yum.pkg.dev/PROJECT/REPO` | RPM packages |

**Key advantages of Artifact Registry over Container Registry:**

- **Per-repository IAM** — you can grant different teams different access to different
  repositories in the same project. With GCR, IAM was applied at the GCS bucket level
  for the whole project.
- **Multi-format** — one service for all artefact types, not just Docker images.
- **Vulnerability scanning** — optional automatic scanning of Docker images using
  Container Analysis, powered by the same backend as Google's own CVE scanning.
- **Regional isolation** — you choose the region for each repository, keeping data local
  for compliance or latency.

**Docker authentication against Artifact Registry:**

Before `docker push` or `docker pull` can talk to Artifact Registry, Docker must be
configured to use your gcloud credentials:

```bash
# Configure Docker to use gcloud credentials for the us-central1 registry endpoint
gcloud auth configure-docker us-central1-docker.pkg.dev
```

This writes a credential helper entry to `~/.docker/config.json`. Any subsequent
`docker push` or `docker pull` against `us-central1-docker.pkg.dev` will use your active
gcloud identity.

> **ACE exam tip:** Artifact Registry vs Container Registry is a common exam question.
> Remember: AR is the modern replacement, supports multiple formats, has per-repo IAM,
> and uses `REGION-docker.pkg.dev` as the hostname. GCR uses `gcr.io` / `us.gcr.io` and
> is deprecated for new projects.

### Cloud Deploy

Cloud Deploy is GCP's managed continuous delivery service. It manages the promotion of a
deployment through an ordered sequence of targets (environments).

```
Delivery Pipeline
    │
    ├── Target: dev     (Cloud Run service in dev project)
    ├── Target: staging (Cloud Run service in staging project)
    └── Target: prod    (Cloud Run service in prod project)
```

A **release** is a snapshot of the artefacts to deploy (e.g. a container image tag).
You create a release once, then **promote** it through the pipeline. Promotion can be
automatic (after passing verification hooks) or require manual approval.

**Cloud Deploy is particularly valuable when:**
- You have multiple environments that must receive the same artefacts in order
- You need an audit trail of every deployment: who promoted what to where, when
- Production deployments require a human approval step
- You want canary or blue/green rollout strategies built into the CD layer

For simple single-environment deployments (a single Cloud Run service), teams often skip
Cloud Deploy and let Cloud Build deploy directly via `gcloud run deploy`. Lab 12 covers
Cloud Deploy conceptually because it appears on the ACE exam — but the hands-on exercises
focus on Cloud Build and Artifact Registry, which are more commonly encountered.

### Cloud Scheduler

Cloud Scheduler is GCP's managed cron service. It is the equivalent of a crontab entry,
but hosted, managed, and observable through the GCP Console and APIs.

A scheduler job has three components:
1. **Schedule** — a unix-cron expression (e.g. `0 */6 * * *` for every 6 hours)
2. **Target** — what to invoke: an HTTP endpoint, a Pub/Sub topic, or an App Engine
   handler
3. **Retry config** — how many times to retry if the target returns an error

Cloud Scheduler guarantees **at-least-once delivery** — in rare cases a job may fire
more than once for a single scheduled time. Design your handlers to be idempotent (safe
to call multiple times for the same logical event).

On AWS, the equivalent is **Amazon EventBridge Scheduler** (formerly CloudWatch Events).

### Cloud Deployment Manager

Cloud Deployment Manager (CDM) is GCP's native infrastructure-as-code tool. You define
your infrastructure in YAML configuration files (with optional Jinja2 or Python templates
for parameterisation), and Deployment Manager creates, updates, or deletes the resources
to match your configuration.

**Deployment Manager vs Terraform:**

| Feature | Cloud Deployment Manager | Terraform |
|---|---|---|
| Provider support | GCP only | Multi-cloud (AWS, Azure, GCP, and 100+ others) |
| Language | YAML + Jinja2 / Python | HCL (HashiCorp Configuration Language) |
| State management | Managed by GCP (no state file to worry about) | State file (local or remote backend) |
| Drift detection | On `gcloud deployment-manager deployments update` | `terraform plan` |
| Maturity of GCP coverage | Full (direct API bindings) | Excellent (via `google` provider) |
| Community / ecosystem | Small | Very large |
| ACE exam relevance | Tested — know the basic concepts and commands | Not tested in ACE |

> **ACE exam tip:** The ACE exam does not test Terraform (that is the Professional Cloud
> DevOps Engineer exam). It does test Cloud Deployment Manager — specifically that it is
> GCP's native declarative infrastructure tool, uses YAML/Jinja2, and that deployments are
> managed with `gcloud deployment-manager deployments create/update/delete`. If you see a
> question about "declarative infrastructure on GCP without a third-party tool", the answer
> is Deployment Manager.

A minimal Deployment Manager configuration:

```yaml
# deployment.yaml
resources:
  - name: my-bucket
    type: storage.v1.bucket
    properties:
      location: US
      storageClass: STANDARD

  - name: my-instance
    type: compute.v1.instance
    properties:
      zone: us-central1-a
      machineType: zones/us-central1-a/machineTypes/e2-micro
      disks:
        - boot: true
          autoDelete: true
          initializeParams:
            sourceImage: projects/debian-cloud/global/images/family/debian-12
      networkInterfaces:
        - network: global/networks/default
```

Deploy it with:
```bash
gcloud deployment-manager deployments create my-deployment --config=deployment.yaml
```

### Pub/Sub

Pub/Sub is GCP's managed message queuing and streaming service. It decouples message
**publishers** (producers) from message **subscribers** (consumers) — the publisher does
not need to know anything about the downstream consumers, and consumers do not need to
know about upstream producers.

**Core concepts:**

```
Publisher                      Subscriber (pull)
    │                               │
    │ publishes message             │ polls for messages
    ▼                               │
[Topic]  ───────────────────►  [Subscription]
                                    │
                               or (push):
                               Pub/Sub delivers HTTP POST to subscriber endpoint
```

- **Topic** — the named channel. Publishers publish messages to a topic.
- **Subscription** — a named cursor on a topic. Each subscription gets a copy of every
  message published after the subscription was created.
- **Pull subscription** — the subscriber calls `gcloud pubsub subscriptions pull` (or the
  API) to retrieve messages. The subscriber controls the pace.
- **Push subscription** — Pub/Sub sends an HTTP POST to a configured URL for each message.
  Good for Cloud Run and Cloud Functions targets.
- **Dead-letter topic** — messages that fail delivery after the maximum retry count are
  forwarded to a dead-letter topic for inspection.
- **Message retention** — by default messages are retained for 7 days. Undelivered
  messages within the retention period can be replayed.

**Pub/Sub vs Cloud Tasks:**

| | Pub/Sub | Cloud Tasks |
|---|---|---|
| Delivery model | Fan-out (one topic, many subscriptions each get a copy) | Point-to-point (one task, one handler) |
| Rate control | Limited (subscription flow control) | Fine-grained (max dispatches/second, max concurrent) |
| Deduplication | No (at-least-once) | No (at-least-once) |
| Scheduling | No | Yes (scheduled future execution) |
| Use case | Event broadcasting, streaming pipelines | Job queues, rate-limited API calls, scheduled one-off tasks |

### Eventarc

Eventarc is GCP's unified event routing service. It routes events from over 90 GCP
services to Cloud Run, Cloud Functions (Gen 2), and Workflows using the CloudEvents
standard format.

```
GCP service emits event
(e.g. new object in Cloud Storage, new BigQuery job, Pub/Sub message)
    │
    ▼
Eventarc trigger
(matches on event type + resource filters)
    │
    ▼
Cloud Run service / Cloud Function / Workflow
```

Eventarc replaces the older per-product eventing mechanisms (e.g. Cloud Storage object
change notifications, Pub/Sub push subscriptions to functions). By standardising on
CloudEvents format, it makes event-driven architectures consistent regardless of the
source service.

> **ACE exam tip:** For the exam, know that Cloud Functions Gen 2 uses Eventarc for its
> event triggers (covered in lab 08). Eventarc is the glue between GCP services and your
> serverless handlers.

### gcloud Scripting Patterns

The gcloud CLI is designed for scripting. Key patterns for reliable scripts:

**Extracting single values with `--format=value()`:**
```bash
PROJECT_ID=$(gcloud config get-value project)
IMAGE_DIGEST=$(gcloud artifacts docker images describe \
  "us-central1-docker.pkg.dev/${PROJECT_ID}/lab12-repo/lab12-app:latest" \
  --format="value(image_summary.digest)")
```

**Filtering lists:**
```bash
# Find builds that failed in the last hour
gcloud builds list \
  --filter="status=FAILURE AND createTime>-PT1H" \
  --format="table(id,status,createTime,duration)"
```

**Checking whether a resource exists before creating it:**
```bash
if gcloud artifacts repositories describe lab12-repo \
     --location=us-central1 \
     --project="${PROJECT_ID}" &>/dev/null; then
  echo "Repository already exists — skipping creation."
else
  gcloud artifacts repositories create lab12-repo \
    --repository-format=docker \
    --location=us-central1 \
    --project="${PROJECT_ID}"
fi
```

**Failing fast with `set -euo pipefail`:**
```bash
#!/bin/bash
set -euo pipefail  # exit on error, undefined variable, or pipe failure
# ... rest of script
```

---

## Setup

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
  --format="value(projectNumber)")
export REGION="us-central1"
export REPO="lab12-repo"
export IMAGE_BASE="us-central1-docker.pkg.dev/${PROJECT_ID}/${REPO}/lab12-app"

echo "Project ID:     ${PROJECT_ID}"
echo "Project Number: ${PROJECT_NUMBER}"
echo "Region:         ${REGION}"
echo "Image base:     ${IMAGE_BASE}"
```

### Cloud Build Service Account Permissions

Grant the Cloud Build service account the roles it needs for this lab:

```bash
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

echo "Cloud Build service account: ${CB_SA}"

# Artifact Registry Writer — push images
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/artifactregistry.writer"

# Cloud Run Developer — deploy to Cloud Run in exercise 4
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/run.developer"

# Service Account User — needed when deploying Cloud Run (acts as the run SA)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:${CB_SA}" \
  --role="roles/iam.serviceAccountUser"
```

Expected output (last binding — followed by the full IAM policy YAML, which is normal):
```
Updated IAM policy for project [YOUR_PROJECT].
bindings:
- ...
```

---

## Exercises

### Exercise 1 — Create an Artifact Registry Docker Repository

Artifact Registry repositories are regional resources. Each repository stores artefacts of
one format type (Docker, Maven, npm, etc.) and has its own IAM policy. You will create a
Docker repository to store container images for the rest of this lab.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
REPO="lab12-repo"

gcloud artifacts repositories create "${REPO}" \
  --repository-format=docker \
  --location="${REGION}" \
  --description="Lab 12 Docker repository for CI/CD exercises" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created repository [lab12-repo].
```

Verify the repository was created and note the hostname format:

```bash
gcloud artifacts repositories describe "${REPO}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="table(name.basename(),format,name.segment(3):label=LOCATION,createTime)"
```

Expected output:
```
NAME        FORMAT  LOCATION     CREATE_TIME
lab12-repo  DOCKER  us-central1  2026-06-...
```

List all repositories in the project to see what already exists (Cloud Build and Cloud Run
often auto-create repositories):

```bash
gcloud artifacts repositories list \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="table(name.basename(),format,name.segment(3):label=LOCATION)"
```

Now configure Docker to authenticate against your Artifact Registry endpoint. This writes
a credential helper to `~/.docker/config.json` so every subsequent `docker` command can
push and pull from `us-central1-docker.pkg.dev`:

```bash
gcloud auth configure-docker us-central1-docker.pkg.dev --quiet
```

Expected output:
```
Adding credentials for: us-central1-docker.pkg.dev
Docker configuration file updated.
```

> **ACE exam tip:** Artifact Registry Docker repositories use the hostname pattern
> `REGION-docker.pkg.dev/PROJECT_ID/REPO_NAME/IMAGE_NAME:TAG`. Container Registry (GCR)
> used `gcr.io/PROJECT_ID/IMAGE_NAME:TAG`. This hostname difference is how exam questions
> distinguish between the two services.

---

### Exercise 2 — Build and Push a Container Image to Artifact Registry

Build a minimal Go HTTP server locally, containerise it, and push the image to the
Artifact Registry repository you just created. This is the "manual CI" path — building
locally before you automate it with Cloud Build.

Build the Docker image locally and tag it with the full Artifact Registry path:

```bash
PROJECT_ID=$(gcloud config get-value project)
IMAGE_BASE="us-central1-docker.pkg.dev/${PROJECT_ID}/lab12-repo/lab12-app"

docker build --platform linux/amd64 -t "${IMAGE_BASE}:v1.0.0" lab12-app
```

Expected output (multi-stage build, last few lines — build time ~10-15s on first run):
```
 => [build 5/5] RUN go build -o /app/server .                              3.8s
 => [stage-1 3/3] COPY --from=build /app/server .                          0.0s
 => exporting to image                                                      0.2s
 => => naming to us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app:v1.0.0
 => => unpacking to us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app:v1.0.0
```

Push the image to Artifact Registry:

```bash
docker push "${IMAGE_BASE}:v1.0.0"
```

Expected output (Docker Desktop pushes layers during build, so they'll report as already existing):
```
The push refers to repository [us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app]
2ab192d5f71f: Layer already exists
...
v1.0.0: digest: sha256:fe2a... size: 855
```

Also tag it as `latest` and push that tag too:

```bash
docker tag "${IMAGE_BASE}:v1.0.0" "${IMAGE_BASE}:latest"
docker push "${IMAGE_BASE}:latest"
```

Verify the image is in Artifact Registry:

```bash
gcloud artifacts docker images list \
  "us-central1-docker.pkg.dev/${PROJECT_ID}/lab12-repo" \
  --format="table(IMAGE,DIGEST,CREATE_TIME)" \
  --project="${PROJECT_ID}"

gcloud artifacts docker tags list \
  "us-central1-docker.pkg.dev/${PROJECT_ID}/lab12-repo/lab12-app" \
  --project="${PROJECT_ID}"
```

Expected output:
```
IMAGE                                                           DIGEST        CREATE_TIME
us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app  sha256:9ffc...  2026-06-...
us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app  sha256:a82b...  2026-06-...
us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app  sha256:fe2a...  2026-06-...

TAG     IMAGE
latest  us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app@sha256:fe2a...
v1.0.0  us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app@sha256:fe2a...
```

Describe the specific image to see its full digest and metadata:

```bash
gcloud artifacts docker images describe "${IMAGE_BASE}:v1.0.0" \
  --project="${PROJECT_ID}"
```

Expected output:
```
image_summary:
  digest: sha256:abc123...
  fully_qualified_digest: us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app@sha256:abc123...
  registry: us-central1-docker.pkg.dev
  repository: lab12-repo
  ...
```

> **Why use the digest instead of a tag?** Tags are mutable — `:latest` today and `:latest`
> tomorrow may point to different images. In production deployments, reference images by
> their immutable `sha256:...` digest to guarantee you are deploying exactly what you
> tested. Cloud Build automatically records the digest of every pushed image in its build
> log.

---

### Exercise 3 — Pull the Image in a Cloud Build Step

Cloud Build steps can pull and use any image, including images from your own Artifact
Registry repository. This exercise demonstrates using your `lab12-app` image as a step
in a build — the canonical pattern for running integration tests against a freshly built
image.

`lab12-pulltest.cloudbuild.yaml` does three things:
1. Pulls the previously pushed image
2. Runs it briefly to verify it starts up
3. Reports the version it is serving

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
```

Submit it to Cloud Build:

```bash
gcloud builds submit \
  --config=lab12-pulltest.cloudbuild.yaml \
  --no-source \
  --project="${PROJECT_ID}" \
  --region="${REGION}"
```

The `--no-source` flag tells Cloud Build not to upload any source directory — this build
uses no local source files, only the cloud-resident image.

Expected output:
```
Creating temporary tarball archive of 0 file(s) totalling 0 bytes before compression.
Uploading tarball of [.] to [gs://YOUR_PROJECT_cloudbuild/source/...
...
BUILD
Starting Step #0 - "run-app-check"
Step #0 - "run-app-check": Image pulled and started successfully
Finished Step #0 - "run-app-check"
Starting Step #1 - "describe-image"
...
PUSH
DONE
--------------------------------------------------------------------------------
ID                                    CREATE_TIME                DURATION  SOURCE  IMAGES  STATUS
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  2026-01-15T10:00:00+00:00  11S       -       -       SUCCESS
```

View the build in Cloud Build history:

```bash
gcloud builds list \
  --region="${REGION}" \
  --limit=5 \
  --format="table(id,status,createTime,duration)" \
  --project="${PROJECT_ID}"
```

Expected output:
```
ID                                    STATUS   CREATE_TIME                   DURATION
abc12345-...                          SUCCESS  2024-01-15T10:15:00+00:00     15S
```

---

### Exercise 4 — Build, Test, and Push With a Cloud Build Pipeline

This exercise is the core of the lab. `lab12-main.cloudbuild.yaml` is a production-style
pipeline that mirrors what a real CI pipeline does: build the image from source, run a
smoke test against it, then push it to Artifact Registry if the test passes.

The build will fail intentionally in one variation to demonstrate failure modes — this
is how you learn to debug Cloud Build.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
SHORT_SHA=$(git rev-parse --short HEAD)
```

`$SHORT_SHA` is automatically populated by Cloud Build when a trigger fires from a git
commit. For manual `gcloud builds submit` it is empty, so we pass it explicitly using
the current repo HEAD.

Submit the build. The source directory is uploaded to Cloud Storage and the build runs
on Cloud Build workers:

```bash
gcloud builds submit lab12-app \
  --config=lab12-main.cloudbuild.yaml \
  --substitutions="SHORT_SHA=${SHORT_SHA}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Creating temporary archive of 3 file(s) totalling 1.0 KiB before compression.
Uploading tarball of [lab12-app] to [gs://YOUR_PROJECT_cloudbuild/source/...]
Created [https://cloudbuild.googleapis.com/v1/projects/YOUR_PROJECT/locations/us-central1/builds/xxxxxxxx-...].
Logs are available at [ https://console.cloud.google.com/cloud-build/builds;region=us-central1/xxxxxxxx-...?project=YOUR_PROJECT_NUMBER ].

gcloud builds submit only displays logs from Cloud Storage. To view logs from Cloud Logging, run:
gcloud beta builds submit

Waiting for build to complete. Polling interval: 1 second(s).
ID                                    CREATE_TIME                DURATION  SOURCE                                        IMAGES                                                              STATUS
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  2026-01-15T10:00:00+00:00  41S       gs://YOUR_PROJECT_cloudbuild/source/...tgz    us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app:abcdef1 (+2 more)  SUCCESS
```

**Now intentionally break the smoke test to observe a failure.** `lab12-app-broken`
contains an identical app but with a Dockerfile that runs on the wrong port, so the
health check cannot connect:

```bash
gcloud builds submit lab12-app-broken \
  --config=lab12-main.cloudbuild.yaml \
  --substitutions="SHORT_SHA=${SHORT_SHA}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output (the build fails at the smoke test step):
```
Creating temporary archive of 3 file(s) totalling 1.1 KiB before compression.
Uploading tarball of [lab12-app-broken] to [gs://YOUR_PROJECT_cloudbuild/source/...]
Created [https://cloudbuild.googleapis.com/v1/projects/YOUR_PROJECT/locations/us-central1/builds/xxxxxxxx-...].
Logs are available at [ https://console.cloud.google.com/cloud-build/builds;region=us-central1/xxxxxxxx-...?project=YOUR_PROJECT_NUMBER ].

gcloud builds submit only displays logs from Cloud Storage. To view logs from Cloud Logging, run:
gcloud beta builds submit

Waiting for build to complete. Polling interval: 1 second(s).

BUILD FAILURE: Build step failure: build step 2 "curlimages/curl:8.5.0" failed: step exited with non-zero status: 7
ERROR: (gcloud.builds.submit) build xxxxxxxx-... completed with status "FAILURE"
```

This is the point: **the push steps never run because the smoke test failed**. The
`waitFor` dependency chain means Cloud Build stops as soon as any step exits with a
non-zero status code. Resubmit using the original checked-in source:

```bash
gcloud builds submit lab12-app \
  --config=lab12-main.cloudbuild.yaml \
  --substitutions="SHORT_SHA=${SHORT_SHA}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

The build should succeed again. Verify the new image tag is in Artifact Registry:

```bash
gcloud artifacts docker images list \
  "us-central1-docker.pkg.dev/${PROJECT_ID}/lab12-repo" \
  --include-tags \
  --format="table(package,tags,createTime)" \
  --project="${PROJECT_ID}"
```

Expected output (you should see multiple `$SHORT_SHA` tags from the builds you ran):
```
PACKAGE                                                                ...  TAGS              CREATE_TIME
us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app             latest,abcdef1     2024-01-15T10:25:00
us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app             1234567            2024-01-15T10:20:00
```

> **Why smoke test in the pipeline?** The canonical CI rule is: fail fast, fail early. If
> you discover a broken container only after it reaches production, the cost of the failure
> is much higher than a build that takes an extra 30 seconds to run a smoke test. The
> `waitFor` dependency graph means the push step is gated on the test step — broken images
> never reach the registry.

---

### Exercise 5 — Push Source to Cloud Source Repositories

A Cloud Build trigger automatically starts a build when source code changes. This exercise
creates a Cloud Source Repository (GCP's managed private git service) and pushes the lab12
source code to it. In practice you would then attach a trigger that builds on every push
to the `main` branch — the trigger concepts are covered below.

> **Note:** Cloud Source Repositories was deprecated by Google in 2025. The CSR API still
> accepts repository creation and pushes, but programmatic trigger creation via `gcloud` or
> the Cloud Build API returns `INVALID_ARGUMENT`. Triggers can still be created manually
> via the Cloud Console at **Cloud Build → Triggers → Create trigger**, where you select
> Cloud Source Repositories as the source. For production workloads, use GitHub, GitLab,
> or Bitbucket as your source provider.

Create a Cloud Source Repository:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud source repos create lab12-source \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [lab12-source].
WARNING: You may be billed for this repository. See https://cloud.google.com/source-repositories/docs/pricing for details.
```

Push the lab12 source to it:

```bash
REGION="us-central1"
REPO_URL="https://source.developers.google.com/p/${PROJECT_ID}/r/lab12-source"

mkdir -p /tmp/lab12-source-repo
cp -r lab12-app/. /tmp/lab12-source-repo/
cp lab12-main.cloudbuild.yaml /tmp/lab12-source-repo/cloudbuild.yaml

cd /tmp/lab12-source-repo
git init
git remote add origin "${REPO_URL}"
git config --local user.email "lab12@example.com"
git config --local user.name "Lab 12"
git config --local credential.helper '!f() { echo "username=oauth2accesstoken"; echo "password=$(gcloud auth print-access-token)"; }; f'
git add .
git commit -m "Initial commit: lab12 app source"
git push -u origin main
```

Expected output:
```
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
...
To https://source.developers.google.com/p/YOUR_PROJECT/r/lab12-source
 * [new branch]      main -> main
```

**Trigger concepts:** When a trigger is connected to this repository, Cloud Build would:

1. Watch for pushes to branches matching the pattern (e.g. `^main$`)
2. On each match, clone the repo at that commit and upload it as build source
3. Run the steps in `cloudbuild.yaml`, with `$SHORT_SHA` and `$COMMIT_SHA` automatically
   populated from the triggering commit
4. Report build status back to the source provider

> **ACE exam tip:** Cloud Build triggers require the Cloud Build service account to have
> read access to the source repository. For Cloud Source Repositories this is automatic
> because the service account already has access within the project. For GitHub, you
> authorise via the Cloud Build GitHub App. For GitLab, you use a Mirror trigger.
> The trigger itself does not store credentials — it relies on the service account IAM
> binding and the source connection.

---

### Exercise 6 — Use Substitutions and Build Environment Variables

Substitutions let you parameterise a `cloudbuild.yaml` so the same config can be used
with different values for different environments. This exercise rewrites the `cloudbuild.yaml`
to accept an `_ENV` substitution that controls where the image is tagged and what version
label is embedded.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
SHORT_SHA=$(git rev-parse --short HEAD)
```

Submit the build passing custom substitution values:

```bash
gcloud builds submit lab12-app \
  --config=lab12-subs.cloudbuild.yaml \
  --substitutions="_ENV=staging,_IMAGE_TAG=v2.0.0,SHORT_SHA=${SHORT_SHA}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Creating temporary archive of 3 file(s) totalling 1.0 KiB before compression.
Uploading tarball of [lab12-app] to [gs://YOUR_PROJECT_cloudbuild/source/...]
Created [https://cloudbuild.googleapis.com/v1/projects/YOUR_PROJECT/locations/us-central1/builds/xxxxxxxx-...].
Logs are available at [ https://console.cloud.google.com/cloud-build/builds;region=us-central1/xxxxxxxx-...?project=YOUR_PROJECT_NUMBER ].

gcloud builds submit only displays logs from Cloud Storage. To view logs from Cloud Logging, run:
gcloud beta builds submit

Waiting for build to complete. Polling interval: 1 second(s).
ID                                    CREATE_TIME                DURATION  SOURCE                                        IMAGES                                                              STATUS
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  2026-01-15T10:00:00+00:00  33S       gs://YOUR_PROJECT_cloudbuild/source/...tgz    us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app:abcdef1  SUCCESS
```

To see the substitutions report, open the build in the Cloud Console using the URL printed
above, or run:

```bash
BUILD_ID=$(gcloud builds list \
  --region="${REGION}" \
  --filter="substitutions._ENV=staging" \
  --limit=1 \
  --format="value(id)" \
  --project="${PROJECT_ID}")

gcloud builds log "${BUILD_ID}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

The output streams the full build log (Python `SyntaxWarning` lines at the top are noise
from gcloud's internal libraries — ignore them). Look for the substitutions report:
```
----------------------------- REMOTE BUILD OUTPUT ------------------------------
starting build "xxxxxxxx-..."
FETCHSOURCE
...
BUILD
Starting Step #0 - "build"
...
Step #0 - "build": Successfully tagged us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app:abcdef1
Finished Step #0 - "build"
Starting Step #1 - "report-substitutions"
Step #1 - "report-substitutions": ===== Substitutions report =====
Step #1 - "report-substitutions": Environment:   staging
Step #1 - "report-substitutions": Image tag:     v2.0.0
Step #1 - "report-substitutions": Short SHA:     abcdef1
Step #1 - "report-substitutions": Commit SHA:
Step #1 - "report-substitutions": Build ID:      xxxxxxxx-...
Step #1 - "report-substitutions": Project:       YOUR_PROJECT
Step #1 - "report-substitutions": Trigger:
Step #1 - "report-substitutions": ================================
Finished Step #1 - "report-substitutions"
...
PUSH
...
DONE
```

Notice that `$COMMIT_SHA` and `$TRIGGER_NAME` are empty for manually submitted builds —
they are only set when a trigger fires from a source commit. `$SHORT_SHA` is also normally
empty for manual builds, which is why we pass it explicitly via `--substitutions`. This is
important for scripts that conditionally branch on whether a build was triggered or manual.

Submit again without the user-defined substitutions to see the defaults apply:

```bash
gcloud builds submit lab12-app \
  --config=lab12-subs.cloudbuild.yaml \
  --substitutions="SHORT_SHA=${SHORT_SHA}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Creating temporary archive of 3 file(s) totalling 1.0 KiB before compression.
Uploading tarball of [lab12-app] to [gs://YOUR_PROJECT_cloudbuild/source/...]
...
Waiting for build to complete. Polling interval: 1 second(s).
ID                                    CREATE_TIME                DURATION  SOURCE                                        IMAGES                                                              STATUS
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  2026-01-15T10:00:00+00:00  45S       gs://YOUR_PROJECT_cloudbuild/source/...tgz    us-central1-docker.pkg.dev/YOUR_PROJECT/lab12-repo/lab12-app:abcdef1  SUCCESS
```

Fetch the log to confirm the defaults were used:

```bash
BUILD_ID=$(gcloud builds list \
  --region="${REGION}" \
  --filter="substitutions._ENV=dev" \
  --limit=1 \
  --format="value(id)" \
  --project="${PROJECT_ID}")

gcloud builds log "${BUILD_ID}" \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Look for the substitutions report section in the output:
```
Step #1 - "report-substitutions": ===== Substitutions report =====
Step #1 - "report-substitutions": Environment:   dev
Step #1 - "report-substitutions": Image tag:     latest
Step #1 - "report-substitutions": Short SHA:     abcdef1
Step #1 - "report-substitutions": Commit SHA:
Step #1 - "report-substitutions": Build ID:      xxxxxxxx-...
Step #1 - "report-substitutions": Project:       YOUR_PROJECT
Step #1 - "report-substitutions": Trigger:
Step #1 - "report-substitutions": ================================
```

> **Substitution validation:** By default Cloud Build raises an error if you reference an
> undefined substitution variable. You can relax this with
> `options: substitution_option: ALLOW_LOOSE` — this lets you use substitutions only when
> they are provided, falling back to empty strings otherwise. Use strict mode (the default)
> in production; it catches typos in variable names immediately.

---

### Exercise 7 — Create a Cloud Scheduler Job That Calls an HTTP Endpoint

Cloud Scheduler invokes HTTP endpoints on a cron schedule. This exercise deploys the
`lab12-app` container image to Cloud Run, then creates a Scheduler job that hits its
`/health` endpoint every 5 minutes — a common pattern for "keep-alive pings" on Cloud
Run services where you want to prevent cold starts without paying for `--min-instances=1`.

Deploy the container image from Artifact Registry to Cloud Run:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
IMAGE_BASE="us-central1-docker.pkg.dev/${PROJECT_ID}/lab12-repo/lab12-app"

gcloud run deploy lab12-app \
  --image="${IMAGE_BASE}:latest" \
  --platform=managed \
  --region="${REGION}" \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=3 \
  --project="${PROJECT_ID}"
```

Expected output:
```
Deploying container to Cloud Run service [lab12-app] in project [YOUR_PROJECT] region [us-central1]
✓ Deploying new service... Done.
  ✓ Creating Revision...
  ✓ Routing traffic...
Done.
Service [lab12-app] revision [lab12-app-00001-abc] has been deployed and is serving 100 percent of traffic.
Service URL: https://lab12-app-xxxxxxxxxx-uc.a.run.app
```

Capture the service URL:

```bash
SERVICE_URL=$(gcloud run services describe lab12-app \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

echo "Service URL: ${SERVICE_URL}"
curl -s "${SERVICE_URL}/health"
```

Expected output:
```
ok
```

Create the Cloud Scheduler job. The schedule `*/5 * * * *` means every 5 minutes. The
`--uri` parameter is the full URL to call, and `--http-method=GET` is the HTTP verb:

```bash
gcloud scheduler jobs create http lab12-health-ping \
  --location="${REGION}" \
  --schedule="*/5 * * * *" \
  --uri="${SERVICE_URL}/health" \
  --http-method=GET \
  --description="Keep-alive ping for lab12-app Cloud Run service" \
  --attempt-deadline=30s \
  --max-retry-attempts=3 \
  --max-retry-duration=90s \
  --project="${PROJECT_ID}"
```

Expected output:
```
name: projects/YOUR_PROJECT/locations/us-central1/jobs/lab12-health-ping
schedule: '*/5 * * * *'
state: ENABLED
status: {}
timeZone: Etc/UTC
...
```

Trigger the job immediately (do not wait for the scheduled time) to verify it works:

```bash
gcloud scheduler jobs run lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
(no output — success is indicated by exit code 0)
```

Describe the job to see the result of the last attempt:

```bash
gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```yaml
attemptDeadline: 30s
description: Keep-alive ping for lab12-app Cloud Run service
httpTarget:
  headers:
    User-Agent: Google-Cloud-Scheduler
  httpMethod: GET
  uri: https://lab12-app-xxxxxxxxxx-uc.a.run.app/health
name: projects/YOUR_PROJECT/locations/us-central1/jobs/lab12-health-ping
retryConfig:
  maxBackoffDuration: 3600s
  maxDoublings: 5
  maxRetryDuration: 90s
  minBackoffDuration: 5s
  retryCount: 3
schedule: '*/5 * * * *'
scheduleTime: '2026-01-15T10:55:00Z'
state: ENABLED
status:
  code: -1    # -1 = no attempt yet; will change to 0 (success) after first run
timeZone: Etc/UTC
userUpdateTime: '2026-01-15T10:50:00Z'
```

`status.code: -1` means the job has not yet made an attempt — it was just created and the
first scheduled run (shown in `scheduleTime`) has not fired yet. After the first successful
invocation it will change to `0`.

Trigger the job manually and poll until the attempt completes:

```bash
PREV_ATTEMPT=$(gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(lastAttemptTime)")

gcloud scheduler jobs run lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

echo "Waiting for job attempt to complete..."
until [[ "$(gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(lastAttemptTime)" 2>/dev/null)" != "${PREV_ATTEMPT}" ]]; do
  echo "  still pending — retrying in 5s..."; sleep 5
done

gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(status,lastAttemptTime)"
```

Expected output:
```yaml
lastAttemptTime: '2026-01-15T10:55:00Z'
status: {}
```

`status: {}` means success — Cloud Scheduler omits the error code when the HTTP call
returned a 2xx response.

Now deliberately break the scheduler by pointing it at a non-existent path to observe a
failure and retry:

```bash
gcloud scheduler jobs update http lab12-health-ping \
  --location="${REGION}" \
  --uri="${SERVICE_URL}/this-path-does-not-exist" \
  --project="${PROJECT_ID}"

PREV_ATTEMPT=$(gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(lastAttemptTime)")

gcloud scheduler jobs run lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

echo "Waiting for new job attempt to complete..."
until [[ "$(gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(lastAttemptTime)" 2>/dev/null)" != "${PREV_ATTEMPT}" ]]; do
  echo "  still pending — retrying in 5s..."; sleep 5
done

gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(status,lastAttemptTime)"
```

Expected output (the non-zero status code indicates failure):
```yaml
lastAttemptTime: '2026-01-15T10:56:00Z'
status:
  code: 5
```

`status.code: 5` is the gRPC NOT_FOUND code, which Cloud Scheduler reports for an HTTP 404
response. Any non-empty `status.code` means the attempt failed.

Fix the job by restoring the correct URL and confirm it passes again:

```bash
gcloud scheduler jobs update http lab12-health-ping \
  --location="${REGION}" \
  --uri="${SERVICE_URL}/health" \
  --project="${PROJECT_ID}"

PREV_ATTEMPT=$(gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(lastAttemptTime)")

gcloud scheduler jobs run lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

echo "Waiting for job attempt to complete..."
until [[ "$(gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(lastAttemptTime)" 2>/dev/null)" != "${PREV_ATTEMPT}" ]]; do
  echo "  still pending — retrying in 5s..."; sleep 5
done

gcloud scheduler jobs describe lab12-health-ping \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(status,lastAttemptTime)"
```

Expected output:
```yaml
lastAttemptTime: '2026-01-15T10:57:00Z'
status: {}
```

> **ACE exam tip:** Cloud Scheduler jobs are regional. The `--location` flag in every
> Scheduler command specifies the region, not a zone. If you need a job to run in multiple
> regions for redundancy, you must create separate jobs in each region. A single Scheduler
> job can invoke a global endpoint (like a global load balancer IP) — the job's region
> only determines where the invocation originates from.

---

### Exercise 8 — A Multi-Step gcloud Script With Error Handling

Real automation scripts need to handle errors gracefully: check preconditions, fail fast
when something goes wrong, clean up partial state, and provide informative messages. This
exercise writes a gcloud script that:

1. Creates a Pub/Sub topic
2. Creates a Cloud Storage bucket
3. Publishes a test message to the topic
4. Verifies the message can be pulled from a subscription
5. Cleans up the resources it created, even if an earlier step failed

The script is already checked in as `lab12-script.sh`. Run it directly:

```bash
./lab12-script.sh
```

Expected output:
```
=== Lab 12 multi-step gcloud script ===
Project: YOUR_PROJECT
Topic:   lab12-script-topic
Bucket:  YOUR_PROJECT-lab12-script

--- Step 1: Checking preconditions ---
All required APIs are enabled.

--- Step 2: Creating Pub/Sub topic and subscription ---
Created topic [projects/YOUR_PROJECT/topics/lab12-script-topic].
Topic created: lab12-script-topic
Created subscription [projects/YOUR_PROJECT/subscriptions/lab12-script-sub].
Subscription created: lab12-script-sub

--- Step 3: Creating Cloud Storage bucket ---
Creating gs://YOUR_PROJECT-lab12-script/...
Bucket created: gs://YOUR_PROJECT-lab12-script

--- Step 4: Publishing test message ---
Published message ID: 1234567890123456

--- Step 5: Pulling and verifying message ---
Message received: {"event":"lab12-test","timestamp":"2024-01-15T10:50:00Z"}

=== All steps succeeded ===

=== Cleanup (exit code: 0) ===
Deleting Pub/Sub subscription...
Deleted subscription [projects/YOUR_PROJECT/subscriptions/lab12-script-sub].
Deleting Pub/Sub topic...
Deleted topic [projects/YOUR_PROJECT/topics/lab12-script-topic].
Deleting Cloud Storage bucket...
Removing objects...
Removed gs://YOUR_PROJECT-lab12-script/...
Deleted bucket gs://YOUR_PROJECT-lab12-script.
=== Cleanup complete ===
```

Notice that the cleanup function ran even though the script succeeded — `trap cleanup EXIT`
fires on any exit, whether from `exit 0`, `exit 1`, or an unexpected error from
`set -euo pipefail`. This is the standard pattern for resource cleanup in bash scripts
and mirrors how `defer` works in Go or `finally` in Java.

To test the failure path, run the checked-in broken version which uses an invalid bucket
name to force a failure at step 3:

```bash
./lab12-script-broken.sh
```

Expected output (bucket creation fails, cleanup still runs and removes the topic and subscription that were already created):
```
--- Step 3: Creating Cloud Storage bucket ---
ERROR: ...
=== Cleanup (exit code: 1) ===
Deleting Pub/Sub subscription...
Deleted subscription...
Deleting Pub/Sub topic...
Deleted topic...
Deleting Cloud Storage bucket...
  Bucket not found — skipping.
```

The `set -e` flag caused the script to exit immediately when `gcloud storage buckets create`
failed. The `trap` then ran cleanup, removing the topic and subscription that were already
created — preventing a leak of resources.

---

### Exercise 9 — Create a Cloud Deployment Manager Config and Deploy It

Cloud Deployment Manager (CDM) lets you declare GCP resources in YAML and manage them as
a unit called a **deployment**. This exercise creates a deployment that provisions a Cloud
Storage bucket and a Pub/Sub topic. You will then update the deployment to add a second
bucket, then delete the entire deployment in one command.

The configuration is already checked in as `lab12-dm.deployment.yaml`.

```bash
PROJECT_ID=$(gcloud config get-value project)
```

Deploy it. The `--preview` flag shows what Deployment Manager would create without actually
creating anything — useful for validating configuration before applying it:

```bash
gcloud deployment-manager deployments create lab12-dm-deploy \
  --config=lab12-dm.deployment.yaml \
  --preview \
  --project="${PROJECT_ID}"
```

Expected output:
```
The following will be created or updated:
NAME              TYPE                  STATE
lab12-dm-bucket   storage.v1.bucket     TO_BE_CREATED
lab12-dm-topic    pubsub.v1.topic       TO_BE_CREATED

Previewing resources...done.

NAME                   LAST_OPERATION_TYPE  STATUS   DESCRIPTION
lab12-dm-deploy        preview              PREVIEW
```

Actually create the resources by cancelling the preview and creating without it:

```bash
# Cancel the preview first
gcloud deployment-manager deployments cancel-preview lab12-dm-deploy \
  --project="${PROJECT_ID}"

# Create for real
gcloud deployment-manager deployments create lab12-dm-deploy \
  --config=lab12-dm.deployment.yaml \
  --project="${PROJECT_ID}"
```

Expected output:
```
Waiting for create [operation-...]...done.
Create operation operation-... completed successfully.
NAME                   LAST_OPERATION_TYPE  STATUS  DESCRIPTION  MANIFEST                  ERRORS
lab12-dm-deploy        insert               DONE                 manifest-...
```

Describe the deployment to see what was created:

```bash
gcloud deployment-manager deployments describe lab12-dm-deploy \
  --project="${PROJECT_ID}"
```

Expected output:
```
---
fingerprint: ...
id: '1234567890'
name: lab12-dm-deploy
...
resources:
- name: lab12-dm-bucket
  type: storage.v1.bucket
  url: https://www.googleapis.com/storage/v1/b/lab12-dm-bucket
- name: lab12-dm-topic
  type: pubsub.v1.topic
  url: https://pubsub.googleapis.com/v1/projects/YOUR_PROJECT/topics/lab12-dm-topic
```

List all resources in the deployment:

```bash
gcloud deployment-manager resources list \
  --deployment=lab12-dm-deploy \
  --project="${PROJECT_ID}" \
  --format="table(name,type,state)"
```

Expected output:
```
NAME               TYPE               STATE
lab12-dm-bucket    storage.v1.bucket  IN_USE
lab12-dm-topic     pubsub.v1.topic    IN_USE
```

Update the deployment to add a second bucket. Copy the config to a working file, append
the new resource, and run `deployments update`:

```bash
cp lab12-dm.deployment.yaml /tmp/lab12-dm-updated.yaml

cat >> /tmp/lab12-dm-updated.yaml << 'YAMLEOF'

  - name: lab12-dm-bucket-logs
    type: storage.v1.bucket
    properties:
      location: US
      storageClass: NEARLINE
      iamConfiguration:
        uniformBucketLevelAccess:
          enabled: true
YAMLEOF

gcloud deployment-manager deployments update lab12-dm-deploy \
  --config=/tmp/lab12-dm-updated.yaml \
  --project="${PROJECT_ID}"
```

Expected output:
```
Waiting for update [operation-...]...done.
Update operation operation-... completed successfully.
NAME                   LAST_OPERATION_TYPE  STATUS  DESCRIPTION
lab12-dm-deploy        update               DONE
```

Verify the new bucket was added:

```bash
gcloud deployment-manager resources list \
  --deployment=lab12-dm-deploy \
  --project="${PROJECT_ID}" \
  --format="table(name,type,state)"
```

Expected output:
```
NAME                    TYPE               STATE
lab12-dm-bucket         storage.v1.bucket  IN_USE
lab12-dm-bucket-logs    storage.v1.bucket  IN_USE
lab12-dm-topic          pubsub.v1.topic    IN_USE
```

Now delete the entire deployment — Deployment Manager deletes all the resources it created
in the correct dependency order:

```bash
gcloud deployment-manager deployments delete lab12-dm-deploy \
  --quiet \
  --project="${PROJECT_ID}"
```

Expected output:
```
Waiting for delete [operation-...]...done.
Delete operation operation-... completed successfully.
```

Verify the resources are gone:

```bash
echo "--- Buckets ---"
gcloud storage buckets list \
  --filter="name:lab12-dm" \
  --project="${PROJECT_ID}"

echo "--- Pub/Sub topics ---"
gcloud pubsub topics list \
  --filter="name:lab12-dm" \
  --project="${PROJECT_ID}"
```

Both commands should return empty output. This is the power of Deployment Manager:
`deployments delete` cleans up everything declared in the config, with no need to
individually delete each resource.

> **ACE exam tip:** Deployment Manager stores the state of your deployment in GCP itself
> — there is no external state file to lose or corrupt (unlike Terraform's `.tfstate`).
> If you create a resource manually (outside Deployment Manager) and then try to import
> it into a deployment, you must use `--create-policy=acquire`. If you delete a resource
> outside Deployment Manager and then run `deployments update`, DM will try to recreate
> it. Always use Deployment Manager (or Terraform) as the single source of truth for
> resources it manages — never mix manual and declarative changes.

---

## Key Takeaways

- **Cloud Build** is GCP's managed CI service. Each build is a sequence of steps defined
  in `cloudbuild.yaml`. Each step runs in a Docker container. Steps can run in parallel
  using `waitFor`.

- **The Cloud Build service account** (`PROJECT_NUMBER@cloudbuild.gserviceaccount.com`)
  must have IAM roles for every action the build performs: pushing images, deploying to
  Cloud Run, reading secrets, etc. Missing roles are the most common cause of build failures.

- **Cloud Build substitutions** let you parameterise `cloudbuild.yaml`. Built-in variables
  like `$PROJECT_ID`, `$SHORT_SHA`, and `$BRANCH_NAME` are always available. User-defined
  substitutions start with `_` and must be uppercase. Pass them with
  `--substitutions=_VAR=value` or configure them in a trigger.

- **Artifact Registry** is the modern replacement for Container Registry (GCR). It supports
  Docker, Maven, npm, Python, Go, Apt, and Yum formats. Its hostname pattern is
  `REGION-docker.pkg.dev/PROJECT_ID/REPO`. Per-repository IAM and vulnerability scanning
  are key advantages over GCR.

- **Cloud Deploy** manages promotion through ordered environments (dev → staging → prod).
  A release is a snapshot of artefacts; promotions can require manual approval. For single-
  environment deployments, Cloud Build deploying directly to Cloud Run is simpler.

- **Cloud Scheduler** is managed cron. Jobs target HTTP endpoints, Pub/Sub topics, or
  App Engine handlers. At-least-once delivery — design handlers to be idempotent.

- **Cloud Deployment Manager** is GCP's native IaC tool. It uses YAML + Jinja2/Python,
  manages state in GCP itself (no state file), and deploys/updates/deletes resources as
  a unit called a **deployment**. It is tested on the ACE exam; Terraform is not.

- **Pub/Sub** decouples producers from consumers. Topics fan out messages to all
  subscriptions. Pull subscriptions let consumers control pace; push subscriptions deliver
  HTTP POST to a URL. At-least-once delivery — messages may arrive more than once.

- **Eventarc** routes events from GCP services to Cloud Run and Cloud Functions using
  CloudEvents format. Cloud Functions Gen 2 uses Eventarc for all non-HTTP triggers.

- **gcloud scripting patterns:** use `--format=value()` to extract single values,
  `--filter` to narrow lists, `set -euo pipefail` to fail fast, and `trap cleanup EXIT`
  to ensure resource cleanup runs even when the script fails.

- A **Cloud Build trigger** fires automatically on git events (branch push, tag push,
  pull request) or programmatically via Pub/Sub and webhooks. Triggers store no credentials
  — they rely on the Cloud Build service account's IAM roles.

---

## Cleanup

Run all of these commands to destroy every resource created in this lab. Delete in the
order shown to avoid dependency errors.

```bash
# Check what exists before cleanup
../status.sh 12
```

```bash
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
  --format="value(projectNumber)")
REGION="us-central1"
CB_SA="${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com"

echo "=== Deleting Cloud Run service ==="
gcloud run services delete lab12-app \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud Scheduler job ==="
gcloud scheduler jobs delete lab12-health-ping \
  --location="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud Build trigger ==="
TRIGGER_ID=$(gcloud builds triggers list \
  --region="${REGION}" \
  --filter="name=lab12-push-to-main" \
  --format="value(id)" \
  --project="${PROJECT_ID}")

if [ -n "${TRIGGER_ID}" ]; then
  gcloud builds triggers delete "${TRIGGER_ID}" \
    --region="${REGION}" \
    --quiet \
    --project="${PROJECT_ID}"
  echo "Trigger deleted."
else
  echo "Trigger not found — skipping."
fi

echo "=== Deleting Cloud Source Repository ==="
gcloud source repos delete lab12-source \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null \
  || echo "Repository not found — skipping."

echo "=== Deleting Artifact Registry repository ==="
gcloud artifacts repositories delete lab12-repo \
  --location="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud Deployment Manager deployment (if still present) ==="
gcloud deployment-manager deployments delete lab12-dm-deploy \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null \
  || echo "Deployment not found — already deleted in exercise 9."

echo "=== Removing IAM bindings for Cloud Build service account ==="
for role in roles/artifactregistry.writer roles/run.developer roles/iam.serviceAccountUser; do
  gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${CB_SA}" \
    --role="${role}" \
    --quiet 2>/dev/null \
    || echo "  Binding ${role} not found — skipping."
done

echo "=== Cleaning up local temp directories ==="
rm -rf /tmp/lab12-source-repo \
       /tmp/lab12-dm-updated.yaml

echo "=== Cleanup complete ==="
```

Verify everything is gone:

```bash
../status.sh 12
```

All sections should be empty.

> **Note on Cloud Build logs:** Cloud Build automatically creates a Cloud Storage bucket
> named `PROJECT_ID_cloudbuild` to store build logs. This bucket accumulates log files
> over time. The files are small (kilobytes each), so the cost is negligible, but if you
> want to delete them completely:
> ```bash
> gcloud storage rm -r "gs://${PROJECT_ID}_cloudbuild" --quiet 2>/dev/null \
>   || echo "Build logs bucket not found."
> ```
> This is optional — the bucket does not incur meaningful cost.

> **Note on Cloud Source Repositories:** The `lab12-source` repository was deleted above,
> but Cloud Source Repositories does not delete the underlying Git objects immediately.
> If you re-create a repository with the same name in the same project, git history is
> not recovered — the new repository starts empty.

---

## Quiz

Test your understanding of the concepts covered in this lab with five ACE-style questions:

```bash
./quiz.sh
```
