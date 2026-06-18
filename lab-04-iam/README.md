# Lab 04 — IAM & Service Accounts

> **Cost:** No significant cost. Service accounts and IAM policies are free. If you create KMS keys in optional steps, destroy them promptly ($0.06/month per key version).

---

## Objectives

After completing this lab you will be able to:

- Explain the IAM model: principal, role, resource, and binding
- Distinguish primitive, predefined, and custom roles and know when to use each
- Create and manage service accounts
- Attach a service account to a Compute Engine instance and verify scoped access from inside the VM
- Create a custom IAM role with a minimal permission set
- Apply IAM conditions to restrict access by resource tag or time window
- Impersonate a service account using `gcloud`
- Inspect Cloud Audit Logs to reconstruct who did what and when
- Deliberately trigger permission-denied errors to understand the failure surface
- Apply the principle of least privilege across all of the above

---

## Concepts

### The IAM Model: WHO, WHAT, WHICH

Every access decision in GCP answers three questions:

| Question | IAM term | Examples |
|---|---|---|
| WHO is making the request? | **Principal** | `user:alice@example.com`, `serviceAccount:my-sa@project.iam.gserviceaccount.com` |
| WHAT are they allowed to do? | **Role** (bundle of permissions) | `roles/storage.objectViewer`, `roles/compute.instanceAdmin.v1` |
| WHICH resource does the binding apply to? | **Resource** | project, bucket, VM, secret |

A **policy** is a collection of **bindings**. Each binding ties one or more principals to one role on one resource. There are no explicit deny rules in standard IAM — access is deny-by-default and opened by bindings.

```
Policy on project my-project
├── binding: roles/compute.instanceAdmin.v1
│   └── members: [user:alice@example.com, serviceAccount:deploy-sa@my-project.iam.gserviceaccount.com]
└── binding: roles/storage.objectViewer
    └── members: [group:analysts@example.com]
```

> **ACE exam tip:** GCP IAM has no DENY rules at the basic level (unlike AWS IAM). Access is additive across all bindings. The only way to restrict is to not grant, or to use Org Policy constraints (a separate system). IAM Deny policies are a newer feature but rarely tested at ACE level — know they exist.

---

### Policy Inheritance

GCP resources form a hierarchy: **Organisation → Folder → Project → Resource (bucket, VM, etc.)**.

Policies at a higher level are **inherited** by everything below. A permission granted at the org level applies to every project and every resource inside that org.

```
Organisation  (roles/viewer granted to alice)
└── Folder: Engineering
    └── Project: my-project          ← alice inherits viewer here
        ├── VM: web-server           ← alice inherits viewer here too
        └── Bucket: my-data          ← and here
```

Critical rule: **a child cannot revoke what a parent grants.** If Alice has `roles/editor` at the org level, adding a binding at the project level cannot remove that. This is why the principle of least privilege starts at the top of the hierarchy.

> **ACE exam tip:** If a user appears to have access they shouldn't, check parent resources — the grant may live at a folder or org level. Use `gcloud projects get-iam-policy` but also check `gcloud organizations get-iam-policy` and `gcloud resource-manager folders get-iam-policy`.

---

### Principal Types

| Principal type | Identifier format | Notes |
|---|---|---|
| Google Account | `user:alice@gmail.com` | Individual human user |
| Service Account | `serviceAccount:sa-name@project.iam.gserviceaccount.com` | Non-human identity for workloads |
| Google Group | `group:team@example.com` | Manages access at scale — preferred over individual users |
| Cloud Identity / Workspace domain | `domain:example.com` | All accounts in the domain |
| `allAuthenticatedUsers` | special value | Any authenticated Google account — use carefully |
| `allUsers` | special value | Literally anyone on the internet — only appropriate for public data |

