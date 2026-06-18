# Lab 01 — GCP Foundations & gcloud CLI

> **Cost:** This lab creates no billable resources. All exercises use free-tier operations (project metadata, API queries, configuration). Safe to run on any account.

---

## Objectives

After completing this lab you will be able to:

- Describe the GCP resource hierarchy (organisation → folder → project → resource) and explain why it matters for IAM inheritance
- Create and configure a GCP project entirely from the CLI
- Authenticate with `gcloud` and explain the difference between user credentials, service account keys, Application Default Credentials (ADC), and Workload Identity
- Enable APIs and explain why every GCP service requires explicit enablement
- Configure `gcloud` defaults (project, region, zone) and create named configurations to switch between environments
- Explore the resource hierarchy using `gcloud` commands
- Explain how billing accounts attach to projects
- Distinguish between global, regional, and zonal resources and give exam-ready examples of each
- Explain the difference between labels (billing metadata) and tags (network firewall selectors)

---

## Concepts

### 1. The GCP Resource Hierarchy

GCP organises everything in a strict parent–child tree. Understanding this tree is foundational because **IAM policies are inherited downward** — a permission granted at a parent node is automatically available to all children.

```
Organisation (your company domain, e.g. container-solutions.com)
 └── Folder  (e.g. "Production", "Development", "Shared-Services")
      └── Project  (the fundamental billing and API boundary)
           └── Resources  (VMs, buckets, databases, etc.)
```

**Why this matters for the exam:**

- A policy binding on a Folder grants that role to all projects inside that folder. You cannot block inherited roles — you can only add more roles at lower levels (IAM is additive, never subtractive via inheritance).
- Every resource belongs to exactly one project. Projects are the unit of billing, quota, and API enablement.
- The Organisation node is created automatically when you verify a domain with Google Workspace or Cloud Identity. Without it you still have projects — they just float at the root level.

> **ACE Exam Tip:** Questions about "who has access to all projects in a business unit" are answered by attaching a role to a **Folder**, not granting it on every project individually. Folders are the recommended way to mirror your organisational structure.

**Comparison with AWS:**

| GCP | AWS | Purpose |
|-----|-----|---------|
| Organisation | AWS Organisation (root) | Top-level governance boundary |
| Folder | Organisational Unit (OU) | Grouping of accounts/projects |
| Project | AWS Account | Billing boundary, isolation unit |
| Resource | Resource (EC2 instance, S3 bucket) | The thing you actually use |

The key difference: in AWS, an account is a hard isolation boundary and moving resources between accounts is painful. In GCP, projects are lighter-weight — you can have dozens of projects under one billing account and resources can share VPC networks across projects via Shared VPC.

---

### 2. gcloud CLI Structure

Every `gcloud` command follows a consistent grammar:

```
gcloud <group> <sub-group> <verb> [POSITIONAL] [--flags]
```

Examples that demonstrate the pattern:

```bash
# group=compute, sub-group=instances, verb=list
gcloud compute instances list

# group=projects, verb=describe
gcloud projects describe my-project-id

# group=iam, sub-group=service-accounts, verb=create
gcloud iam service-accounts create my-sa --display-name="My SA"

# --help works at every level
gcloud compute --help
gcloud compute instances --help
gcloud compute instances create --help
```

Common global flags you will use constantly:

| Flag | Purpose |
|------|---------|
| `--project` | Override the active project for this one command |
| `--format` | Output format: `json`, `yaml`, `table`, `value(field)` |
| `--quiet` / `-q` | Skip confirmation prompts (useful in scripts) |
| `--filter` | Server-side filtering (faster than piping to grep) |
| `--limit` | Cap the number of results returned |

---

### 3. gcloud Configurations

A **configuration** is a named set of properties (project, account, region, zone, etc.) that you can activate with a single command. Think of it as a profile.

```bash
# List all configurations
gcloud config configurations list

# Create a new one
gcloud config configurations create dev-project

# Switch to it
gcloud config configurations activate dev-project

# Set properties inside the active configuration
gcloud config set project my-dev-project-id
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-a
gcloud config set account dev@example.com

# See what is currently set
gcloud config list
```

Without named configurations you would pass `--project`, `--region`, and `--zone` to every single command. Configurations eliminate that noise when working across multiple projects.

