# GCP Associate Cloud Engineer Practice Test — Questions

**Time allowed:** 120 minutes
**Total points:** 120
**Pass mark:** 84 (70%)
**Distinction:** 102 (85%)

Start the timer only after the setup script has completed and you have sourced
`setup/setup-outputs.env`.

Set these environment variables at the start — every command in this test uses them:

```bash
source gcp-ace-labs/practice-test/setup/setup-outputs.env
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"
```

---

## Question 1 — Project Setup, Billing, and APIs (7 points) — Domain 1

**Scenario:** A colleague has handed you a freshly created GCP project. Before any
workload can be deployed you need to verify billing is linked, enable the required
service APIs, and confirm your gcloud CLI is configured correctly.

**Tasks:**

1. Confirm that a billing account is linked to your project and capture its ID.
2. Enable the Cloud Run, GKE, and Secret Manager APIs in a single `gcloud` command.
3. Set your project as the default and configure the default region to `us-central1`
   and default zone to `us-central1-a` using `gcloud config set`.
4. Confirm all three APIs are now enabled by listing enabled services filtered to
   the three you just enabled.

**Success criteria:** All three APIs appear in the enabled services list; billing is
confirmed active; gcloud config shows your project, region, and zone.

**Verification:**

```bash
# Check billing
gcloud billing projects describe "${PROJECT_ID}" \
  --format="value(billingAccountName,billingEnabled)"
```

Expected output:
```
billingAccounts/XXXXXX-XXXXXX-XXXXXX  True
```

```bash
# Confirm APIs are enabled
gcloud services list --enabled \
  --filter="name:(run.googleapis.com OR container.googleapis.com OR secretmanager.googleapis.com)" \
  --format="table(name,state)"
```

Expected output:
```
NAME                         STATE
container.googleapis.com     ENABLED
run.googleapis.com           ENABLED
secretmanager.googleapis.com ENABLED
```

```bash
# Confirm gcloud config
gcloud config list --format="table(core.project,compute.region,compute.zone)"
```

Expected output:
```
PROJECT           REGION       ZONE
your-project-id   us-central1  us-central1-a
```

---

## Question 2 — Compute Engine: Startup Script and Firewall (7 points) — Domain 3

**Scenario:** You need to deploy a web server VM that installs nginx via startup script,
and make it reachable on port 80 from the internet. The instance must use an e2-micro
machine type (free tier eligible) and must be tagged so the firewall rule applies only
to it.

**Tasks:**

1. Create a firewall rule named `allow-http-ace` that allows TCP port 80 ingress from
   `0.0.0.0/0` to instances with the network tag `http-server`.
2. Create a Compute Engine instance named `ace-web-01` in zone `us-central1-a` with:
   - Machine type: `e2-micro`
   - Image family: `debian-12` (project: `debian-cloud`)
   - Network tag: `http-server`
   - Startup script that runs: `apt-get update && apt-get install -y nginx`
3. Wait for the instance to finish booting (hint: use `gcloud compute ssh` or poll the
   serial port output), then verify nginx is serving HTTP traffic.

**Success criteria:** Curling the external IP on port 80 returns the nginx default page.

**Verification:**

```bash
# Get the external IP
EXTERNAL_IP=$(gcloud compute instances describe ace-web-01 \
  --zone="${ZONE}" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
echo "External IP: ${EXTERNAL_IP}"

# Test HTTP (wait 60-90s after create for startup script to complete)
curl -s --max-time 10 "http://${EXTERNAL_IP}" | grep -o "Welcome to nginx"
```

Expected output:
```
Welcome to nginx
```

```bash
# Confirm the firewall rule exists
gcloud compute firewall-rules describe allow-http-ace \
  --format="table(name,direction,allowed[].map().firewall_rule(),targetTags.list())"
```

Expected output:
```
NAME            DIRECTION  ALLOW   TARGET_TAGS
allow-http-ace  INGRESS    tcp:80  http-server
```

---

## Question 3 — Cloud Storage: Lifecycle Rules and Versioning (7 points) — Domain 3

**Scenario:** Your team stores build artifacts in Cloud Storage. Objects older than 30
days should be downgraded to Nearline storage to reduce cost, and objects older than 90
days should be deleted. The bucket must also have versioning enabled so accidental
deletions can be recovered.

A bucket named `ace-practice-import-${PROJECT_ID}` was pre-created by the setup script.

**Tasks:**

1. Enable versioning on the pre-created bucket.
2. Write a lifecycle configuration JSON file that:
   - Transitions objects to `NEARLINE` storage after 30 days
   - Deletes objects after 90 days (applies to current and non-current versions)
