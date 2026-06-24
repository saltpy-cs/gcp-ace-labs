# Lab 10 — Operations & Observability

> **Cost warning:** Cloud Monitoring and Logging have generous free tiers.
> - Custom metrics: first 150 MB/project/month free, then $0.01/MB.
> - Log ingestion: first 50 GiB/project/month free, then $0.01/GiB.
> - Uptime checks: first 1 million checks/month free.
> - Log exports to GCS/BigQuery/Pub/Sub: standard storage/egress rates apply.
>
> Estimated for this lab (well within free tiers): **~$0.00**.

---

## Objectives

After completing this lab you will be able to:

- Create custom Cloud Monitoring dashboards and charts for GCE CPU and memory
- Define alerting policies with metric threshold conditions
- Configure email notification channels and attach them to alerting policies
- Write structured Cloud Logging queries using the Logging query language
- Find IAM changes using Cloud Audit Logs
- Create log sinks to export logs to GCS and BigQuery
- Create log-based metrics and build alerts on them
- Set up uptime checks for external HTTP endpoints and alert on failures
- Explain the difference between GAUGE, DELTA, and CUMULATIVE metric types
- Understand Cloud Trace, Error Reporting, and Cloud Profiler (conceptual)

---

## Concepts

### Why Observability Matters

Before you can operate a cloud solution reliably you need three signals — the classic
**observability triad**:

1. **Metrics** — numeric measurements over time (CPU %, request count, error rate). Metrics
   tell you _that_ something is wrong and _how much_.
2. **Logs** — timestamped records of discrete events. Logs tell you _what happened_ and
   in what order.
3. **Traces** — end-to-end records of a request travelling through multiple services.
   Traces tell you _where_ latency lives in a distributed system.

GCP groups its observability tools under **Google Cloud's operations suite** (formerly
Stackdriver). Each tool in the suite maps to one pillar of the triad:

| Tool | Pillar | Primary Use |
|---|---|---|
| Cloud Monitoring | Metrics | Dashboards, alerting, SLOs |
| Cloud Logging | Logs | Querying, sinking, retention |
| Cloud Trace | Traces | Latency analysis, distributed tracing |
| Error Reporting | Logs (aggregated) | Auto-grouping of application exceptions |
| Cloud Profiler | Metrics (application internals) | CPU/memory flame graphs for running code |

On AWS, the equivalents are CloudWatch Metrics, CloudWatch Logs, X-Ray, and AWS Distro
for OpenTelemetry. GCP's suite is more tightly integrated — you do not need to configure
agents or roles to start seeing most infrastructure metrics.

### Cloud Monitoring: Metrics and Time Series

Every metric in Cloud Monitoring is a **time series** — a sequence of (timestamp, value)
pairs for a specific combination of metric type and resource labels.

For example, the metric `compute.googleapis.com/instance/cpu/utilization` for VM
`my-vm-01` in zone `us-central1-a` is one time series. If you have 10 VMs, you have 10
independent time series for that metric type.

Metric types have one of three **kinds**:

| Kind | Description | Example | How to Read |
|---|---|---|---|
| **GAUGE** | Snapshot of a value at the measurement time. Has no memory of the past. | CPU utilization at 14:00:00 | The raw value at that instant |
| **DELTA** | Difference from the previous measurement period. Represents a rate of change. | Number of requests in the last minute | Sum over a window to get totals |
| **CUMULATIVE** | Monotonically increasing count since a start time. Resets only on resource restart. | Total bytes sent since VM started | Rate-of-change (delta) is the useful derived metric |

Understanding metric kinds matters when you write alerting conditions. A CPU utilization
alert uses GAUGE (raw percentage). A request-count alert uses DELTA or CUMULATIVE — you
want to alert on the rate (requests/minute) not the raw cumulative total.

GCP metrics also have a **value type**: BOOL, INT64, DOUBLE, STRING, or DISTRIBUTION.
Distribution metrics (used by Cloud Trace, HTTP request latency) store histograms, not
single values.

### Cloud Monitoring: Ops Agent

VMs report basic infrastructure metrics (CPU, network, disk I/O) to Cloud Monitoring
automatically — no agent required. However, for **memory utilization**, **per-process
metrics**, and **application logs**, you need the **Ops Agent**.

```
No agent required:      CPU utilization, network bytes in/out, disk read/write ops
Ops Agent required:     Memory utilization, disk fill %, per-process CPU/mem
Ops Agent (logging):    Application logs from /var/log, nginx/apache access logs, syslog
```

The Ops Agent replaces two legacy agents — the Monitoring agent (based on collectd) and
the Logging agent (based on fluentd). If you see references to either of those in exam
questions, know that the Ops Agent supersedes both.

> **ACE exam tip:** If an exam question asks why memory metrics are not visible on a
> Monitoring dashboard for a GCE instance, the answer is almost always that the Ops Agent
> is not installed. CPU, network, and disk I/O metrics are available without the agent;
> memory is not.

### Alerting Policies

An **alerting policy** defines when to send a notification. It has three parts:

1. **Condition** — the metric, comparison, threshold, and duration that must be satisfied
   to trigger the alert. For example: "CPU utilization > 80% for 5 minutes."
2. **Notification channels** — where to send the alert (email, PagerDuty, Slack, Pub/Sub,
   webhook, SMS).
3. **Documentation** — free-text instructions for the on-call engineer that appear in the
   notification.

GCP supports four condition types:

| Condition Type | Triggers When | Typical Use |
|---|---|---|
| **Metric threshold** | A metric crosses a value for a duration | CPU high, disk full, error rate spike |
| **Metric absence** | A metric stops reporting data | VM stopped, agent died, service went down |
| **Log-based** | Log entries match a filter at a rate/count | Error count in logs exceeds N per minute |
| **SLO burn rate** | An SLO's error budget is being consumed too fast | SRE alerting on SLO compliance |

An alerting policy can have multiple conditions combined with AND or OR logic. In this lab
you will use metric threshold (Exercise 2) and log-based alerting (Exercise 8).

> **ACE exam tip:** "Metric absence" is the right condition when you want to be alerted if
> a service _stops reporting_ entirely — not just if its value is high. A dead VM will
> produce no CPU metric at all, so a threshold condition will never fire; an absence
> condition will.

### Cloud Logging: Structured vs Unstructured Logs