**AWS comparison:** GCP principals map roughly to AWS IAM identities, but GCP has no concept of IAM Users as first-class objects — you manage humans via Google Accounts or Cloud Identity and grant them roles. There is no equivalent to AWS IAM Users with access keys for humans (use Workload Identity or service account keys for programmatic access, and prefer Workload Identity).

---

### Role Types

| Type | Who manages it | Permission granularity | When to use |
|---|---|---|---|
| **Primitive** (`roles/owner`, `roles/editor`, `roles/viewer`) | Google | Extremely broad — touches nearly everything | Never in production. Owner gives billing admin. Legacy only. |
| **Predefined** (`roles/compute.instanceAdmin.v1`, `roles/storage.objectCreator`, etc.) | Google | Fine-grained, curated per service | Default choice for most use cases |
| **Custom** | You | Exactly the permissions you specify | When predefined roles are still too broad for least-privilege |

Primitive roles predate fine-grained IAM and exist for historical reasons. `roles/editor` grants write access to almost every GCP service — granting it is rarely appropriate.

```bash
# List all predefined roles for Compute Engine
gcloud iam roles list --filter="name:roles/compute" --format="table(name,title)"
```

---

### Service Accounts: Two Distinct Concepts

Service accounts are simultaneously:

1. **A principal (identity):** A workload (VM, container, Cloud Function) can run AS the service account, inheriting its roles. This is the "who is making the request" answer.
2. **A resource:** The service account itself has an IAM policy. You can grant a human `roles/iam.serviceAccountUser` on a specific SA, allowing them to act as it.

This dual nature is a common source of confusion.

```
Service Account: deploy-sa@my-project.iam.gserviceaccount.com
│
├── AS A PRINCIPAL: has roles/storage.objectAdmin on bucket my-data
│   → VMs running as this SA can read/write objects in my-data
│
└── AS A RESOURCE: alice has roles/iam.serviceAccountUser on this SA
    → alice can attach this SA to VMs, or impersonate it
```

---

### Service Account Credentials: Avoid JSON Keys

There are four ways a workload authenticates as a service account:

| Method | How it works | Use this when |
|---|---|---|
| **Metadata server (ADC on GCE/GKE)** | VM/pod automatically gets tokens from `169.254.169.254` | Always prefer this on GCP compute |
| **Application Default Credentials (ADC)** | `gcloud auth application-default login` for local dev | Local development only |
| **Workload Identity Federation** | External workloads (GitHub Actions, AWS, Azure) exchange their identity token for a GCP token | CI/CD pipelines, multi-cloud |
| **JSON key file** | Long-lived private key downloaded to disk | Last resort — avoid. Key doesn't expire automatically, can be leaked |

> **ACE exam tip:** JSON service account keys are the #1 source of credential leaks in GCP. The exam tests that you know to prefer the metadata server / ADC / Workload Identity Federation over downloading key files. If asked how to authenticate from a VM, the answer is: attach a service account, use the metadata server.

---

### Service Account Impersonation

A principal with `roles/iam.serviceAccountTokenCreator` on a service account can generate tokens for it. This is **impersonation** and is powerful — use it instead of downloading JSON keys.

```bash
# Illustrative only — do not run yet. Replace with a real service account email from the exercises below.
gcloud storage ls --impersonate-service-account=sa@project.iam.gserviceaccount.com
```

---

### IAM Conditions

IAM conditions let you make bindings **context-aware**. The binding only applies when the condition expression evaluates to true.

Common condition attributes:

| Attribute | Example use case |
|---|---|
| `resource.name` | Restrict to specific buckets or VMs by name prefix |
| `resource.type` | Restrict to a particular resource type |
| `request.time` | Restrict to business hours, or grant temporary access |
| `resource.matchTag()` | Restrict to resources with a specific tag (key/value) |

Conditions use the Common Expression Language (CEL).

---

### Org Policies vs IAM

These are two different enforcement layers that are frequently confused:

| | **IAM** | **Org Policy** |
|---|---|---|
| What it controls | Who can perform actions | What actions are possible at all |
| Scope | Binding on a resource | Constraint applied to org/folder/project |
| Example | Alice can create VMs | Nobody can create VMs in us-east1 |
| Bypassed by owners? | No — but owners can modify policy | No — even org admins can't override a constraint set above them |
| Primary use | Access control | Governance, compliance |

Example org policy constraint: `constraints/compute.restrictCloudSQLInstances` — prevents Cloud SQL from being created in certain regions regardless of what IAM roles a user has.

---

### Cloud Audit Logs

Every meaningful API call in GCP generates an audit log entry. There are three types:

| Log type | What it records | Always on? |
|---|---|---|
| **Admin Activity** | Configuration changes: create VM, modify IAM policy | Yes, always |
| **Data Access** | Read/write of data: list objects, read a secret | No — must enable per service (generates cost) |
| **System Event** | Google-initiated actions: live migration, auto-scaling | Yes, always |

Logs land in Cloud Logging and can be exported to BigQuery, Pub/Sub, or Cloud Storage for retention and analysis.

---

## Setup

This lab requires an active GCP project with billing enabled (covered in Lab 01). No paid resources are created, but you need Owner or IAM Admin permissions to manage IAM policies.

```bash
# Confirm your active account and project
gcloud auth list
gcloud config list project

# Set your project if needed
PROJECT_ID=$(gcloud config get-value project)
echo "Working in project: $PROJECT_ID"

# Enable the IAM and Compute APIs (likely already enabled from earlier labs)
gcloud services enable iam.googleapis.com compute.googleapis.com cloudresourcemanager.googleapis.com
```

Store your own email for use throughout the exercises:

```bash
MY_EMAIL=$(gcloud config get-value account)
echo "Your account: $MY_EMAIL"
```

---

## Exercises

### Exercise 1 — View the Current IAM Policy on the Project

Before granting anything, understand what is already there.

```bash
PROJECT_ID=$(gcloud config get-value project)

# Full IAM policy in YAML
gcloud projects get-iam-policy $PROJECT_ID

# More readable: flat table of member → role bindings
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)"
```

**Expected output (abbreviated — your output may include extra service accounts from prior work in the same project):**

```
ROLE                          MEMBERS
roles/editor                  serviceAccount:...@developer.gserviceaccount.com
roles/owner                   user:your-email@example.com
roles/viewer                  ...
```

Note how primitive roles like `roles/owner` and `roles/editor` appear — these are auto-created by GCP. The default compute service account typically has `roles/editor` which is deliberately broad and should be replaced with least-privilege SAs in production.

```bash
# Check only your own bindings
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  --filter="bindings.members:$MY_EMAIL"
```

---

### Exercise 2 — Grant and Revoke a Predefined Role

Grant a predefined role to your own account (simulating granting to a colleague), then revoke it to observe the change.

```bash
PROJECT_ID=$(gcloud config get-value project)
MY_EMAIL=$(gcloud config get-value account)

# Grant the Cloud Storage viewer role to yourself
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$MY_EMAIL" \
  --role="roles/storage.objectViewer"
```

**Expected output:**

```
Updated IAM policy for project [my-project].
bindings:
- members:
  - user:your-email@example.com
  role: roles/storage.objectViewer
...
```

```bash
# Confirm the binding was added
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  --filter="bindings.role:roles/storage.objectViewer"
```

```bash
# Now revoke it
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="user:$MY_EMAIL" \
  --role="roles/storage.objectViewer"
```

**Expected output:**

```
Updated IAM policy for project [my-project].
```

> **ACE exam tip:** `add-iam-policy-binding` and `remove-iam-policy-binding` are **additive** — they read-modify-write a single binding without overwriting the rest of the policy. Never use `set-iam-policy` with a hand-crafted file unless you intend to replace the entire policy, as you risk removing bindings you didn't intend to touch.

---

### Exercise 3 — Create a Service Account