3. Apply the lifecycle rules to the bucket.
4. Upload a test object to the bucket to confirm it accepts writes.

**Success criteria:** Versioning is enabled; lifecycle rules are applied; a test object
is uploadable.

**Verification:**

```bash
BUCKET="ace-practice-import-${PROJECT_ID}"

# Check versioning
gcloud storage buckets describe "gs://${BUCKET}" \
  --format="value(versioning.enabled)"
```

Expected output:
```
True
```

```bash
# Check lifecycle rules
gcloud storage buckets describe "gs://${BUCKET}" \
  --format="json(lifecycle)"
```

Expected output (abridged — confirm both rules are present):
```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {"storageClass": "NEARLINE", "type": "SetStorageClass"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}
      }
    ]
  }
}
```

```bash
# Confirm test object uploaded
gcloud storage ls "gs://${BUCKET}/"
```

Expected output: at least one object listed.

---

## Question 4 — IAM Role Binding and Service Account (7 points) — Domain 5

**Scenario:** A background job needs to read objects from Cloud Storage without any
human credentials. Security policy requires using a dedicated service account with
only the minimum permissions needed, not a user account or the default compute service
account.

A service account named `ace-practice-sa` was pre-created by setup.

**Tasks:**

1. Grant the service account `roles/storage.objectViewer` on your project.
2. Create a new service account named `ace-app-sa` with display name `ACE App SA`.
3. Grant `ace-app-sa` the role `roles/run.invoker` on your project.
4. Verify the IAM policy shows both bindings by filtering the project's IAM policy.
5. Generate a service account key JSON file for `ace-practice-sa` and save it to
   `/tmp/ace-practice-sa-key.json` — then immediately identify why this approach is
   discouraged and what the preferred alternative is for GCE/GKE workloads.

**Success criteria:** Both role bindings appear in the project IAM policy; a key file
is generated (even though the secure alternative is Workload Identity / attached SA).

**Verification:**

```bash
# Check objectViewer binding for ace-practice-sa
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.role=roles/storage.objectViewer AND bindings.members:ace-practice-sa" \
  --format="table(bindings.role,bindings.members)"
```

Expected output:
```
ROLE                        MEMBERS
roles/storage.objectViewer  serviceAccount:ace-practice-sa@PROJECT_ID.iam.gserviceaccount.com
```

```bash
# Check run.invoker binding for ace-app-sa
gcloud projects get-iam-policy "${PROJECT_ID}" \
  --flatten="bindings[].members" \
  --filter="bindings.role=roles/run.invoker AND bindings.members:ace-app-sa" \
  --format="table(bindings.role,bindings.members)"
```

Expected output:
```
ROLE               MEMBERS
roles/run.invoker  serviceAccount:ace-app-sa@PROJECT_ID.iam.gserviceaccount.com
```

```bash
# Confirm key file created
ls -lh /tmp/ace-practice-sa-key.json
```

Expected output: a file around 2–3 KB (the JSON private key).

> **Why key files are discouraged:** JSON key files are long-lived credentials that can
> be leaked, are not automatically rotated, and require manual distribution. On GCE and
> GKE, attaching a service account to the instance or using Workload Identity lets
> workloads obtain short-lived tokens automatically with zero key management.

---

## Question 5 — VPC with Firewall Rules and Cloud NAT (9 points) — Domain 2+3

**Scenario:** You need to deploy a private VM that can reach the internet to download
packages (egress), but must not be reachable directly from the internet (no external IP).
The VPC network `ace-practice-vpc` and subnet `ace-practice-subnet` (10.10.0.0/24) were
pre-created by setup, along with a Cloud NAT router named `ace-practice-router`.

**Tasks:**

1. Create a Cloud NAT configuration named `ace-practice-nat` on the pre-created router
   `ace-practice-router` that covers all subnet IP ranges automatically.
2. Create a firewall rule named `allow-internal-ace` that allows all TCP/UDP/ICMP
   traffic between instances within the `10.10.0.0/24` range (source range).
3. Create a firewall rule named `deny-all-ingress-ace` with priority 65500 that
   explicitly denies all ingress traffic (this tests that your NAT egress still works
   even without an allow-ingress rule for the VM itself).
4. Create a VM named `ace-private-vm` in zone `us-central1-a` with **no external IP**
   (`--no-address`), on the `ace-practice-vpc` network / `ace-practice-subnet` subnet,
   with a startup script that runs `curl -s https://example.com -o /tmp/test.html`.
5. Confirm the startup script succeeded by checking the serial port output or by SSHing
   through IAP and checking `/tmp/test.html`.