Cloud Logging stores log entries. Each entry has:
- A **log name** (e.g. `projects/my-project/logs/syslog`)
- A **resource** (the GCP resource that emitted the log — VM, Cloud Run service, GKE pod)
- A **severity** level (DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL, ALERT, EMERGENCY)
- A **timestamp**
- A **payload** — either `textPayload` (plain string) or `jsonPayload` (structured JSON)
- A `protoPayload` for Audit Log entries (strongly typed Protocol Buffer)

**Structured logging** means emitting JSON payloads where fields are explicit keys. This
is far more useful than plain text because you can query on individual fields:

```json
{
  "message": "request failed",
  "user_id": "user_12345",
  "endpoint": "/api/orders",
  "latency_ms": 4502,
  "status_code": 500
}
```

With a structured log you can filter on `jsonPayload.status_code=500` or
`jsonPayload.latency_ms>1000`. With `textPayload` you can only substring-match the entire
string, which is fragile.

### Cloud Logging Query Language

The Logging query language (formerly called "advanced filters") is used in the Logs
Explorer, in `gcloud logging read`, and in log sinks. Queries use a comparison syntax
where each term further restricts the result set:

```
# All terms are ANDed together by default
resource.type="gce_instance"
severity>=WARNING

# Match a specific log name
logName="projects/my-project/logs/syslog"

# Match a field in the JSON payload
jsonPayload.message:"error"

# Match a proto payload field (Audit Logs)
protoPayload.methodName="SetIamPolicy"

# Time range (ISO 8601)
timestamp>="2024-01-01T00:00:00Z"
timestamp<"2024-01-02T00:00:00Z"

# Substring match (colon = contains)
textPayload:"NGINX_ERROR"

# Equality match (equals = exact match)
labels."compute.googleapis.com/resource_name"="my-vm-01"

# OR logic
severity=ERROR OR severity=CRITICAL
```

The most important operators:
- `:` — substring / contains (for strings and fields)
- `=` — exact equality
- `!=` — not equal
- `>`, `>=`, `<`, `<=` — numeric or lexicographic comparison
- `AND`, `OR`, `NOT` — boolean logic

### Cloud Audit Logs

Audit logs record _who did what_ to GCP resources. They are a special category of Cloud
Logging entries with a `protoPayload` (not `jsonPayload`).

| Audit Log Type | What it Records | Cost | Default State |
|---|---|---|---|
| **Admin Activity** | Mutations to resource configurations (create VM, set IAM policy, delete bucket) | Free, always stored | Always on, cannot disable |
| **Data Access** | Reads and writes to resource data (read a GCS object, query a BigQuery table) | Paid, can be large | Off by default — must enable per service |
| **System Events** | Automatic GCP system actions (live migration, autoscaling) | Free | Always on |
| **Policy Denied** | IAM policy denied a principal from accessing a resource | Free | Always on |

For the ACE exam, the key facts are:
1. Admin Activity logs cannot be disabled — GCP always records configuration changes.
2. Data Access logs must be explicitly enabled and will significantly increase log volume
   and cost for high-traffic services like GCS or BigQuery.
3. Audit logs use `protoPayload` not `jsonPayload` — query them with
   `protoPayload.methodName` or `protoPayload.resourceName`.
4. The `principalEmail` inside `protoPayload.authenticationInfo` tells you _who_ made the
   change.

> **ACE exam tip:** If an exam question asks how to find out who deleted a GCS bucket or
> who changed an IAM policy, the answer is Cloud Audit Logs with a filter on
> `protoPayload.methodName`. These are Admin Activity logs — no configuration needed.

### Log Sinks

A **log sink** exports log entries that match a filter to an external destination. Sinks
run continuously — every new log entry matching the filter is automatically exported.

| Destination | Use Case | Retention | Query |
|---|---|---|---|
| **Cloud Storage** | Long-term archival, compliance, cost-effective cold storage | Years (GCS lifecycle policies) | gsutil/gcloud storage, download then grep |
| **BigQuery** | Structured log analytics, SQL queries across months of logs | Unlimited (BigQuery storage pricing) | Standard SQL in BigQuery |
| **Pub/Sub** | Real-time streaming to external systems (SIEM, custom processors) | Consumer-controlled | Streaming consumers |
| **Log Bucket** | Optimised log storage within Cloud Logging, configurable retention | 1 day to 3650 days | Log Explorer, log analytics |

The default `_Default` log bucket retains all logs for **30 days**. You can create custom
log buckets with retention from 1 to 3650 days. If you need longer than 30 days in
Logging (for compliance) but shorter than "forever", a custom log bucket is the right
tool — not GCS.

A sink has three parts:
1. **Name** — identifier for the sink
2. **Filter** — Logging query language expression to select which entries to export
3. **Destination** — where to write (GCS bucket URI, BigQuery dataset, Pub/Sub topic)