```bash
PROJECT_ID=$(gcloud config get-value project)

# Create a service account for a hypothetical storage worker
gcloud iam service-accounts create storage-worker-sa \
  --display-name="Storage Worker Service Account" \
  --description="Reads and writes objects in the app data bucket"

# Confirm creation
gcloud iam service-accounts list
```

**Expected output:**

```
DISPLAY NAME                         EMAIL                                                DISABLED
Storage Worker Service Account       storage-worker-sa@my-project.iam.gserviceaccount.com  False
Compute Engine default service acc...  123456789-compute@developer.gserviceaccount.com      False
```

Store the SA email for later exercises:

```bash
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"
echo "Service account: $SA_EMAIL"
```

---

### Exercise 4 — Grant Roles to the Service Account

Grant only the permissions the service account needs — no more.

```bash
PROJECT_ID=$(gcloud config get-value project)
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant Storage Object Admin on the project
# (in production you would scope this to a specific bucket — see below)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectAdmin"
```

**Better practice: scope to a specific bucket, not the whole project.** Create a bucket and bind there:

```bash
BUCKET_NAME="${PROJECT_ID}-lab04-data"

# Create the bucket (using gcloud storage from Lab 03)
gcloud storage buckets create gs://$BUCKET_NAME --location=us-central1

# Grant the SA object admin on just this bucket, not the whole project
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectAdmin"

# Confirm the bucket-level policy
gcloud storage buckets get-iam-policy gs://$BUCKET_NAME
```

**Expected output:**

```
bindings:
- members:
  - serviceAccount:storage-worker-sa@my-project.iam.gserviceaccount.com
  role: roles/storage.objectAdmin
...
```

> **ACE exam tip:** Always prefer resource-level bindings over project-level bindings when the access scope can be narrowed. A service account that only needs to read one bucket should have `roles/storage.objectViewer` on that bucket, not on the project.

---

### Exercise 5 — Attach a Service Account to a VM and Verify Access

This exercise shows how workloads authenticate without key files: the VM runs as the service account and uses the metadata server automatically.

```bash
PROJECT_ID=$(gcloud config get-value project)
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET_NAME="${PROJECT_ID}-lab04-data"

# Create a small VM with the service account attached
gcloud compute instances create lab04-worker \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --service-account=$SA_EMAIL \
  --scopes=cloud-platform \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address

# Wait for the VM to be ready
gcloud compute instances describe lab04-worker \
  --zone=us-central1-a \
  --format="value(status)"
```

**Expected output:** `RUNNING`

Now SSH in and verify the service account identity and storage access:

```bash
gcloud compute ssh lab04-worker --zone=us-central1-a --tunnel-through-iap
```

Inside the VM, run:

```bash
# Who am I? (queries the metadata server)
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email"
```

**Expected output:**

```
storage-worker-sa@my-project.iam.gserviceaccount.com
```

```bash
# Use gcloud inside the VM — it automatically uses the attached SA
gcloud auth list
```

**Expected output:**

```
ACTIVE  ACCOUNT
*       storage-worker-sa@my-project.iam.gserviceaccount.com
```

```bash
# Upload a test file to prove the SA can write to the bucket
echo "hello from the VM" > /tmp/test.txt
BUCKET_NAME="YOUR_PROJECT_ID-lab04-data"   # substitute your project ID
gcloud storage cp /tmp/test.txt gs://$BUCKET_NAME/test.txt
gcloud storage ls gs://$BUCKET_NAME/
```

**Expected output:**

```
gs://my-project-lab04-data/test.txt
```

Type `exit` to leave the SSH session.

> **ACE exam tip:** The `--scopes=cloud-platform` flag grants the VM permission to use all GCP APIs that the attached service account has roles for. Scopes are a legacy access control layer on top of IAM — if you set `cloud-platform`, IAM roles are the sole access control. Avoid setting narrow scopes (like `storage-ro`) because they can silently block access even when the SA has the right IAM role.