> **ACE Exam Tip:** The default configuration is literally named `default`. You cannot delete it. A property set in a configuration is scoped to that configuration only — activating a different configuration immediately changes your active context.

---

### 4. Authentication: Four Ways to Prove Identity

This is one of the most exam-tested topics in Domain 1 and Domain 5.

| Method | When to use | Command |
|--------|-------------|---------|
| **User credentials** | Interactive development on your laptop | `gcloud auth login` |
| **Application Default Credentials (ADC)** | Code running locally that calls GCP APIs | `gcloud auth application-default login` |
| **Service account key file** | Workloads outside GCP that need a long-lived credential (avoid when possible) | `gcloud auth activate-service-account --key-file=key.json` |
| **Workload Identity / Attached SA** | Code running on GCP (VM, GKE pod, Cloud Run) — no key file needed | Automatic via metadata server |

**User credentials vs ADC — why two?**

`gcloud auth login` stores a credential that `gcloud` itself uses to make API calls on your behalf (creating VMs, listing buckets, etc.).

`gcloud auth application-default login` stores a *separate* credential that client libraries (Python `google-cloud-storage`, Go `cloud.google.com/go`, etc.) use when your own code calls GCP APIs. They are different tokens stored in different places.

```bash
# Where credentials are stored
cat ~/.config/gcloud/credentials.db        # user credentials (gcloud)
cat ~/.config/gcloud/application_default_credentials.json  # ADC
```

**Why avoid service account key files?**

A JSON key file is a long-lived secret that never expires unless you rotate it. If it leaks, an attacker has permanent access until you manually revoke it. Workload Identity (on GKE) and attached service accounts (on VMs/Cloud Run) give the workload a short-lived, auto-rotating credential with no key file.

> **ACE Exam Tip:** The exam will ask which authentication method is "most secure" or "best practice" for a VM running in GCP. The answer is always **attach a service account to the VM** (Workload Identity or attached SA) — never a key file, never user credentials on a server.

---

### 5. APIs: Why They Must Be Enabled

GCP does not activate every service by default. Before you can create a Cloud SQL instance, send a Pub/Sub message, or deploy to Cloud Run, you must enable that service's API on your project.

**Why?**

- **Billing guardrail:** You cannot be billed for a service you have not explicitly enabled.
- **Audit surface:** Enables API-level audit logging for that service.
- **Quota tracking:** Per-service quotas only apply once the API is enabled.

APIs are identified by a service name, not a friendly name:

| Friendly Name | API Service Name |
|---------------|-----------------|
| Compute Engine | `compute.googleapis.com` |
| Cloud Storage | `storage.googleapis.com` |
| Cloud Run | `run.googleapis.com` |
| Kubernetes Engine | `container.googleapis.com` |
| Cloud SQL | `sqladmin.googleapis.com` |
| Cloud Build | `cloudbuild.googleapis.com` |
| Secret Manager | `secretmanager.googleapis.com` |

```bash
# Enable one API
gcloud services enable compute.googleapis.com

# Enable multiple at once
gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  run.googleapis.com

# List enabled APIs
gcloud services list --enabled

# List available (but not yet enabled) APIs
gcloud services list --available --filter="name:google"
```

---

### 6. Regions, Zones, and Resource Scope

A **region** is a geographic area (e.g. `europe-west2` = London). Each region contains two or more **zones** (e.g. `europe-west2-a`, `europe-west2-b`, `europe-west2-c`). Zones are independent failure domains within a region — they have separate power, cooling, and network.

**How to choose a region:**

1. **Latency** — pick the region closest to your users
2. **Data residency** — regulatory requirements may restrict which countries data can reside in
3. **Service availability** — not all services are available in all regions (`gcloud compute regions describe europe-west2`)
4. **Price** — pricing varies slightly by region

**Global, regional, and zonal resources — exam-critical table:**

| Scope | Examples | What it means |
|-------|----------|---------------|
| **Global** | VPC networks, firewall rules, Cloud Load Balancers (global), IAM policies, images | Available in all regions simultaneously |
| **Regional** | Regional MIGs, Cloud NAT, regional IP addresses, GCS regional buckets, Cloud SQL | Tied to one region, replicated across its zones |
| **Zonal** | VM instances, persistent disks, zonal GKE node pools | Tied to a single zone; zone failure = resource unavailable |