**Success criteria:** The VM has no external IP; the startup script downloads content
via NAT (confirming egress works); direct ingress from internet is blocked.

**Verification:**

```bash
# Confirm VM has no external IP
gcloud compute instances describe ace-private-vm \
  --zone="${ZONE}" \
  --format="value(networkInterfaces[0].accessConfigs)"
```

Expected output:
```
[]
```
(empty — no access config means no external IP)

```bash
# Confirm NAT config exists
gcloud compute routers nats describe ace-practice-nat \
  --router=ace-practice-router \
  --region="${REGION}" \
  --format="value(name,sourceSubnetworkIpRangesToNat)"
```

Expected output:
```
ace-practice-nat  ALL_SUBNETWORKS_ALL_IP_RANGES
```

```bash
# SSH via IAP and check the downloaded file (IAP tunnels through Google's infra)
gcloud compute ssh ace-private-vm \
  --zone="${ZONE}" \
  --tunnel-through-iap \
  --command="grep -o '<title>.*</title>' /tmp/test.html"
```

Expected output:
```
<title>Example Domain</title>
```

---

## Question 6 — Cloud Run: Deployment and Traffic Splitting (9 points) — Domain 3

**Scenario:** You are deploying a containerised web application to Cloud Run. The new
version has already been tested in dev. You need to deploy it, then perform a canary
release by directing 20% of traffic to the new revision while 80% stays on the stable
revision — all without any downtime.

**Tasks:**

1. Deploy a Cloud Run service named `ace-hello` in region `us-central1` using the
   public container image `us-docker.pkg.dev/cloudrun/container/hello` with:
   - `--allow-unauthenticated` (public access)
   - `--no-traffic` flag so the new revision receives no traffic yet
   - Tag the revision as `stable`
2. Deploy a second revision of the same service using the same image but with an
   environment variable `VERSION=v2` set. Tag this revision as `canary`. Use
   `--no-traffic` again.
3. Split traffic so that `stable` receives 80% and `canary` receives 20%.
4. Confirm the traffic split is active.

**Success criteria:** Two revisions exist; traffic is split 80/20 between stable and
canary as reported by `gcloud run services describe`.

**Verification:**

```bash
# List revisions
gcloud run revisions list \
  --service=ace-hello \
  --region="${REGION}" \
  --format="table(name,status.conditions[0].status,metadata.annotations['serving.knative.dev/tags'])"
```

Expected output (revision names will differ):
```
NAME              READY  TAGS
ace-hello-XXXXX   True   canary
ace-hello-YYYYY   True   stable
```

```bash
# Check traffic split
gcloud run services describe ace-hello \
  --region="${REGION}" \
  --format="value(status.traffic)"
```

Expected output (order may vary):
```
[{'percent': 80, 'tag': 'stable', ...}, {'percent': 20, 'tag': 'canary', ...}]
```

```bash
# Confirm service URL responds
SERVICE_URL=$(gcloud run services describe ace-hello \
  --region="${REGION}" \
  --format="value(status.url)")
curl -s --max-time 10 "${SERVICE_URL}" | grep -o "Hello World"
```

Expected output:
```
Hello World
```

---

## Question 7 — GKE: Deploy App with ConfigMap and HPA (9 points) — Domain 3

**Scenario:** Your team runs a Kubernetes-based microservice on GKE. You need to deploy
an Autopilot cluster, configure application settings through a ConfigMap (not baked into
the image), deploy the application as a Deployment, expose it internally, and enable
Horizontal Pod Autoscaling so it scales automatically under load.

**Tasks:**

1. Create a GKE Autopilot cluster named `ace-practice-cluster` in region `us-central1`.
   (This takes 5–8 minutes — start it first and work on other questions while it provisions.)
2. Get credentials for the cluster.
3. Create a namespace named `ace-app`.
4. Create a ConfigMap named `ace-app-config` in the `ace-app` namespace with the
   key-value pair `APP_ENV=production` and `LOG_LEVEL=info`.
5. Deploy a Deployment named `ace-app` in the `ace-app` namespace using the image
   `nginx:stable` with 2 replicas. Mount the ConfigMap values as environment variables
   in the container.
6. Expose the Deployment as a ClusterIP Service named `ace-app-svc` on port 80.
7. Create a HorizontalPodAutoscaler named `ace-app-hpa` targeting `ace-app` with
   min replicas 2, max replicas 6, and a CPU utilisation target of 50%.

**Success criteria:** All pods running; ConfigMap values injected; HPA created and
reporting current/desired replicas.