---

### Exercise 6 — Deliberate Failure: Try an Action Without Permission

Understanding denied access is as important as granting it. This exercise intentionally fails to show what the error looks like and how to diagnose it.

Create a second service account with no roles:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud iam service-accounts create no-perms-sa \
  --display-name="No Permissions SA" \
  --description="Intentionally has no roles"

NO_PERMS_SA="no-perms-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

Create a VM running as this unprivileged SA:

```bash
gcloud compute instances create lab04-noperms \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --service-account=$NO_PERMS_SA \
  --scopes=cloud-platform \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --no-address
```

SSH into it and attempt to access Cloud Storage:

```bash
gcloud compute ssh lab04-noperms --zone=us-central1-a --tunnel-through-iap
```

Inside the VM:

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="${PROJECT_ID}-lab04-data"
gcloud storage ls gs://$BUCKET_NAME/
```

**Expected output (failure is the goal):**

```
ERROR: (gcloud.storage.ls) HTTPError 403: no-perms-sa@my-project.iam.gserviceaccount.com
does not have storage.objects.list access to the Google Cloud Storage bucket.
Permission 'storage.objects.list' denied on resource (or it may not exist).
```

The error message tells you exactly which permission is missing and on which resource. This is the diagnostic path: look at the error, find the missing permission, look up which predefined role grants it, bind that role to the principal.

Exit the VM with `exit`.

---

### Exercise 7 — Create a Custom IAM Role

When predefined roles are still too broad, define your own. Here you create a role that allows listing and reading objects in Cloud Storage, but not writing or deleting.

```bash
PROJECT_ID=$(gcloud config get-value project)

# First, explore what permissions exist for storage
gcloud iam list-testable-permissions \
  --filter="name:storage.objects" \
  cloudresourcemanager.googleapis.com/projects/$PROJECT_ID \
  --format="table(name,stage)"
```

**Expected output (excerpt):**

```
NAME                          STAGE
storage.objects.create        GA
storage.objects.delete        GA
storage.objects.get           GA
storage.objects.getIamPolicy  GA
storage.objects.list          GA
storage.objects.setIamPolicy  GA
storage.objects.update        GA
```

Create a custom role with only read permissions:

```bash
gcloud iam roles create storageReadOnly \
  --project=$PROJECT_ID \
  --title="Storage Read Only" \
  --description="Read and list objects only — no write, no delete" \
  --permissions="storage.objects.get,storage.objects.list,storage.buckets.get" \
  --stage=GA
```

**Expected output:**

```
Created role [storageReadOnly].
description: Read and list objects only — no write, no delete
etag: BwX...
includedPermissions:
- storage.buckets.get
- storage.objects.get
- storage.objects.list
name: projects/my-project/roles/storageReadOnly
stage: GA
title: Storage Read Only
```

Grant your custom role to the storage worker SA:

```bash
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET_NAME="${PROJECT_ID}-lab04-data"

gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
  --member="serviceAccount:$SA_EMAIL" \
  --role="projects/$PROJECT_ID/roles/storageReadOnly"
```

List all custom roles in the project:

```bash
gcloud iam roles list --project=$PROJECT_ID
```

**Expected output:**

```
NAME                                    TITLE              STAGE
projects/my-project/roles/storageReadOnly  Storage Read Only  GA
```

> **ACE exam tip:** Custom roles reference permissions by their internal permission string (e.g. `storage.objects.get`), not by role names. The exam may ask you to identify which permission is needed for a task. Know the pattern: `service.resource.verb` — e.g. `compute.instances.start`, `bigquery.datasets.create`, `iam.serviceAccounts.actAs`.

---

### Exercise 8 — IAM Conditions: Restrict Access by Resource Tag

IAM conditions let you make a binding active only when conditions are met. Here you grant access only to buckets that carry a specific resource tag.

First, create a tag key and value (requires the Resource Manager API):

```bash
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Create a tag key scoped to the project
gcloud resource-manager tags keys create environment \
  --parent=projects/$PROJECT_ID \
  --short-name=environment \
  --description="Environment tag for IAM conditions"