> **ACE Exam Tip:** A persistent disk (PD) is **zonal**. If you want a disk a VM in zone A can share with a VM in zone B, you need a different approach (like Cloud Filestore, which is regional, or GCS). Standard PDs cannot be attached to a VM in a different zone.

**Comparison with AWS:**

| GCP | AWS | Notes |
|-----|-----|-------|
| Region (`europe-west2`) | Region (`eu-west-2`) | Essentially the same concept |
| Zone (`europe-west2-a`) | Availability Zone (`eu-west-2a`) | Same concept, different naming |
| Global VPC | VPC (regional by default, but spans AZs) | GCP VPCs are truly global; AWS VPCs are regional |

---

### 7. Labels vs Tags

These two terms are used very differently in GCP, and the exam exploits this confusion.

| | Labels | Tags |
|-|--------|------|
| **Purpose** | Metadata for organisation, cost allocation, and filtering | Targeting network firewall rules and routes |
| **Format** | Key-value pairs (`env=prod`, `team=platform`) | String identifiers (`web-server`, `allow-ssh`) |
| **Applied to** | Almost any resource (VMs, disks, buckets, etc.) | VM instances (network tags), or Tag Manager (resource tags) |
| **Billing** | Yes — you can break down costs by label | No |
| **IAM effect** | None (labels are purely informational) | None for network tags; resource tags via Tag Manager can condition IAM |
| **Max per resource** | 64 key-value pairs | 64 network tags |

```bash
# Adding a label to a VM (covered in Lab 02, shown here for context)
gcloud compute instances add-labels my-vm \
  --labels=env=dev,team=platform \
  --zone=europe-west2-a

# Network tags are set at instance creation or with update
gcloud compute instances add-tags my-vm \
  --tags=web-server,allow-health-check \
  --zone=europe-west2-a
```

> **ACE Exam Tip:** If a question asks "how do you apply a firewall rule only to certain VMs", the answer is **network tags**. If it asks "how do you track which team owns which resource for billing", the answer is **labels**.

---

## Setup

### Prerequisites

Complete the **GCP Project Setup** section in the [root README](../README.md) before starting this lab. That setup creates your course-wide project, links billing, and enables all core APIs — you do not need to repeat those steps here.

### Verify your gcloud installation

```bash
gcloud version
```

Expected output:

```
Google Cloud SDK 480.0.0
bq 2.1.11
core 2024.04.19
gcloud-crc32c 1.0.0
gsutil 5.29
```

The version numbers will differ — what matters is that the command runs without error.

---

## Exercises

### Exercise 1 — Authenticate and Inspect Your Identity

Before creating any resources, authenticate and understand what credentials you have.

```bash
# Authenticate interactively — this opens a browser
gcloud auth login
```

Expected output (after browser flow completes):

```
You are now logged in as [your-email@gmail.com].
Your current project is [None].  You can change this setting by running:
  $ gcloud config set project PROJECT_ID
```

```bash
# Confirm which account is active
gcloud auth list
```

Expected output:

```
                     Credentialed Accounts
ACTIVE  ACCOUNT
*       your-email@gmail.com

To set the active account, run:
    $ gcloud config set account `ACCOUNT`
```

```bash
# Also set up ADC so local code can call GCP APIs
gcloud auth application-default login
```

```bash
# Confirm ADC is set
gcloud auth application-default print-access-token | head -c 50
```

You should see the beginning of a long token string. If you see an error like `Could not automatically determine credentials`, ADC is not set up.

**What just happened?** You now have two separate credentials:

- `~/.config/gcloud/credentials.db` — used by `gcloud` commands
- `~/.config/gcloud/application_default_credentials.json` — used by GCP client libraries in your code

---

> **What you already did in course setup:** You created a project, linked a billing account, and enabled all course APIs — run the commands below to inspect that state and understand what each step did.

### Exercise 2 — Inspect Your Project and Billing

The course setup created your project. Let's examine the three identifiers GCP assigns to every project.

```bash
# Load the project from your active gcloud config
PROJECT_ID=$(gcloud config get-value project)

# Describe the project — note the three distinct identifiers
gcloud projects describe $PROJECT_ID
```

Expected output:

```
createTime: '2024-06-17T10:30:00.000Z'
lifecycleState: ACTIVE
name: GCP ACE Labs (yourname)
projectId: gcp-ace-yourname
projectNumber: '123456789012'
```

The three identifiers:

- **Project ID** (`gcp-ace-yourname`) — you chose this; globally unique; immutable after creation
- **Project name** (`GCP ACE Labs (yourname)`) — human-readable; not unique; changeable
- **Project number** (`123456789012`) — assigned by GCP; numeric; immutable; used in some API URLs

> **ACE Exam Tip:** The project **ID** and project **number** are both permanent and cannot be changed. The project **name** can be changed. Some GCP APIs refer to projects by number in their URLs even when you specify by ID.

```bash
# Confirm billing is linked
gcloud billing projects describe $PROJECT_ID
```

Expected output:

```
billingAccountName: billingAccounts/01ABCD-EF2345-678901
billingEnabled: true
name: projects/gcp-ace-yourname/billingInfo
projectId: gcp-ace-yourname
```

> **ACE Exam Tip:** The exam may ask what prevents a user from creating a VM even though they have the `roles/compute.admin` role. A common answer: **billing is not enabled on the project**.

---

### Exercise 3 — Inspect Enabled APIs

The course setup enabled all APIs you will need. Let's see what that looks like and understand what would happen without it.

```bash
# List currently enabled APIs
gcloud services list --enabled
```

You should see ~20 APIs including `compute.googleapis.com`, `container.googleapis.com`, `run.googleapis.com`, and others enabled during course setup.

**Deliberately break it** — see what happens when an API is not enabled:

```bash
# Disable compute temporarily
gcloud services disable compute.googleapis.com --force

# Try to list instances (will fail)
gcloud compute instances list
```

Expected error:

```
ERROR: (gcloud.compute.instances.list) PERMISSION_DENIED: Compute Engine API has not
been used in project gcp-ace-... before or it is disabled. Enable it by visiting
https://console.developers.google.com/apis/api/compute.googleapis.com/overview?project=...
```

```bash
# Re-enable it
gcloud services enable compute.googleapis.com
```

---

### Exercise 4 — Configure gcloud Defaults

Rather than passing `--project`, `--region`, and `--zone` to every command, set them as defaults in your configuration.

```bash
# See the current state of the default configuration
gcloud config list
```

```bash
# Set your project, region, and zone
gcloud config set project $PROJECT_ID
gcloud config set compute/region europe-west2
gcloud config set compute/zone europe-west2-a
```

```bash
# Verify
gcloud config list
```

Expected output:

```
[compute]
region = europe-west2
zone = europe-west2-a
[core]
account = your-email@gmail.com
disable_usage_reporting = True
project = gcp-ace-yourname

Your active configuration is: [default]
```

Your output may include additional fields such as `disable_usage_reporting` (set when you opted out of anonymous SDK telemetry during installation) or `pass_credentials_to_gsutil`. These are harmless — `gcloud config list` shows every property that has been explicitly set, regardless of which command set it.

```bash
# You can also get individual values
gcloud config get-value project
gcloud config get-value compute/region
gcloud config get-value compute/zone
```

```bash
# Store them in shell variables for use in commands below
PROJECT_ID=$(gcloud config get-value project)
REGION=$(gcloud config get-value compute/region)
ZONE=$(gcloud config get-value compute/zone)

echo "Project : $PROJECT_ID"
echo "Region  : $REGION"
echo "Zone    : $ZONE"
```

---

### Exercise 5 — Explore Regions and Zones

Before choosing a region for your workloads, understand what is available and what each region offers.

```bash
# List all regions
gcloud compute regions list
```

Expected output (truncated):

```
NAME                     CPUS  DISKS_GB  ADDRESSES  RESERVED_ADDRESSES  STATUS  TURNDOWN_DATE
africa-south1            0/24  0/4096    0/8        0/8                 UP
asia-east1               0/24  0/4096    0/8        0/8                 UP
asia-east2               0/24  0/4096    0/8        0/8                 UP
...
europe-west2             0/24  0/4096    0/8        0/8                 UP
...
```

```bash
# Get detailed info about your chosen region, including available zones and services
gcloud compute regions describe $REGION
```

```bash
# List zones in your region only
gcloud compute zones list --filter="region:($REGION)"
```

Expected output:

```
NAME             REGION        STATUS  NEXT_MAINTENANCE  TURNDOWN_DATE
europe-west2-a   europe-west2  UP
europe-west2-b   europe-west2  UP
europe-west2-c   europe-west2  UP
```