**Verification:**

```bash
gcloud container clusters get-credentials ace-practice-cluster \
  --region="${REGION}"

# Check pods
kubectl get pods -n ace-app -l app=ace-app
```

Expected output:
```
NAME                       READY   STATUS    RESTARTS   AGE
ace-app-XXXXXXXXX-XXXXX    1/1     Running   0          Xm
ace-app-XXXXXXXXX-XXXXX    1/1     Running   0          Xm
```

```bash
# Check ConfigMap values are injected
kubectl exec -n ace-app \
  $(kubectl get pod -n ace-app -l app=ace-app -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep -E "APP_ENV|LOG_LEVEL"
```

Expected output:
```
APP_ENV=production
LOG_LEVEL=info
```

```bash
# Check HPA
kubectl get hpa ace-app-hpa -n ace-app
```

Expected output:
```
NAME          REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS
ace-app-hpa   Deployment/ace-app   0%/50%    2         6         2
```

---

## Question 8 — Cloud SQL: Auth Proxy and Automated Backups (9 points) — Domain 3+4

**Scenario:** You are setting up a managed PostgreSQL database for an application.
The database must not be reachable over the public internet. The application will
connect using the Cloud SQL Auth Proxy, which handles authentication and encryption
transparently. Automated backups must be enabled.

**Tasks:**

1. Create a Cloud SQL PostgreSQL instance named `ace-practice-db` with:
   - Database version: `POSTGRES_15`
   - Tier: `db-f1-micro`
   - Region: `us-central1`
   - No authorised networks (private access only)
   - Automated daily backups enabled with start time `02:00`
2. Create a database named `ace_app` inside the instance.
3. Create a database user named `ace_user` with a secure password.
4. Download and install the Cloud SQL Auth Proxy binary, then start it listening on
   `localhost:5432` for the `ace-practice-db` instance using your Application Default
   Credentials.
5. Connect to the database through the proxy using `psql` (or confirm the proxy is
   listening with `nc -z localhost 5432`) and list the databases.

> **Cost note:** Cloud SQL db-f1-micro bills ~$0.017/hr. Destroy it promptly after
> verification.

**Success criteria:** Instance is RUNNABLE; backup is configured; proxy connects and
the `ace_app` database is visible.

**Verification:**

```bash
# Check instance status and backup config
gcloud sql instances describe ace-practice-db \
  --format="table(name,state,settings.backupConfiguration.enabled,settings.backupConfiguration.startTime)"
```

Expected output:
```
NAME              STATE     ENABLED  START_TIME
ace-practice-db   RUNNABLE  True     02:00
```

```bash
# Check the database exists
gcloud sql databases list --instance=ace-practice-db \
  --format="table(name)"
```

Expected output (includes built-in postgres databases):
```
NAME
ace_app
postgres
```

```bash
# Check the user exists
gcloud sql users list --instance=ace-practice-db \
  --format="table(name)"
```

Expected output (includes default postgres user):
```
NAME
ace_user
postgres
```

```bash
# Confirm proxy is listening (run after starting the proxy in another terminal)
nc -z localhost 5432 && echo "proxy is listening"
```

Expected output:
```
proxy is listening
```

---

## Question 9 — Cloud Monitoring: Alerting Policy and Notification Channel (9 points) — Domain 4

**Scenario:** Your SRE team requires an alerting policy that fires whenever a Compute
Engine instance's CPU utilisation exceeds 80% for more than 5 minutes. Alerts must be
delivered to an email address so the on-call engineer is notified.

**Tasks:**

1. Create an email notification channel for the address `oncall@example.com`.
2. Create an alerting policy named `ace-cpu-alert` that:
   - Monitors the metric `compute.googleapis.com/instance/cpu/utilization`
   - Fires when CPU utilisation is above `0.80` for a 5-minute window (300 seconds)
   - Is scoped to your project
   - Uses the notification channel created in step 1
3. Confirm the policy is enabled and the notification channel is attached.

**Success criteria:** The alerting policy exists in ENABLED state with the correct
threshold and notification channel; the notification channel is VERIFIED.

**Verification:**

```bash
# List alerting policies
gcloud alpha monitoring policies list \
  --filter="displayName='ace-cpu-alert'" \
  --format="table(displayName,enabled,conditions[0].conditionThreshold.thresholdValue)"
```

Expected output:
```
DISPLAY_NAME   ENABLED  THRESHOLD_VALUE
ace-cpu-alert  True     0.8
```

```bash
# List notification channels
gcloud alpha monitoring channels list \
  --filter="displayName='oncall-email'" \
  --format="table(displayName,type,labels.email_address,verificationStatus)"
```