```

**Expected output:**

```
createTime: '...'
name: tagKeys/123456789012
namespacedName: my-project/environment
parent: projects/123456789012
shortName: environment
```

```bash
# Create a tag value "production"
TAG_KEY_ID=$(gcloud resource-manager tags keys describe my-project/environment \
  --format="value(name)")

gcloud resource-manager tags values create production \
  --parent=$TAG_KEY_ID \
  --short-name=production \
  --description="Production environment"
```

Now grant a role with a condition that restricts it to resources tagged `environment=production`:

```bash
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"
TAG_KEY_NS="$PROJECT_ID/environment"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectViewer" \
  --condition="expression=resource.matchTag('${TAG_KEY_NS}/production'),title=ProductionOnly,description=Access only to production-tagged resources"
```

**Expected output:**

```
Updated IAM policy for project [my-project].
bindings:
...
- condition:
    description: Access only to production-tagged resources
    expression: resource.matchTag('my-project/environment/production')
    title: ProductionOnly
  members:
  - serviceAccount:storage-worker-sa@my-project.iam.gserviceaccount.com
  role: roles/storage.objectViewer
```

View the conditional binding:

```bash
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.condition.title,bindings.members)" \
  --filter="bindings.condition:*"
```

> **ACE exam tip:** IAM conditions make a binding **context-aware** but do not replace the need for a binding. If you want time-based access (e.g. only 09:00–17:00), use `request.time` in the condition expression. This is useful for break-glass access scenarios where you grant access for a limited time window.

---

### Exercise 9 — Impersonate a Service Account

Impersonation lets you act as a service account without downloading a key file. You need `roles/iam.serviceAccountTokenCreator` on the target SA.

```bash
PROJECT_ID=$(gcloud config get-value project)
MY_EMAIL=$(gcloud config get-value account)
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant yourself token creator on the SA (binding on the SA resource, not the project)
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --member="user:$MY_EMAIL" \
  --role="roles/iam.serviceAccountTokenCreator"
```

**Expected output:**

```
Updated IAM policy for service account [storage-worker-sa@my-project.iam.gserviceaccount.com].
bindings:
- members:
  - user:your-email@example.com
  role: roles/iam.serviceAccountTokenCreator
```

Now run a command impersonating the SA:

```bash
BUCKET_NAME="${PROJECT_ID}-lab04-data"

# List objects as the SA, without any key file
gcloud storage ls gs://$BUCKET_NAME/ \
  --impersonate-service-account=$SA_EMAIL
```

**Expected output:**

```
WARNING: This command is using service account impersonation. All API calls will be executed as [storage-worker-sa@my-project.iam.gserviceaccount.com].
gs://my-project-lab04-data/test.txt
```

The warning is intentional — it reminds you that impersonation is in effect. Notice no key file was created or downloaded.

```bash
# You can also impersonate for an entire gcloud session
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=$SA_EMAIL
gcloud auth list   # shows the impersonated account
gcloud storage ls gs://$BUCKET_NAME/

# Clear impersonation
unset CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
```

> **ACE exam tip:** `roles/iam.serviceAccountUser` allows a principal to **attach** a service account to a VM or other resource. `roles/iam.serviceAccountTokenCreator` allows a principal to **generate tokens** for the SA (impersonation). These are different roles with different risk profiles — token creator is more powerful.

---

### Exercise 10 — View Audit Logs for IAM Changes

Every IAM policy change generates an Admin Activity audit log entry. Use Cloud Logging to find them.

```bash
PROJECT_ID=$(gcloud config get-value project)