```bash
# List available machine types in your zone (these are the VM sizes)
gcloud compute machine-types list \
  --filter="zone:($ZONE)" \
  --format="table(name,guestCpus,memoryMb)" | head -20
```

Expected output (first 20 rows):

```
NAME            CPUS  MEMORY_GB
c2-standard-16  16    64.00
c2-standard-30  30    120.00
c2-standard-4   4     16.00
c2-standard-60  60    240.00
c2-standard-8   8     32.00
e2-highcpu-16   16    16.00
e2-highcpu-2    2     2.00
e2-highcpu-32   32    32.00
...
```

```bash
# Check region-specific pricing differences by looking at available resources
# List disk types available in your zone
gcloud compute disk-types list --filter="zone:($ZONE)"
```

Expected output:

```
NAME                  ZONE            VALID_DISK_SIZES
hyperdisk-balanced    europe-west2-a  4GB-65536GB
hyperdisk-extreme     europe-west2-a  64GB-65536GB
hyperdisk-ml          europe-west2-a  4GB-65536GB
hyperdisk-throughput  europe-west2-a  2048GB-32768GB
local-ssd             europe-west2-a  375GB-375GB
pd-balanced           europe-west2-a  10GB-65536GB
pd-extreme            europe-west2-a  500GB-65536GB
pd-ssd                europe-west2-a  10GB-65536GB
pd-standard           europe-west2-a  10GB-65536GB
```

> **ACE Exam Tip:** `pd-standard` (HDD) is cheapest but lowest IOPS. `pd-ssd` is higher performance. `pd-balanced` is the recommended default — SSD performance at lower cost. `pd-extreme` is for the highest-throughput databases. You will use these in Lab 02.

---

### Exercise 6 — Create and Switch Between Named Configurations

Configurations let you maintain separate contexts for different projects, accounts, or environments without re-running `gcloud config set` every time you switch.

```bash
# See current configurations
gcloud config configurations list
```

Expected output:

```
NAME     IS_ACTIVE  ACCOUNT                   PROJECT                    COMPUTE_DEFAULT_ZONE  COMPUTE_DEFAULT_REGION
default  True       your-email@gmail.com      gcp-ace-yourname           europe-west2-a        europe-west2
```

```bash
# Create a second configuration simulating a "production" environment
gcloud config configurations create prod-environment
```

Expected output:

```
Created [prod-environment].
Activated [prod-environment].
```

```bash
# Notice you are now in the new (empty) configuration
gcloud config list
```

Expected output:

```
[core]
account = (unset)

Your active configuration is: [prod-environment]
```

```bash
# Set properties for this configuration
gcloud config set account $(gcloud auth list --format="value(account)" --limit=1)
gcloud config set project $PROJECT_ID
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

```bash
# Switch back to default
gcloud config configurations activate default
```

Expected output:

```
Activated [default].
```

```bash
# Confirm you are back to europe-west2
gcloud config get-value compute/region
```

Expected output:

```
europe-west2
```

```bash
# Switch to prod and confirm the region changed
gcloud config configurations activate prod-environment
gcloud config get-value compute/region
```

Expected output:

```
us-central1
```

```bash
# Switch back to default for the rest of the lab
gcloud config configurations activate default
```

**Tip for teams:** Store your configurations in a shell script or dotfile so new team members can reproduce your exact `gcloud` context. Configuration files live in `~/.config/gcloud/configurations/`.

---

### Exercise 7 — Explore the Resource Hierarchy and IAM Preview

Explore how the resource hierarchy works from the CLI, and get a preview of IAM bindings that will be covered in depth in Lab 04.

```bash
# Describe your project — note the projectNumber field
gcloud projects describe $PROJECT_ID
```

```bash
# List all projects you have access to
gcloud projects list
```

Expected output:

```
PROJECT_ID               NAME                  PROJECT_NUMBER
gcp-ace-yourname         GCP ACE Labs (yourname)  123456789012
```

```bash
# Get the IAM policy on your project — who has what role
gcloud projects get-iam-policy $PROJECT_ID
```

Expected output (abbreviated):

```yaml
bindings:
- members:
  - user:your-email@gmail.com
  role: roles/owner