Expected output:
```
DISPLAY_NAME   TYPE   EMAIL_ADDRESS          VERIFICATION_STATUS
oncall-email   email  oncall@example.com     UNVERIFIED
```

> **Note:** Email channels start as UNVERIFIED until the recipient clicks a confirmation
> link. UNVERIFIED channels still receive alerts — verification only confirms delivery
> is to the intended address.

```bash
# Describe the full policy (confirm threshold and duration)
POLICY_NAME=$(gcloud alpha monitoring policies list \
  --filter="displayName='ace-cpu-alert'" \
  --format="value(name)")
gcloud alpha monitoring policies describe "${POLICY_NAME}" \
  --format="yaml(conditions[0].conditionThreshold)"
```

Expected output:
```yaml
conditionThreshold:
  comparison: COMPARISON_GT
  duration: 300s
  filter: resource.type="gce_instance" AND metric.type="compute.googleapis.com/instance/cpu/utilization"
  thresholdValue: 0.8
```

---

## Question 10 — Log Sink to BigQuery and Log-Based Metric (8 points) — Domain 4

**Scenario:** Your compliance team requires that all HTTP 5xx errors from Cloud Run
services are exported to BigQuery for long-term retention and ad-hoc analysis. They
also want a real-time count metric so that dashboards and alerts can use it.

A BigQuery dataset named `ace_practice_logs` was pre-created by setup.

**Tasks:**

1. Create a log sink named `ace-bq-sink` that routes all Cloud Run request logs to the
   pre-created BigQuery dataset `ace_practice_logs`. Use the log filter:
   ```
   resource.type="cloud_run_revision" AND httpRequest.status>=500
   ```
2. Grant the sink's service account the `roles/bigquery.dataEditor` role on the
   BigQuery dataset (Cloud Logging creates a writer service account for the sink that
   needs permission to insert rows).
3. Create a log-based metric named `ace_5xx_count` that counts the same log entries
   (same filter) with metric type `counter`.
4. Confirm the sink and metric both exist.

**Success criteria:** Log sink exists pointing at the BigQuery dataset; sink service
account has dataEditor on the dataset; log-based metric exists.

**Verification:**

```bash
# Check sink
gcloud logging sinks describe ace-bq-sink \
  --format="table(name,destination,filter)"
```

Expected output:
```
NAME         DESTINATION                                                           FILTER
ace-bq-sink  bigquery.googleapis.com/projects/PROJECT_ID/datasets/ace_practice_logs  resource.type="cloud_run_revision"...
```

```bash
# Capture sink writer identity
WRITER_IDENTITY=$(gcloud logging sinks describe ace-bq-sink \
  --format="value(writerIdentity)")
echo "Sink writer: ${WRITER_IDENTITY}"
```

Expected output:
```
Sink writer: serviceAccount:pXXXXXXXXX-XXXXXX@gcp-sa-logging.iam.gserviceaccount.com
```

```bash
# Check log-based metric
gcloud logging metrics describe ace_5xx_count \
  --format="table(name,filter,metricDescriptor.metricKind)"
```

Expected output:
```
NAME           FILTER                                             METRIC_KIND
ace_5xx_count  resource.type="cloud_run_revision" AND ...        DELTA
```

---

## Question 11 — Cloud KMS Encrypt/Decrypt and Secret Manager (8 points) — Domain 5

**Scenario:** A database password must be stored securely using two complementary
approaches: Cloud KMS for envelope encryption of files, and Secret Manager for
application-level secret retrieval. Understanding both is required for the ACE exam —
KMS protects data at rest (CMEK), while Secret Manager is the right tool for app
credentials.

A KMS key ring named `ace-practice-keyring` with a key named `ace-practice-key` was
pre-created by setup.

**Tasks:**

1. Use the pre-created KMS key to encrypt the plaintext string `s3cr3t-db-password`
   (write it to a file, then encrypt that file). Save the ciphertext to
   `/tmp/encrypted.enc`.
2. Decrypt `/tmp/encrypted.enc` back to plaintext and confirm it matches the original.
3. Create a Secret Manager secret named `ace-db-password` and add the value
   `s3cr3t-db-password` as its first version.
4. Access the secret value using `gcloud secrets versions access` and confirm it returns
   the correct plaintext.
5. Disable version 1 of the secret (this simulates secret rotation — the old version
   is kept for audit but cannot be accessed).

**Success criteria:** KMS encrypt/decrypt round-trip succeeds; Secret Manager secret
exists with a DISABLED version 1.