When you create a sink to GCS or BigQuery, GCP automatically creates a **service account**
(the sink's writer identity) and you must grant it write access to the destination.

### Log-Based Metrics

Log-based metrics convert log entries into Cloud Monitoring metrics. This bridges the
logging and monitoring pillars — you can alert on the _frequency_ of specific log events
without building a separate log processor.

Two types:
- **Counter metric** — counts the number of log entries matching a filter per unit time.
  Example: count of entries with `severity=ERROR` and `resource.type="gce_instance"`.
- **Distribution metric** — extracts a numeric field from each matching log entry and
  builds a histogram. Example: distribution of `jsonPayload.latency_ms` across all
  request log entries.

Counter metrics are the most common exam topic — create a metric, then create an alerting
policy that fires when the count exceeds a threshold.

### SLOs and SLIs (ACE Exam Addition)

The GCP ACE exam now includes Service Level Objectives and Service Level Indicators.

- **SLI (Service Level Indicator)** — a measurable proxy for user experience. Examples:
  "proportion of HTTP requests that succeed", "proportion of requests with latency < 200ms".
- **SLO (Service Level Objective)** — a target for an SLI over a window. Example:
  "99.9% of requests succeed over a rolling 30-day window".
- **Error budget** — the complement of the SLO: `100% - SLO%`. A 99.9% SLO gives
  0.1% error budget — about 43 minutes of downtime per month. When the error budget is
  exhausted, the SLO is breached.

```
30-day rolling window:
  Total minutes: 43,200
  Error budget (0.1%): 43.2 minutes

  If downtime this month = 30 minutes:  budget remaining = 13.2 min (healthy)
  If downtime this month = 50 minutes:  budget EXHAUSTED (SLO breached)
```

In Cloud Monitoring, you can define SLOs on backend services (HTTP success rate, latency)
and create **SLO burn rate alerts** that fire when the budget is being consumed faster than
it can replenish.

> **ACE exam tip:** Burn rate alerting is more sensitive than threshold alerting for SLOs.
> A 14x burn rate on a 30-day window means the error budget will be exhausted in ~50 hours
> — triggering an alert now gives you time to fix it before the SLO is breached.

### Cloud Trace

Cloud Trace records the latency of requests as they flow through a distributed system.
Each **trace** represents one request; it is composed of **spans**, where each span is one
hop (e.g., one microservice call, one database query).

```
Request trace (total: 340ms):
  [frontend-service      340ms] ─────────────────────
    [auth-service         45ms]   ────
    [product-service     280ms]         ──────────────
      [database query    240ms]           ────────────
    [logging             15ms]                          ─
```

Cloud Trace auto-instruments many GCP services (Cloud Run, App Engine, GKE with the
trace agent, Cloud Functions). For Compute Engine VMs you need to use the OpenTelemetry
SDK or the Cloud Trace client library in your application code.

The **Trace Explorer** in the console shows a latency distribution histogram and lets you
drill into individual traces to find the slowest operations. The exam tests whether you
know which tool answers "why is my application slow?" — the answer is Cloud Trace.

### Cloud Profiler

Cloud Profiler continuously samples the CPU and memory usage of running application code,
building **flame graphs** that show which functions consume the most resources.

Unlike Trace (which measures per-request latency), Profiler measures _where_ the
application spends CPU cycles or allocates memory in aggregate. It answers "which function
is causing my CPU to spike?" rather than "which request is slow?".

Cloud Profiler adds < 1% overhead and can run continuously in production. It supports Go,
Java, Node.js, and Python.

### Error Reporting

Error Reporting automatically groups application exceptions and stack traces from Cloud
Logging into distinct error groups. It counts occurrences, shows the first/last seen time,
and can notify you when a new error group appears.

Error Reporting works without any additional configuration if your application writes
exceptions to Cloud Logging in the expected format (stack traces in `textPayload` or
`jsonPayload.stack_trace`). For App Engine, Cloud Run, and Cloud Functions, exception
capture is automatic.

The exam tests: "which tool surfaces application exceptions grouped by stack trace?" —
the answer is Error Reporting.

---

## Setup

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"
echo "Project: ${PROJECT_ID}, Region: ${REGION}, Zone: ${ZONE}"
```

### Create a Test VM

Several exercises require a running Compute Engine instance to observe metrics and generate
logs. Create one now:

```bash
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-central1-a"

gcloud compute instances create lab10-vm \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --zone="${ZONE}" \
  --tags=http-server \
  --metadata-from-file=startup-script=vm-startup.sh \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/zones/us-central1-a/instances/lab10-vm].
NAME      ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
lab10-vm  us-central1-a  e2-micro                   10.128.0.X   34.xxx.xxx.xx  RUNNING
```

Also create a firewall rule to allow HTTP traffic (needed for Exercise 9's uptime check):

```bash
gcloud compute firewall-rules create lab10-allow-http \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:80 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=http-server \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Rule already exists — skipping."
```

---

## Exercises

### Exercise 1 — Create a Custom Dashboard with GCE CPU Charts

Cloud Monitoring dashboards are the first thing you look at when investigating a problem.
A well-configured dashboard gives you immediate context: is this normal, or is something
broken?

You can create dashboards via the Console UI or via `gcloud monitoring dashboards create`
with a JSON/YAML specification. The gcloud approach is reproducible and version-controllable.

Import the checked-in dashboard definition:

```bash
gcloud monitoring dashboards create \
  --config-from-file=lab10-dashboard.json \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created [projects/YOUR_PROJECT/dashboards/DASHBOARD_ID].
```

List your dashboards to confirm it was created:

```bash
gcloud monitoring dashboards list \
  --project="${PROJECT_ID}" \
  --format="table(displayName,name)"
```

Expected output:

```
DISPLAY_NAME                           NAME
Lab 10 — GCE Operations Dashboard     projects/YOUR_PROJECT/dashboards/XXXXX
```

> **Why network and disk use `ALIGN_RATE`?** Network bytes and disk ops are DELTA metrics
> — they accumulate over each measurement interval. `ALIGN_RATE` converts a cumulative
> count into a rate (bytes/second or ops/second), which is much more interpretable than a
> raw delta that changes with alignment period length. CPU utilization is a GAUGE metric —
> it already represents a snapshot percentage, so `ALIGN_MEAN` is appropriate.

View the dashboard in the Cloud Console:

1. Get the dashboard ID from the create output (the last segment of the `name` field):
   ```bash
   DASHBOARD_ID=$(gcloud monitoring dashboards list \
     --project="${PROJECT_ID}" \
     --format="value(name)" \
     --filter="displayName='Lab 10 — GCE Operations Dashboard'" \
     | sed 's|.*/||')
   echo "https://console.cloud.google.com/monitoring/dashboards/custom/${DASHBOARD_ID}?project=${PROJECT_ID}"
   ```
2. Open the printed URL in your browser.
3. Alternatively: **Cloud Console → Monitoring → Dashboards → Lab 10 — GCE Operations Dashboard**.
4. You should see three chart widgets — CPU utilization, network bytes in/out, and disk ops.
   Charts may show a flat line initially; generate some load to see movement:
   ```bash
   gcloud compute ssh lab10-vm --zone="${ZONE}" --project="${PROJECT_ID}" \
     --command="dd if=/dev/urandom of=/dev/null bs=1M count=500"
   ```
5. Refresh the dashboard after 1–2 minutes — the CPU and disk charts should show a spike.

---

### Exercise 2 — Create an Alerting Policy: CPU > 80% for 5 Minutes

An alerting policy is useless if it fires too frequently (alert fatigue) or not at all
(silent failures). The "duration" parameter is the key lever: the metric must exceed the
threshold continuously for the entire duration before the alert fires. This prevents
transient spikes from generating pages at 3am.

Create a metric threshold alerting policy on CPU utilization:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud alpha monitoring policies create \
  --policy-from-file=lab10-cpu-alert.json \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created alert policy [projects/YOUR_PROJECT/alertPolicies/POLICY_ID].
```

List alerting policies to confirm creation:

```bash
gcloud alpha monitoring policies list \
  --project="${PROJECT_ID}" \
  --format="table(displayName,enabled,conditions[0].displayName)"
```

Expected output:

```
DISPLAY_NAME                        ENABLED  CONDITIONS_DISPLAY_NAME
Lab 10 — High CPU on lab10-vm       True     CPU utilization > 80% for 5 minutes
```

Describe the policy to see its full configuration:

```bash
gcloud alpha monitoring policies list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10'" \
  --format="yaml(displayName,conditions,alertStrategy)"
```

> **Why 5 minutes and not 1 minute?** CPU naturally spikes during process startup, garbage
> collection, and short bursts. A 1-minute duration would generate false positives
> constantly. 5 minutes (300 seconds) ensures you are only alerted about _sustained_ high
> CPU that genuinely warrants investigation. For critical services where even 1 minute of
> high CPU indicates a real problem, reduce the duration. For batch jobs that legitimately
> run at 100% CPU for extended periods, use a longer duration or no CPU alert at all.

> **ACE exam tip:** The `thresholdValue` for CPU utilization in Cloud Monitoring is
> expressed as a decimal between 0 and 1 (0.8 = 80%), not as a percentage. The exam may
> include distractor answers that use percentage notation — always use the decimal form
> in the API/gcloud.

---

### Exercise 3 — Create a Notification Channel and Attach it to the Alert

An alerting policy with no notification channel will open an incident in the Cloud Console
but send no external notification. In practice, alerts need to reach the on-call engineer
via email, PagerDuty, Slack, or another channel.

Create an email notification channel:

```bash
PROJECT_ID=$(gcloud config get-value project)

# Replace with your actual email address
YOUR_EMAIL="your-email@example.com"

envsubst < lab10-email-channel.json.tmpl > /tmp/lab10-email-channel.json

gcloud alpha monitoring channels create \
  --channel-content-from-file=/tmp/lab10-email-channel.json \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created notification channel [projects/YOUR_PROJECT/notificationChannels/CHANNEL_ID].
```

Get the channel ID — you need it to attach the channel to the alerting policy:

```bash
CHANNEL_ID=$(gcloud alpha monitoring channels list \
  --project="${PROJECT_ID}" \
  --filter="displayName='Lab 10 On-Call Email'" \
  --format="value(name)")

echo "Channel ID: ${CHANNEL_ID}"
```

Expected output:

```
Channel ID: projects/YOUR_PROJECT/notificationChannels/12345678901234567
```

Now update the alerting policy to attach the notification channel. First get the policy
name:

```bash
POLICY_NAME=$(gcloud alpha monitoring policies list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10 — High CPU'" \
  --format="value(name)")

echo "Policy: ${POLICY_NAME}"
```

Update the policy with the notification channel:

```bash
gcloud alpha monitoring policies update "${POLICY_NAME}" \
  --add-notification-channels="${CHANNEL_ID}" \
  --project="${PROJECT_ID}"
```

Expected output:

```
Updated alert policy [projects/YOUR_PROJECT/alertPolicies/POLICY_ID].
```

Verify the channel is attached:

```bash
gcloud alpha monitoring policies describe "${POLICY_NAME}" \
  --project="${PROJECT_ID}" \
  --format="yaml(displayName,notificationChannels)"
```

Expected output:

```yaml
displayName: Lab 10 — High CPU on lab10-vm
notificationChannels:
- projects/YOUR_PROJECT/notificationChannels/12345678901234567
```

> **Notification channel types available in Cloud Monitoring:**
> Email, SMS, Slack, PagerDuty, Webhooks (for any HTTPS endpoint), Pub/Sub (for custom
> routing logic), and Google Chat. For the ACE exam, know that Pub/Sub notification
> channels enable _arbitrary programmatic handling_ of alert notifications — for example,
> auto-scaling or auto-remediation triggered by an alert.

---

### Exercise 4 — Write Advanced Log Queries

The Logs Explorer query language is a precision tool. Knowing how to compose queries
quickly separates operators who find the root cause in 5 minutes from those who scroll
through raw logs for an hour.

All commands below use `gcloud logging read`. The filter is the same syntax used in the
Logs Explorer console — you can copy-paste between the two.

#### Query 1: All WARNING and above logs from the lab VM

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud logging read \
  'resource.type="gce_instance" AND severity>=WARNING' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="table(timestamp,severity,resource.labels.instance_id,textPayload)"
```

Expected output (contains the WARNING line from the startup script):

```
TIMESTAMP                     SEVERITY  INSTANCE_ID    TEXT_PAYLOAD
2024-01-01T00:00:05.000000Z   WARNING   1234567890123  lab10-app: WARNING: high memory threshold approaching
2024-01-01T00:00:05.000000Z   ERROR     1234567890123  lab10-app: ERROR: simulated application error for lab exercise
```

#### Query 2: Only ERROR severity from the lab10-app tag

```bash
gcloud logging read \
  'resource.type="gce_instance" AND severity=ERROR AND textPayload:"lab10-app"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="table(timestamp,severity,textPayload)"
```

Expected output:

```
TIMESTAMP                     SEVERITY  TEXT_PAYLOAD
2024-01-01T00:00:05.000000Z   ERROR     lab10-app: ERROR: simulated application error for lab exercise
```

#### Query 3: Nginx access logs from the VM

```bash
gcloud logging read \
  'resource.type="gce_instance" AND logName:"nginx"' \
  --project="${PROJECT_ID}" \
  --limit=5 \
  --format="table(timestamp,logName,textPayload)"