etag: BwXxxxxxxxx=
version: 1
```

As project creator, you are automatically granted `roles/owner` — the most permissive role. The three **primitive roles** are:

| Role | What it grants | Exam note |
|------|---------------|-----------|
| `roles/viewer` | Read-only access to all resources in the project | Cannot modify anything |
| `roles/editor` | Viewer + create/modify resources, cannot change IAM | Broad write access; avoid in production |
| `roles/owner` | Editor + manage IAM + billing | Full control; assign only to admins |

```bash
# See what predefined roles are available for Compute Engine (preview for Lab 04)
gcloud iam roles list --filter="name:roles/compute" \
  --format="table(name,title)" | head -15
```

Expected output:

```
NAME                                TITLE
roles/compute.admin                 Compute Admin
roles/compute.imageUser             Compute Image User
roles/compute.instanceAdmin         Compute Instance Admin (beta)
roles/compute.instanceAdmin.v1      Compute Instance Admin (v1)
roles/compute.loadBalancerAdmin     Compute Load Balancer Admin
roles/compute.networkAdmin          Compute Network Admin
roles/compute.networkUser           Compute Network User
roles/compute.networkViewer         Compute Network Viewer
roles/compute.osAdminLogin          Compute OS Admin Login
roles/compute.osLogin               Compute OS Login
roles/compute.securityAdmin         Compute Security Admin
roles/compute.storageAdmin          Compute Storage Admin
roles/compute.viewer                Compute Viewer
```

> **ACE Exam Tip:** Predefined roles like `roles/compute.instanceAdmin.v1` follow the **principle of least privilege** — they grant only the permissions needed for a specific job function. You should nearly always use a predefined role rather than a primitive role (`owner`/`editor`/`viewer`) in production.

```bash
# Add a label to your project (labels work on projects too, not just resources)
gcloud projects update $PROJECT_ID \
  --update-labels=env=lab,course=ace,lab-number=01
```

```bash
# Verify the labels were applied
gcloud projects describe $PROJECT_ID --format="value(labels)"
```

Expected output:

```
course=ace;env=lab;lab-number=01
```

```bash
# List projects filtered by label
gcloud projects list --filter="labels.course=ace"
```

---

## Key Takeaways

- The GCP resource hierarchy is Organisation → Folder → Project → Resource. IAM policies are **inherited downward** and cannot be blocked by children.
- A **Project** is the fundamental boundary for billing, quotas, and API enablement. Every resource belongs to exactly one project.
- The project **ID** and project **number** are permanent and immutable. The project **name** is changeable.
- `gcloud auth login` stores credentials for `gcloud` commands; `gcloud auth application-default login` stores credentials for code that calls GCP APIs — these are separate tokens.
- The most secure way to authenticate a workload **running in GCP** is to attach a service account to the resource (VM, Cloud Run service, GKE pod via Workload Identity). Never use key files on GCP-hosted workloads.
- Every GCP service requires its API to be explicitly enabled on the project. Attempting to use a disabled API returns a `PERMISSION_DENIED` error.
- **Labels** are key-value metadata for billing and organisation (`env=prod`). **Network tags** are string identifiers for targeting firewall rules (`web-server`). These are completely different mechanisms.
- `gcloud config configurations` let you maintain named sets of properties (project, region, zone, account) and switch between them instantly — essential when working across multiple projects.
- **Global resources** (VPCs, firewall rules) span all regions. **Regional resources** (Cloud SQL, regional IP addresses) are tied to one region. **Zonal resources** (VMs, persistent disks) are tied to one zone and are unavailable during zone failures.
- Persistent disks are **zonal** — a disk in `europe-west2-a` cannot be attached to a VM in `europe-west2-b`.
- Primitive roles (`owner`, `editor`, `viewer`) are broad and should be avoided in production. Use **predefined roles** (e.g. `roles/compute.instanceAdmin.v1`) to follow the principle of least privilege.
- On the ACE exam: "which region" questions should consider latency, data residency regulations, service availability, and cost — in roughly that priority order for most scenarios.

---

## Cleanup

This lab created no billable resources and does not delete the course project (it is shared across all labs). The only thing to clean up is the `prod-environment` named configuration created in Exercise 6.

```bash
# Delete the prod-environment configuration created in Exercise 6
gcloud config configurations delete prod-environment
```

Expected output:

```
The following configurations will be deleted:
 - prod-environment
Do you want to continue (Y/n)? Y

Deleted [prod-environment].
```

```bash
# Verify the default configuration is still active and pointing at your course project
gcloud config configurations list
gcloud config get-value project
```