**Verification:**

```bash
# Confirm decrypt works
gcloud kms decrypt \
  --keyring=ace-practice-keyring \
  --key=ace-practice-key \
  --location=us-central1 \
  --ciphertext-file=/tmp/encrypted.enc \
  --plaintext-file=/tmp/decrypted.txt
cat /tmp/decrypted.txt
```

Expected output:
```
s3cr3t-db-password
```

```bash
# Check secret exists
gcloud secrets describe ace-db-password \
  --format="table(name,replication.automatic)"
```

Expected output:
```
NAME                                              AUTOMATIC
projects/PROJECT_ID/secrets/ace-db-password       {}
```

```bash
# Check version state
gcloud secrets versions list ace-db-password \
  --format="table(name,state)"
```

Expected output:
```
NAME                                                         STATE
projects/PROJECT_ID/secrets/ace-db-password/versions/1      DISABLED
```

---

## Question 12 — Managed Instance Group with Autoscaling and HTTP(S) Load Balancer (8 points) — Domain 3

**Scenario:** You need to deploy a horizontally scalable web tier using a regional
Managed Instance Group behind a global HTTP(S) load balancer. The MIG must autoscale
based on CPU usage and the load balancer must perform health checks before sending
traffic to instances.

**Tasks:**

1. Create an instance template named `ace-web-template` with:
   - Machine type: `e2-micro`
   - Image family: `debian-12` (project: `debian-cloud`)
   - Network tag: `http-server`
   - Startup script: `apt-get update -y && apt-get install -y nginx && systemctl start nginx`
2. Create a regional MIG named `ace-web-mig` in region `us-central1` using the template,
   with initial size 2.
3. Configure autoscaling on the MIG: min 2 replicas, max 5 replicas, target CPU 60%.
4. Create an HTTP health check named `ace-http-hc` checking path `/` on port 80.
5. Create a backend service named `ace-backend-svc` (global, HTTP protocol) and attach
   the MIG as a backend with the health check.
6. Create a URL map named `ace-url-map`, a target HTTP proxy named `ace-http-proxy`, and
   a global forwarding rule named `ace-http-rule` on port 80.
7. Wait for the load balancer to provision (2–5 minutes), then curl its IP and confirm
   nginx responds.

**Success criteria:** MIG has 2 healthy instances; LB forwarding rule has an external IP;
curling the LB IP returns an nginx response.

**Verification:**

```bash
# Check MIG size and health
gcloud compute instance-groups managed describe ace-web-mig \
  --region="${REGION}" \
  --format="table(name,status.statefulPolicy,targetSize,autoscaler)"
```

Expected output (abridged):
```
NAME          TARGET_SIZE
ace-web-mig   2
```

```bash
# Check autoscaling policy
gcloud compute instance-groups managed describe ace-web-mig \
  --region="${REGION}" \
  --format="value(autoscaler)"
# Then:
gcloud compute autoscalers describe ace-web-mig \
  --region="${REGION}" \
  --format="table(name,autoscalingPolicy.minNumReplicas,autoscalingPolicy.maxNumReplicas,autoscalingPolicy.cpuUtilization.utilizationTarget)"
```

Expected output:
```
NAME          MIN  MAX  CPU_TARGET
ace-web-mig   2    5    0.6
```

```bash
# Get LB IP and test
LB_IP=$(gcloud compute forwarding-rules describe ace-http-rule \
  --global \
  --format="value(IPAddress)")
echo "LB IP: ${LB_IP}"

# Wait up to 5 minutes for health checks to pass, then:
curl -s --max-time 10 "http://${LB_IP}" | grep -o "Welcome to nginx"
```

Expected output:
```
Welcome to nginx
```

---

## Question 13 — Cloud Build Pipeline and Artifact Registry (8 points) — Domain 3

**Scenario:** Your team needs a CI/CD pipeline that automatically builds a Docker image
and pushes it to Artifact Registry whenever code is pushed to a repository. You will
simulate the pipeline by writing a `cloudbuild.yaml`, submitting a manual build, and
confirming the image lands in the registry.

An Artifact Registry repository named `ace-practice-repo` (format: Docker, region:
`us-central1`) was pre-created by setup.

**Tasks:**

1. Create a working directory `/tmp/ace-build-demo/` and write a minimal `Dockerfile`
   that uses `FROM nginx:alpine` and copies a custom `index.html` with the content
   `ACE Practice Build`.