# Find IAM policy changes in the last hour
gcloud logging read \
  'protoPayload.serviceName="iam.googleapis.com" OR protoPayload.methodName=~"SetIamPolicy"' \
  --project=$PROJECT_ID \
  --freshness=1h \
  --format="table(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail,protoPayload.resourceName)"
```

**Expected output:**

```
TIMESTAMP                       METHOD_NAME                       PRINCIPAL_EMAIL               RESOURCE_NAME
2026-06-17T10:23:41Z  SetIamPolicy  your-email@example.com  projects/my-project
2026-06-17T10:21:15Z  google.iam.v1.IAM.CreateServiceAccount  your-email@example.com  projects/my-project
```

Find logs specifically for the service account you created:

```bash
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud logging read \
  "protoPayload.request.serviceAccount.email=\"$SA_EMAIL\" OR protoPayload.resourceName=\"projects/$PROJECT_ID/serviceAccounts/$SA_EMAIL\"" \
  --project=$PROJECT_ID \
  --freshness=2h \
  --limit=10 \
  --format="json" | python3 -m json.tool | grep -E '"timestamp|methodName|principalEmail"'
```

Check audit logs for any access by a specific principal:

```bash
MY_EMAIL=$(gcloud config get-value account)

gcloud logging read \
  "protoPayload.authenticationInfo.principalEmail=\"$MY_EMAIL\" protoPayload.methodName=~\"SetIamPolicy\"" \
  --project=$PROJECT_ID \
  --freshness=2h \
  --format="table(timestamp,protoPayload.methodName,protoPayload.resourceName)"
```

> **ACE exam tip:** Admin Activity logs are always on and always free. You cannot disable them. They are the primary forensic tool for security incidents: "who changed this IAM policy and when?" is always answerable from Admin Activity logs. Data Access logs (who read what data) are separate, off by default, and generate cost when enabled.

---

### Exercise 11 — Explore the Principle of Least Privilege in Practice

Compare what access the default Compute Engine SA has versus what it should have:

```bash
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
DEFAULT_COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Check what roles the default compute SA has
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  --filter="bindings.members:$DEFAULT_COMPUTE_SA"
```

**Expected output:**

```
ROLE            MEMBERS
roles/editor    serviceAccount:123456789-compute@developer.gserviceaccount.com
```

`roles/editor` gives this SA write access to nearly every GCP service. Any VM that uses the default SA (and has `cloud-platform` scope) can read/write secrets, modify databases, reconfigure networking, and more. This is the default because Google created it for convenience, but it violates least privilege.

The correct approach for production:

```bash
# 1. Create a dedicated SA per workload
gcloud iam service-accounts create webapp-sa \
  --display-name="Web Application Service Account"

# 2. Grant only what that workload needs
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:webapp-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

# 3. Attach that SA to the instance (not the default)
# gcloud compute instances create ... --service-account=webapp-sa@...

# You can also check what permissions a role actually contains
gcloud iam roles describe roles/cloudsql.client \
  --format="table(includedPermissions[])"