```

If nginx has not received requests yet, this returns no results. Generate a request first:

```bash
VM_IP=$(gcloud compute instances describe lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

curl -s "http://${VM_IP}" > /dev/null
echo "Sent request to ${VM_IP}"
```

Wait 30 seconds for the log to appear, then run the query again.

#### Query 4: All log entries in a time window (last 10 minutes)

```bash
# Calculate timestamp 10 minutes ago
START_TIME=$(date -u -d '10 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
             date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ')

gcloud logging read \
  "resource.type=\"gce_instance\" AND timestamp>=\"${START_TIME}\"" \
  --project="${PROJECT_ID}" \
  --limit=20 \
  --format="table(timestamp,severity,logName)"
```

Expected output (a mix of system and application logs from the last 10 minutes):

```
TIMESTAMP                     SEVERITY  LOG_NAME
2024-01-01T00:05:12.000000Z   INFO      ...logs/nginx/access
2024-01-01T00:00:05.000000Z   ERROR     ...logs/syslog
2024-01-01T00:00:05.000000Z   WARNING   ...logs/syslog
2024-01-01T00:00:05.000000Z   INFO      ...logs/syslog
```

> **Performance tip for log queries:** Always include `resource.type` and a time range
> in your filter. These are indexed fields that narrow the search before Cloud Logging
> evaluates the remaining filter terms. A query without a resource type or time range
> scans your entire log history, which is slow and can be expensive if you have high log
> volume. The Logs Explorer warns you when a query will scan a large volume.

---

### Exercise 5 — Find IAM Changes Using Audit Logs

Admin Activity audit logs record every IAM policy change. This is the forensic record used
in security investigations. The key technique is filtering on the `methodName` field inside
`protoPayload`.

#### Step 5a — Generate an IAM Change to Audit

First, make an IAM change so there is an audit event to find:

```bash
PROJECT_ID=$(gcloud config get-value project)

# Grant viewer role to a test service account
# (creating the service account generates its own audit event)
gcloud iam service-accounts create lab10-audit-sa \
  --display-name="Lab 10 Audit Test SA" \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created service account [lab10-audit-sa].
```

Now grant it a role — this is the IAM change we will find in the audit logs:

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:lab10-audit-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/viewer"
```

Expected output:

```
Updated IAM policy for project [YOUR_PROJECT].
bindings:
- members:
  - serviceAccount:lab10-audit-sa@YOUR_PROJECT.iam.gserviceaccount.com
  role: roles/viewer
...
```

#### Step 5b — Query Audit Logs for IAM Changes

Wait 60 seconds for the audit log to be indexed, then query:

```bash
gcloud logging read \
  'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName="SetIamPolicy"' \
  --project="${PROJECT_ID}" \
  --limit=5 \
  --format="table(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)"
```

Expected output:

```
TIMESTAMP                     METHOD_NAME     PRINCIPAL_EMAIL                    RESOURCE_NAME
2024-01-01T00:01:30.000000Z   SetIamPolicy    your-account@example.com           projects/YOUR_PROJECT
```

The `principalEmail` field tells you exactly which account made the change. This is the
answer to "who granted that role?" in a security investigation.

#### Step 5c — Find Service Account Creation Events

```bash
gcloud logging read \
  'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.methodName:"CreateServiceAccount"' \
  --project="${PROJECT_ID}" \
  --limit=5 \
  --format="table(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail,protoPayload.request.name)"
```

Expected output:

```
TIMESTAMP                     METHOD_NAME           PRINCIPAL_EMAIL              REQUEST_NAME
2024-01-01T00:01:00.000000Z   CreateServiceAccount  your-account@example.com     lab10-audit-sa
```

#### Step 5d — Find ALL IAM-related Audit Events (broader search)

```bash
gcloud logging read \
  'logName:"cloudaudit.googleapis.com%2Factivity" AND protoPayload.serviceName="iam.googleapis.com"' \
  --project="${PROJECT_ID}" \
  --limit=10 \
  --format="table(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail)"
```

This broader filter catches all IAM service operations — useful when you need to find
_any_ IAM change without knowing the exact method name.

> **ACE exam tip:** Audit log entries always use `logName` containing
> `cloudaudit.googleapis.com`. Admin Activity goes into
> `cloudaudit.googleapis.com%2Factivity`. Data Access goes into
> `cloudaudit.googleapis.com%2Fdata_access`. The URL-encoded `%2F` is a forward slash.
> Knowing this log name pattern is required for exam questions about audit log filtering.

---

### Exercise 6 — Create a Log Sink to Export Logs to GCS

A log sink to GCS is the standard pattern for long-term log archival and compliance.
Logs are written as compressed JSON files, organized by date in GCS.

#### Step 6a — Create the GCS Bucket

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud storage buckets create "gs://lab10-logs-${PROJECT_ID}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --project="${PROJECT_ID}"
```

Expected output:

```
Creating gs://lab10-logs-YOUR_PROJECT/...
```

#### Step 6b — Create the Log Sink

```bash
gcloud logging sinks create lab10-gcs-sink \
  "storage.googleapis.com/lab10-logs-${PROJECT_ID}" \
  --log-filter='resource.type="gce_instance" AND severity>=WARNING' \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created [https://logging.googleapis.com/v2/projects/YOUR_PROJECT/sinks/lab10-gcs-sink].
Please remember to grant `serviceAccount:p1234567890-XXXXX@gcp-sa-logging.iam.gserviceaccount.com` the Writer role on the destination.
More information about sinks can be found at https://cloud.google.com/logging/docs/export/configure_export
```

The output includes the **sink's writer identity** — a service account that Cloud Logging
uses to write to the GCS bucket. You must grant it write access:

```bash
# Get the sink's writer identity (service account)
SINK_SA=$(gcloud logging sinks describe lab10-gcs-sink \
  --project="${PROJECT_ID}" \
  --format="value(writerIdentity)")

echo "Sink writer identity: ${SINK_SA}"

# Grant it objectCreator on the GCS bucket
gcloud storage buckets add-iam-policy-binding \
  "gs://lab10-logs-${PROJECT_ID}" \
  --member="${SINK_SA}" \
  --role="roles/storage.objectCreator"
```

Expected output:

```
Sink writer identity: serviceAccount:p1234567890-XXXXX@gcp-sa-logging.iam.gserviceaccount.com

Updated IAM policy for bucket [lab10-logs-YOUR_PROJECT].
bindings:
- members:
  - serviceAccount:p1234567890-XXXXX@gcp-sa-logging.iam.gserviceaccount.com
  role: roles/storage.objectCreator
```

Verify the sink configuration:

```bash
gcloud logging sinks describe lab10-gcs-sink \
  --project="${PROJECT_ID}" \
  --format="yaml(name,destination,filter,writerIdentity)"
```

Expected output:

```yaml
destination: storage.googleapis.com/lab10-logs-YOUR_PROJECT
filter: resource.type="gce_instance" AND severity>=WARNING
name: projects/YOUR_PROJECT/sinks/lab10-gcs-sink
writerIdentity: serviceAccount:p1234567890-XXXXX@gcp-sa-logging.iam.gserviceaccount.com
```

#### Step 6c — Verify Logs Are Exported

Generate some WARNING-level logs to trigger the sink, then check GCS:

```bash
# SSH into the VM and write warning-level log entries
gcloud compute ssh lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --command='for i in 1 2 3; do logger -t lab10-app -p user.warning "WARNING: sink test entry ${i}"; done; echo "Logged 3 warning entries"'
```

Expected output:

```
Logged 3 warning entries
```

Wait 2–3 minutes for the sink to batch and export the entries, then check GCS:

```bash
gcloud storage ls "gs://lab10-logs-${PROJECT_ID}/" --recursive
```

Expected output (GCS organizes logs by date/hour):

```
gs://lab10-logs-YOUR_PROJECT/cloudlogs/2024/01/01/00/
gs://lab10-logs-YOUR_PROJECT/cloudlogs/2024/01/01/00/lab10-gcs-sink_gce_instance_20240101T000000_20240101T010000_00.json
```

> **Log sink export delay:** Cloud Logging exports logs in batches, not in real time. GCS
> sinks export on approximately 1-hour intervals. If you check GCS immediately after
> writing log entries, you will not see them yet. Plan for up to 2 hours for logs to
> appear in GCS. For Pub/Sub sinks, the delay is seconds to minutes — use Pub/Sub when
> you need near-real-time log streaming.

---

### Exercise 7 — Create a Log Sink to BigQuery for Analysis

A BigQuery sink lets you run SQL queries over your logs. This is the right pattern for
compliance reporting ("show me all IAM changes in the last 90 days"), trend analysis, and
ad-hoc investigations that would be difficult with the Logs Explorer.

#### Step 7a — Create the BigQuery Dataset

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

bq --location="${REGION}" mk \
  --dataset \
  --description="Lab 10 log exports" \
  "${PROJECT_ID}:lab10_logs"
```

Expected output:

```
Dataset 'YOUR_PROJECT:lab10_logs' successfully created.
```

#### Step 7b — Create the BigQuery Log Sink

```bash
gcloud logging sinks create lab10-bq-sink \
  "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/lab10_logs" \
  --log-filter='logName:"cloudaudit.googleapis.com%2Factivity"' \
  --use-partitioned-tables \
  --project="${PROJECT_ID}"
```

The `--use-partitioned-tables` flag is important: it creates date-partitioned BigQuery
tables, which dramatically reduces query cost when filtering by date range. Without
partitioning, every query scans the entire table.

Expected output:

```
Created [https://logging.googleapis.com/v2/projects/YOUR_PROJECT/sinks/lab10-bq-sink].
Please remember to grant `serviceAccount:pXXXXXX-YYYYY@gcp-sa-logging.iam.gserviceaccount.com` the Writer role on the destination.
```

Grant the sink's writer identity access to the BigQuery dataset:

```bash
BQ_SINK_SA=$(gcloud logging sinks describe lab10-bq-sink \
  --project="${PROJECT_ID}" \
  --format="value(writerIdentity)")

echo "BQ sink service account: ${BQ_SINK_SA}"

# Grant bigquery.dataEditor so the sink can create tables and insert rows
bq add-iam-policy-binding \
  --member="${BQ_SINK_SA}" \
  --role="roles/bigquery.dataEditor" \
  "${PROJECT_ID}:lab10_logs"
```

Expected output:

```
BQ sink service account: serviceAccount:pXXXXX-YYYYY@gcp-sa-logging.iam.gserviceaccount.com
Successfully updated IAM policy for dataset lab10_logs.
```

#### Step 7c — Query Audit Logs in BigQuery

Generate an IAM event and wait 10–15 minutes for it to appear in BigQuery:

```bash
# Grant then revoke a role to generate two audit events
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:lab10-audit-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:lab10-audit-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"

echo "Generated two IAM audit events — wait 10-15 minutes then run the BigQuery query"
```

After 10–15 minutes, query the exported audit logs in BigQuery:

```bash
bq query \
  --use_legacy_sql=false \
  --project_id="${PROJECT_ID}" \
  "
SELECT
  timestamp,
  proto_payload.method_name AS method,
  proto_payload.authentication_info.principal_email AS who,
  proto_payload.resource_name AS resource
FROM \`${PROJECT_ID}.lab10_logs.cloudaudit_googleapis_com_activity_*\`
WHERE DATE(_PARTITIONTIME) = CURRENT_DATE()
  AND proto_payload.method_name LIKE '%Iam%'
ORDER BY timestamp DESC
LIMIT 20
"
```

Expected output (once events propagate — allow up to 15 minutes):

```
+---------------------+------------------+---------------------------+----------------------+
|      timestamp      |      method      |           who             |       resource       |
+---------------------+------------------+---------------------------+----------------------+
| 2024-01-01 00:05:00 | SetIamPolicy     | your-email@example.com    | projects/YOUR_PROJECT |
| 2024-01-01 00:04:00 | SetIamPolicy     | your-email@example.com    | projects/YOUR_PROJECT |
+---------------------+------------------+---------------------------+----------------------+
```

> **Why BigQuery for logs?** The Logs Explorer is excellent for interactive querying of
> recent logs (last 30 days in the default bucket). BigQuery is the right tool when you
> need: SQL aggregations across months of logs, joins between log data and other datasets,
> scheduled reports, or retention beyond 30 days at low cost. The `_PARTITIONTIME` filter
> in the WHERE clause is critical — without it, BigQuery scans all partitions and the
> query is expensive.

---

### Exercise 8 — Create a Log-Based Metric and Alert on It

Log-based metrics bridge logging and monitoring. You define a filter, and Cloud Monitoring
counts the matching log entries as a metric that you can chart and alert on.

This is the right pattern when you want to alert on application error rates, security
events, or any condition that is naturally expressed as a log pattern rather than a numeric
metric.

#### Step 8a — Create a Counter Log-Based Metric

Create a metric that counts ERROR-level log entries from the lab VM:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud logging metrics create lab10-error-count \
  --description="Count of ERROR log entries from lab10-vm" \
  --log-filter='resource.type="gce_instance" AND severity=ERROR AND textPayload:"lab10-app"' \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created [lab10-error-count].
```

List log-based metrics to confirm:

```bash
gcloud logging metrics list \
  --project="${PROJECT_ID}" \
  --format="table(name,description,filter)"
```

Expected output:

```
NAME                DESCRIPTION                                    FILTER
lab10-error-count   Count of ERROR log entries from lab10-vm       resource.type="gce_instance" AND...
```

#### Step 8b — Generate Error Logs to Populate the Metric

Log-based metrics only show data from the point of creation forward. Generate some error
entries:

```bash
# Write error log entries to the VM
gcloud compute ssh lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --command='for i in $(seq 1 10); do logger -t lab10-app -p user.err "ERROR: simulated application error number ${i}"; sleep 2; done; echo "Generated 10 error log entries"'
```

Expected output:

```
Generated 10 error log entries
```

#### Step 8c — Create an Alerting Policy on the Log-Based Metric

Log-based metrics appear in Cloud Monitoring with the prefix
`logging.googleapis.com/user/`. Create a threshold alert that fires when the error count
exceeds 3 in a 5-minute window:

```bash
cat > /tmp/lab10-logmetric-alert.json << 'EOF'
{
  "displayName": "Lab 10 — Application Error Rate Too High",
  "conditions": [
    {
      "displayName": "More than 3 errors in 5 minutes",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"logging.googleapis.com/user/lab10-error-count\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_SUM",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 3,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "More than 3 application errors were logged in a 5-minute window on lab10-vm. Check application logs with: gcloud logging read 'resource.type=gce_instance AND severity=ERROR' --limit=20",
    "mimeType": "text/markdown"
  }
}
EOF

gcloud alpha monitoring policies create \
  --policy-from-file=/tmp/lab10-logmetric-alert.json \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created alert policy [projects/YOUR_PROJECT/alertPolicies/POLICY_ID].
```

> **ALIGN_SUM vs ALIGN_RATE for log-based metrics:** Log-based counter metrics are DELTA
> metrics — each data point represents the count of matching entries in that alignment
> period. Use `ALIGN_SUM` to get the total count per window. `ALIGN_RATE` would give you
> count-per-second, which is usually less intuitive for error alerting where you think in
> terms of "N errors per 5 minutes."

#### Step 8d — Verify the Metric Has Data

Wait 5 minutes after generating the errors, then check the metric:

```bash
gcloud monitoring time-series list \
  --filter='metric.type="logging.googleapis.com/user/lab10-error-count"' \
  --project="${PROJECT_ID}" \
  --format="table(metric.type,points[0].value.int64Value,points[0].interval.endTime)"
```

Expected output:

```
METRIC_TYPE                                    INT64_VALUE  END_TIME
logging.googleapis.com/user/lab10-error-count  10           2024-01-01T00:10:00Z
```

---

### Exercise 9 — Uptime Check with Alert on Failure

An uptime check probes an external endpoint on a schedule from multiple geographic
locations. If the endpoint fails to respond, Cloud Monitoring fires an alert. This is
the simplest form of external black-box availability monitoring.

#### Step 9a — Get the VM's External IP

```bash
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-central1-a"

VM_IP=$(gcloud compute instances describe lab10-vm \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "VM external IP: ${VM_IP}"
```

Expected output:

```
VM external IP: 34.xxx.xxx.xx
```

#### Step 9b — Create the Uptime Check

```bash
cat > /tmp/lab10-uptime-check.json << EOF
{
  "displayName": "Lab 10 — lab10-vm nginx HTTP",
  "httpCheck": {
    "path": "/",
    "port": 80,
    "requestMethod": "GET",
    "validateSsl": false
  },
  "monitoredResource": {
    "type": "uptime_url",
    "labels": {
      "host": "${VM_IP}",
      "project_id": "${PROJECT_ID}"
    }
  },
  "period": "60s",
  "timeout": "10s",
  "checkerType": "STATIC_IP_CHECKERS"
}
EOF

gcloud monitoring uptime create \
  --display-name="Lab 10 — lab10-vm nginx HTTP" \
  --synthetic-target='' \
  --http-check-path="/" \
  --http-check-port=80 \
  --resource-type="uptime_url" \
  --resource-labels="host=${VM_IP},project_id=${PROJECT_ID}" \
  --period=60 \
  --timeout=10 \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created [projects/YOUR_PROJECT/uptimeCheckConfigs/UPTIME_CHECK_ID].
```

Verify the uptime check was created:

```bash
gcloud monitoring uptime list \
  --project="${PROJECT_ID}" \
  --format="table(displayName,httpCheck.path,monitoredResource.labels.host,period)"
```

Expected output:

```
DISPLAY_NAME                    PATH  HOST            PERIOD
Lab 10 — lab10-vm nginx HTTP    /     34.xxx.xxx.xx   60s
```

#### Step 9c — Create an Alert for Uptime Check Failure

The uptime check needs an alerting policy to actually notify you on failure. The metric
for uptime checks is `monitoring.googleapis.com/uptime_check/check_passed`:

```bash
# Get the uptime check ID
UPTIME_CHECK_ID=$(gcloud monitoring uptime list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10'" \
  --format="value(name)" | awk -F/ '{print $NF}')

echo "Uptime check ID: ${UPTIME_CHECK_ID}"

cat > /tmp/lab10-uptime-alert.json << EOF
{
  "displayName": "Lab 10 — lab10-vm Uptime Failure",
  "conditions": [
    {
      "displayName": "Uptime check failing from any location",
      "conditionThreshold": {
        "filter": "resource.type = \"uptime_url\" AND metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\" AND metric.labels.check_id = \"${UPTIME_CHECK_ID}\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "perSeriesAligner": "ALIGN_FRACTION_TRUE",
            "crossSeriesReducer": "REDUCE_MEAN"
          }
        ],
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1.0,
        "duration": "0s",
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "documentation": {
    "content": "The uptime check for lab10-vm is failing. The nginx service may be down. SSH to the VM and check: gcloud compute ssh lab10-vm -- sudo systemctl status nginx",
    "mimeType": "text/markdown"
  }
}
EOF

gcloud alpha monitoring policies create \
  --policy-from-file=/tmp/lab10-uptime-alert.json \
  --project="${PROJECT_ID}"
```

Expected output:

```
Created alert policy [projects/YOUR_PROJECT/alertPolicies/POLICY_ID].
```

#### Step 9d — Intentionally Break the Service and Watch the Alert Fire

Stop nginx on the VM to simulate a service outage:

```bash
gcloud compute ssh lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --command='sudo systemctl stop nginx && echo "nginx stopped"'
```

Expected output:

```
nginx stopped
```

The uptime check runs every 60 seconds from multiple geographic locations. After 2–3
minutes, Cloud Monitoring detects the failure. Check the uptime check status:

```bash
# List recent uptime check results (this may take 2-3 minutes to reflect the outage)
gcloud monitoring uptime list \
  --project="${PROJECT_ID}" \
  --format="table(displayName,name)"
```

To verify the failure is being detected, you can manually test the endpoint:

```bash
VM_IP=$(gcloud compute instances describe lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

# This should fail — nginx is stopped
curl -s --connect-timeout 5 "http://${VM_IP}" || echo "Connection failed — expected!"
```

Expected output:

```
Connection failed — expected!
```

Restore nginx to fix the "outage":

```bash
gcloud compute ssh lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --command='sudo systemctl start nginx && echo "nginx restarted"'
```

Expected output:

```
nginx restarted
```

Verify nginx is responding again:

```bash
curl -s --connect-timeout 5 "http://${VM_IP}" | grep -o '<title>.*</title>' || echo "Nginx responding"
```

> **Multi-region uptime checks:** GCP probes uptime checks from multiple global locations
> (the Americas, Europe, Asia-Pacific). The alert fires when a threshold number of
> locations fail (default: any location). This prevents false positives from transient
> regional network issues — if only one location fails, the alert does not fire. You can
> configure the threshold in the uptime check settings. For the ACE exam, know that
> uptime checks are external probes from outside your VPC — they test the public endpoint,
> not internal reachability.

---

## Key Takeaways

- **Cloud Monitoring metrics** have three kinds: GAUGE (snapshot), DELTA (change over
  interval), and CUMULATIVE (monotonically increasing). Using the wrong aggregation
  function for the metric kind produces meaningless charts and unreliable alerts.

- **Memory metrics require the Ops Agent.** CPU, network, and disk I/O are available
  without any agent. The Ops Agent replaces the legacy Monitoring agent (collectd) and
  Logging agent (fluentd) — there is only one agent to install.

- **Alerting policy conditions:** metric threshold (value crosses a level), metric absence
  (value stops reporting), log-based (log entries match a filter), SLO burn rate (error
  budget consumed too fast). Metric absence is the right choice when a stopped service
  produces no metrics at all.

- **Notification channels** must be explicitly attached to alerting policies. An alerting
  policy without a notification channel opens incidents in the console but sends no
  external alert. Pub/Sub channels enable programmatic alert handling and auto-remediation.

- **Cloud Logging query language:** always include `resource.type` and a time range in
  your filter for performance. Use `:` for substring matching and `=` for exact equality.
  AUDIT log entries use `protoPayload` (not `jsonPayload`) and log names containing
  `cloudaudit.googleapis.com`.

- **Admin Activity audit logs** are always on, always free, and record all configuration
  mutations (create, delete, update, set IAM policy). **Data Access audit logs** must be
  explicitly enabled and can be large and expensive for high-traffic services.

- **Log sinks** continuously export matching log entries to GCS (archival), BigQuery
  (analysis), Pub/Sub (streaming), or Log Buckets (extended retention in Logging). Each
  sink creates a writer identity service account — you must grant it write access to the
  destination.

- **GCS sinks export in batches** (approximately hourly). **Pub/Sub sinks** deliver in
  near-real time (seconds to minutes). Choose Pub/Sub when downstream consumers need low
  latency.

- **Log-based metrics** turn log filter matches into Cloud Monitoring counter or
  distribution metrics. They use the metric prefix `logging.googleapis.com/user/` and
  only accumulate data from the time of metric creation forward.

- **BigQuery log sinks** should always use `--use-partitioned-tables`. Always filter on
  `_PARTITIONTIME` in your queries to avoid scanning all partitions and incurring
  unnecessary cost.

- **Uptime checks** are external probes from multiple GCP global locations. They measure
  external availability — not internal health. They require a public endpoint. The alert
  fires when `check_passed` drops below the threshold you configure.

- **Cloud Trace** answers "where is latency in my distributed system?" — use it to find
  slow spans in a request path. **Error Reporting** groups application exceptions
  automatically. **Cloud Profiler** generates CPU/memory flame graphs for running
  production code.

- **SLO error budget** = `100% - SLO target`. When the budget is exhausted, the SLO is
  breached. Burn rate alerting fires when the error budget is being consumed faster than
  sustainable, giving you time to act before the SLO is actually breached.

---

## Cleanup

Run all commands in this section to destroy every resource created in this lab.

```bash
# Check what exists before cleanup
../status.sh 10
```

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
ZONE="us-central1-a"

echo "=== Deleting alerting policies ==="
for POLICY in $(gcloud alpha monitoring policies list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10'" \
  --format="value(name)"); do
  gcloud alpha monitoring policies delete "${POLICY}" \
    --quiet \
    --project="${PROJECT_ID}"
done

echo "=== Deleting notification channels ==="
for CHANNEL in $(gcloud alpha monitoring channels list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10'" \
  --format="value(name)"); do
  gcloud alpha monitoring channels delete "${CHANNEL}" \
    --quiet \
    --project="${PROJECT_ID}"
done

echo "=== Deleting uptime checks ==="
for CHECK in $(gcloud monitoring uptime list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10'" \
  --format="value(name)"); do
  gcloud monitoring uptime delete "${CHECK}" \
    --quiet \
    --project="${PROJECT_ID}"
done

echo "=== Deleting dashboards ==="
for DASHBOARD in $(gcloud monitoring dashboards list \
  --project="${PROJECT_ID}" \
  --filter="displayName:'Lab 10'" \
  --format="value(name)"); do
  gcloud monitoring dashboards delete "${DASHBOARD}" \
    --quiet \
    --project="${PROJECT_ID}"
done

echo "=== Deleting log-based metrics ==="
gcloud logging metrics delete lab10-error-count \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting log sinks ==="
gcloud logging sinks delete lab10-gcs-sink \
  --quiet \
  --project="${PROJECT_ID}"

gcloud logging sinks delete lab10-bq-sink \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting GCS log bucket ==="
gcloud storage rm -r "gs://lab10-logs-${PROJECT_ID}" \
  --quiet

echo "=== Deleting BigQuery dataset ==="
bq rm -r -f "${PROJECT_ID}:lab10_logs"

echo "=== Removing IAM role binding for audit service account ==="
gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:lab10-audit-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/viewer" \
  --quiet 2>/dev/null || echo "Binding already removed."

echo "=== Deleting test service account ==="
gcloud iam service-accounts delete \
  "lab10-audit-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting firewall rule ==="
gcloud compute firewall-rules delete lab10-allow-http \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Firewall rule already removed or did not exist."

echo "=== Deleting GCE instance ==="
gcloud compute instances delete lab10-vm \
  --zone="${ZONE}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Cleanup complete ==="
```

Verify nothing remains:

```bash
../status.sh 10
```

All sections should be empty. If any resources remain, delete them individually
using the resource type and name shown.

---

## Quiz

Test your understanding of the concepts covered in this lab before moving on:

```bash
./quiz.sh
```

Five scenario-based questions covering metric kinds, the Ops Agent, audit logs, log sink
destinations, and log-based metric aligners — matching ACE exam style.