2. Write a `cloudbuild.yaml` in the same directory with two steps:
   - Step 1 (`name: gcr.io/cloud-builders/docker`): build the image and tag it as
     `us-central1-docker.pkg.dev/${PROJECT_ID}/ace-practice-repo/ace-app:$BUILD_ID`
   - Step 2: push the tagged image to Artifact Registry
   - Set `images` at the top level to reference the same tagged image so Cloud Build
     records it.
3. Submit the build using `gcloud builds submit`.
4. Confirm the image appears in Artifact Registry after the build completes.

**Success criteria:** The Cloud Build run completes with SUCCESS status; the image
appears in `ace-practice-repo`.

**Verification:**

```bash
# Check most recent build status
gcloud builds list --limit=1 \
  --format="table(id,status,createTime,duration)"
```

Expected output:
```
ID                                    STATUS   CREATE_TIME          DURATION
XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX  SUCCESS  YYYY-MM-DDTHH:MM:SS  Xs
```

```bash
# Check image in Artifact Registry
gcloud artifacts docker images list \
  "us-central1-docker.pkg.dev/${PROJECT_ID}/ace-practice-repo" \
  --format="table(package,version,tags,createTime)"
```

Expected output:
```
PACKAGE                                                          VERSION  TAGS       CREATE_TIME
us-central1-docker.pkg.dev/PROJECT_ID/ace-practice-repo/ace-app  sha256:  BUILD_ID   YYYY-MM-DD
```

---

## Question 14 — Multi-Service: GKE + Cloud SQL + Workload Identity (6 points) — Domain 3+5

**Scenario:** A production application runs on GKE and needs to read from a Cloud SQL
PostgreSQL database. Rather than mounting a service account JSON key into the pod (a
security anti-pattern), you must use **Workload Identity** so the Kubernetes service
account is mapped to a GCP service account and can authenticate to Cloud SQL without any
key files.

This question builds on Q7 (GKE cluster) and Q8 (Cloud SQL instance). Both must be
complete before starting this question.

**Tasks:**

1. Enable Workload Identity on the `ace-practice-cluster` cluster (if not already
   enabled — Autopilot clusters have it enabled by default).
2. Create a GCP service account named `ace-wi-sa` and grant it `roles/cloudsql.client`
   on the project.
3. Create a Kubernetes namespace named `ace-wi-demo` and a Kubernetes service account
   named `ace-wi-ksa` in that namespace.
4. Bind the Kubernetes service account to the GCP service account using the Workload
   Identity annotation:
   - Add the annotation `iam.gke.io/gcp-service-account=ace-wi-sa@PROJECT_ID.iam.gserviceaccount.com`
     to the Kubernetes service account.
   - Grant the `roles/iam.workloadIdentityUser` role to the Kubernetes service account
     on the GCP service account (`--member="serviceAccount:PROJECT_ID.svc.id.goog[ace-wi-demo/ace-wi-ksa]"`).
5. Deploy a test pod in the `ace-wi-demo` namespace that uses `ace-wi-ksa` as its
   service account and runs `gcloud auth list` to confirm it is authenticating as
   `ace-wi-sa`.

**Success criteria:** The test pod authenticates as the GCP service account without any
key file mounted; `gcloud auth list` inside the pod shows `ace-wi-sa` as the active account.

**Verification:**

```bash
# Check Workload Identity annotation on the KSA
kubectl get serviceaccount ace-wi-ksa -n ace-wi-demo \
  -o jsonpath='{.metadata.annotations.iam\.gke\.io/gcp-service-account}'
```

Expected output:
```
ace-wi-sa@PROJECT_ID.iam.gserviceaccount.com
```

```bash
# Check IAM binding on GCP SA
gcloud iam service-accounts get-iam-policy \
  "ace-wi-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --format="table(bindings[].role,bindings[].members)"
```

Expected output (includes the workloadIdentityUser binding):
```
ROLE                          MEMBERS
roles/iam.workloadIdentityUser  serviceAccount:PROJECT_ID.svc.id.goog[ace-wi-demo/ace-wi-ksa]
```

```bash
# Check test pod auth (pod must be running)
kubectl exec -n ace-wi-demo \
  $(kubectl get pod -n ace-wi-demo -l app=ace-wi-test -o jsonpath='{.items[0].metadata.name}') \
  -- gcloud auth list 2>&1 | grep "ACTIVE"
```

Expected output:
```
*  ace-wi-sa@PROJECT_ID.iam.gserviceaccount.com  ACTIVE
```

---

## Question 15 — Multi-Service: Cloud Run + Secret Manager + Cloud Armor (6 points) — Domain 3+5