```

**Expected output (excerpt):**

```
INCLUDED_PERMISSIONS
cloudsql.backupRuns.get
cloudsql.backupRuns.list
cloudsql.instances.connect
cloudsql.instances.get
cloudsql.instances.list
```

This confirms `roles/cloudsql.client` gives only connection permissions — not the ability to create or delete databases.

---

## Key Takeaways

- IAM access is **additive and deny-by-default**: access is opened by bindings, not explicitly denied. The only native deny mechanism is IAM Deny policies (advanced) or simply not granting.
- **Policy inheritance flows downward**: a role granted at the organisation or folder level applies to every child resource. Children cannot revoke parent grants.
- **Primitive roles are legacy**: `roles/editor` and `roles/owner` are too broad for production. Use predefined or custom roles.
- **Service accounts serve dual roles**: they are an identity (principal) that workloads run as, and they are a resource that has its own IAM policy controlling who can use or impersonate them.
- **Never use JSON key files** if you can avoid it. Prefer the metadata server (on GCE), ADC (local dev), or Workload Identity Federation (external workloads).
- **`roles/iam.serviceAccountUser`** lets a principal attach a SA to a resource. **`roles/iam.serviceAccountTokenCreator`** lets a principal impersonate a SA. Both are sensitive roles.
- **`--scopes=cloud-platform`** on a GCE instance means IAM is the sole access gate. Narrow scopes can silently block access even when IAM grants it.
- **IAM conditions** use Common Expression Language (CEL) to make bindings context-aware: restrict by resource tag, time window, IP range, etc.
- **Org Policies are not IAM**: org policies restrict what can be done (governance), IAM restricts who can do it (access control). Both are needed in a secure environment.
- **Admin Activity audit logs are always on and always free**. They record every IAM policy change. Use Cloud Logging to query them. Data Access logs must be explicitly enabled and incur cost.
- **Principle of least privilege**: grant the minimum role, at the narrowest resource scope, for the shortest time necessary. Bucket-level bindings beat project-level bindings when access can be scoped.
- On the ACE exam: any question about "how do VMs authenticate to GCP APIs" has the answer: attach a service account, use the metadata server. JSON keys are the wrong answer.

---

## Cleanup

Run these commands to remove all resources created in this lab. Order matters — delete VMs before SAs, bindings before roles.

```bash
PROJECT_ID=$(gcloud config get-value project)
MY_EMAIL=$(gcloud config get-value account)
SA_EMAIL="storage-worker-sa@${PROJECT_ID}.iam.gserviceaccount.com"
NO_PERMS_SA="no-perms-sa@${PROJECT_ID}.iam.gserviceaccount.com"
BUCKET_NAME="${PROJECT_ID}-lab04-data"

# 1. Delete the VMs
gcloud compute instances delete lab04-worker lab04-noperms \
  --zone=us-central1-a \
  --quiet

# 2. Remove IAM bindings from the project for the storage worker SA
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectAdmin"

# Remove conditional binding (requires --condition flag or --all-conditions)
gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.objectViewer" \
  --all

# Remove token creator binding from yourself on the SA
gcloud iam service-accounts remove-iam-policy-binding $SA_EMAIL \
  --member="user:$MY_EMAIL" \
  --role="roles/iam.serviceAccountTokenCreator"

# 3. Delete the service accounts
gcloud iam service-accounts delete $SA_EMAIL --quiet
gcloud iam service-accounts delete $NO_PERMS_SA --quiet
gcloud iam service-accounts delete \
  "webapp-sa@${PROJECT_ID}.iam.gserviceaccount.com" --quiet 2>/dev/null || true

# 4. Delete the custom IAM role
gcloud iam roles delete storageReadOnly --project=$PROJECT_ID

# 5. Delete the bucket and all objects in it
gcloud storage rm -r gs://$BUCKET_NAME

# 6. Delete the resource manager tags (values before keys)
TAG_VALUE_ID=$(gcloud resource-manager tags values describe \
  "${PROJECT_ID}/environment/production" --format="value(name)" 2>/dev/null)
if [ -n "$TAG_VALUE_ID" ]; then
  gcloud resource-manager tags values delete $TAG_VALUE_ID --quiet
fi

TAG_KEY_ID=$(gcloud resource-manager tags keys describe \
  "${PROJECT_ID}/environment" --format="value(name)" 2>/dev/null)
if [ -n "$TAG_KEY_ID" ]; then
  gcloud resource-manager tags keys delete $TAG_KEY_ID --quiet
fi

# 7. Verify nothing remains
gcloud compute instances list --filter="name~lab04"
gcloud iam service-accounts list --filter="email~storage-worker-sa OR email~no-perms-sa"
gcloud storage buckets list --filter="name~lab04-data"
gcloud iam roles list --project=$PROJECT_ID
```

**Expected final output:** all four verification commands return empty results.