**Scenario:** You are hardening a public-facing Cloud Run service. Application secrets
must never be in environment variables or the container image — they must be mounted from
Secret Manager. Additionally, a Cloud Armor security policy must restrict access to known
safe IP ranges and block requests with SQL injection patterns (OWASP rule set).

This question builds on Q6 (Cloud Run) and Q11 (Secret Manager).

**Tasks:**

1. Create a new Cloud Run service named `ace-secure-svc` in `us-central1` using the
   image `us-docker.pkg.dev/cloudrun/container/hello`. Configure it to:
   - Run as the `ace-app-sa` service account created in Q4
   - Mount the `ace-db-password` secret (created in Q11, version `latest`) as the
     environment variable `DB_PASSWORD` using the `--set-secrets` flag
   - Allow unauthenticated access
2. Verify the service is running and the secret is accessible inside the container
   (use the Cloud Run logs or exec into a revision to confirm `DB_PASSWORD` is set —
   note: Cloud Run does not support exec; check via a small test container or the
   logs from a startup probe).
3. Create a Cloud Armor security policy named `ace-armor-policy` that:
   - Has a default rule that **denies** all traffic (priority 2147483647, action `deny-403`)
   - Adds a rule (priority 1000) that allows traffic from your own IP address
     (`$(curl -s ifconfig.me)/32`)
   - Adds a rule (priority 900) using the pre-configured rule `evaluatePreconfiguredExpr('sqli-v33-stable')`
     to block SQL injection attempts (action `deny-403`)
4. Note: Cloud Armor policies attach to backend services on HTTP(S) Load Balancers, not
   directly to Cloud Run. Document the command you would use to attach `ace-armor-policy`
   to the `ace-backend-svc` backend service from Q12.

**Success criteria:** Cloud Run service runs with secret mounted; Cloud Armor policy
exists with the three rules; attachment command is documented.

**Verification:**

```bash
# Check Cloud Run service is running with secret mounted
gcloud run services describe ace-secure-svc \
  --region="${REGION}" \
  --format="value(spec.template.spec.containers[0].env)"
```

Expected output (contains the secret reference):
```
[{'name': 'DB_PASSWORD', 'valueFrom': {'secretKeyRef': {'key': 'latest', 'name': 'ace-db-password'}}}]
```

```bash
# Check Cloud Armor policy exists with correct rule count
gcloud compute security-policies describe ace-armor-policy \
  --format="table(name,rules[].priority,rules[].action)"
```

Expected output:
```
NAME              PRIORITY  ACTION
ace-armor-policy  900       deny(403)
ace-armor-policy  1000      allow
ace-armor-policy  2147483647  deny(403)
```

```bash
# Document the attachment command (run this to attach to the Q12 backend service)
echo "Attach command:"
echo "gcloud compute backend-services update ace-backend-svc \\"
echo "  --global \\"
echo "  --security-policy=ace-armor-policy"
```

Expected output:
```
Attach command:
gcloud compute backend-services update ace-backend-svc \
  --global \
  --security-policy=ace-armor-policy
```

---

## Scoring Checklist

| # | Question | Domain | Points | Complete? |
|---|----------|--------|--------|-----------|
| 1 | Project setup, billing, APIs | Domain 1 | 7 | [ ] |
| 2 | GCE instance: startup script and firewall | Domain 3 | 7 | [ ] |
| 3 | Cloud Storage: lifecycle rules and versioning | Domain 3 | 7 | [ ] |
| 4 | IAM role binding and service account | Domain 5 | 7 | [ ] |
| 5 | VPC: private VM with Cloud NAT | Domain 2+3 | 9 | [ ] |
| 6 | Cloud Run: deployment and traffic splitting | Domain 3 | 9 | [ ] |
| 7 | GKE: ConfigMap and HPA | Domain 3 | 9 | [ ] |
| 8 | Cloud SQL: Auth Proxy and backups | Domain 3+4 | 9 | [ ] |
| 9 | Cloud Monitoring: alerting policy | Domain 4 | 9 | [ ] |
| 10 | Log sink to BigQuery + log-based metric | Domain 4 | 8 | [ ] |
| 11 | Cloud KMS encrypt/decrypt + Secret Manager | Domain 5 | 8 | [ ] |
| 12 | MIG with autoscaling + HTTP(S) LB | Domain 3 | 8 | [ ] |
| 13 | Cloud Build + Artifact Registry | Domain 3 | 8 | [ ] |
| 14 | GKE + Cloud SQL + Workload Identity | Domain 3+5 | 6 | [ ] |
| 15 | Cloud Run + Secret Manager + Cloud Armor | Domain 3+5 | 6 | [ ] |
| | **Total** | | **120** | |
