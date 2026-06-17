# GCP Associate Cloud Engineer Labs

A progressive series of hands-on labs for the **Google Cloud Associate Cloud Engineer** exam.
Every concept is taught through the `gcloud` CLI — no click-ops, no Terraform. You learn
what GCP is actually doing, not how a tool abstracts it away.

Labs build on each other: resources created in lab 01 are referenced in later labs, and
patterns introduced early (VPC, IAM, service accounts) reappear with greater depth as the
course progresses.

---

## Prerequisites

Install the following tools before starting:

```bash
# Google Cloud CLI (includes gsutil and gcloud storage)
brew install --cask google-cloud-sdk

# kubectl (for lab 07 — GKE)
brew install kubectl
# or via gcloud:
gcloud components install kubectl

# Docker (for lab 12 — Cloud Build, Artifact Registry)
brew install --cask docker

# Verify versions
gcloud --version        # should be >= 450.0.0
kubectl version --client
docker --version
```

> **Windows users:** Use [Google Cloud Shell](https://shell.cloud.google.com/) — all tools
> are pre-installed. Alternatively, WSL2 with the Linux install path works well.

---

## GCP Project Setup

Each learner needs a dedicated GCP project. The commands below create one named after
your local username so it is easy to identify and avoids collisions with teammates.

> **First-time GCP account?** Before the CLI can create projects you must accept Google
> Cloud's Terms of Service in the browser. Visit **https://console.cloud.google.com/**,
> sign in with the account you will use for `gcloud auth login`, and accept the ToS when
> prompted. You do not need to create anything in the console — just accept and return here.

```bash
# Build a project ID from your username.
# GCP project IDs must be lowercase, 6–30 chars, letters/digits/hyphens, start with a letter.
PROJECT_ID="gcp-ace-$(echo "$USER" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-' | cut -c1-20)"
echo "Project ID: ${PROJECT_ID}"
```

> If this ID is already taken (project IDs are globally unique), append a short suffix:
> `PROJECT_ID="${PROJECT_ID}-01"`

```bash
# Authenticate your user account (opens a browser)
gcloud auth login

# Create the project
gcloud projects create "${PROJECT_ID}" --name="GCP ACE Labs (${USER})"

# Link a billing account — required before any paid resources can be created.
# This lists your open billing accounts and links the first one automatically.
BILLING_ACCOUNT=$(gcloud billing accounts list \
  --filter="open=true" \
  --format="value(name)" | head -1)

if [ -z "${BILLING_ACCOUNT}" ]; then
  echo "No open billing account found."
  echo "Create one at: https://console.cloud.google.com/billing"
else
  gcloud billing projects link "${PROJECT_ID}" \
    --billing-account="${BILLING_ACCOUNT}"
  echo "Billing linked: ${BILLING_ACCOUNT}"
fi

# Set as the active project for all subsequent gcloud commands
gcloud config set project "${PROJECT_ID}"
echo "Active project: $(gcloud config get-value project)"
```

### Application Default Credentials

Some labs use client libraries or tools that read Application Default Credentials (ADC)
rather than the `gcloud` session. Set these up once:

```bash
# Sets up ADC for your user account (opens a browser)
gcloud auth application-default login

# Verify — should print a long access token
gcloud auth application-default print-access-token | cut -c1-40
```

### Enable Core APIs

Enable these APIs once for your project. Each is free to enable:

```bash
gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  servicenetworking.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  appengine.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  datastore.googleapis.com \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  compute.googleapis.com \
  dns.googleapis.com
```

> Individual lab READMEs call out any additional APIs they require in their **Setup** section.

---

## Cost Warning

Labs 02–12 create real GCP resources. Estimated costs assume you follow the lab and
run the cleanup commands promptly at the end. Leaving resources running overnight will
exceed these estimates.

| Lab | Resources created | Estimated cost | Notes |
|-----|-------------------|---------------|-------|
| 01  | None (config only) | Free | gcloud CLI setup, no infrastructure |
| 02  | e2-micro VM | ~$0.00 | Covered by free tier in `us-central1` |
| 03  | GCS bucket, ~10 MB objects | ~$0.00 | Free tier: 5 GB storage, 5K ops/month |
| 04  | Service accounts, IAM bindings | Free | IAM has no per-resource charge |
| 05  | VPC, subnets, firewall rules, VM | ~$0.00 | Free tier VM; VPC/firewall rules are free |
| 06  | Regional MIG, 2–3 VMs, HTTP LB | **~$0.05–0.10/hr** | Destroy promptly; LB forwarding rules bill hourly |
| 07  | GKE Autopilot cluster, 2 pods | **~$0.10/hr** | Autopilot charges per pod resource request |
| 08  | Cloud Run service, Cloud Function, App Engine | ~$0.00 | Generous free tier; first 2M requests/month free |
| 09  | Cloud SQL (db-f1-micro), Memorystore (1 GB) | **~$0.07/hr** | SQL + Redis bill per hour — destroy promptly |
| 10  | Log sinks (GCS), alerting policies | ~$0.00 | GCS sink: free tier storage |
| 11  | KMS key rings, Secret Manager secrets, Cloud Armor policy | ~$0.01 | KMS: $0.06/key/month; Secret Manager: $0.06/secret/month |
| 12  | Cloud Build triggers, Artifact Registry repo | ~$0.00 | First 120 build-min/day free; 0.5 GB AR storage free |

**Always run the Cleanup commands at the end of each lab.**

To check current spend on your project at any time:

```bash
PROJECT_ID=$(gcloud config get-value project)
# Open the billing report for this project in your browser
gcloud billing projects describe "${PROJECT_ID}"
echo "https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
```

---

## Lab Overview

| Lab | Topic | GCP Services | Exam Domain |
|-----|-------|-------------|-------------|
| [01 - GCP Foundations & gcloud CLI](lab-01-foundations/README.md) | Projects, billing, organizations, gcloud config, quota | Resource Manager, Cloud Billing, IAM | Domain 1 — Setting up (17.5%) |
| [02 - Compute Engine](lab-02-compute-engine/README.md) | VMs, machine types, images, snapshots, startup scripts, SSH | Compute Engine | Domain 3 — Deploying (25%) |
| [03 - Cloud Storage](lab-03-cloud-storage/README.md) | Buckets, storage classes, lifecycle, signed URLs, versioning | Cloud Storage | Domain 3+4 — Deploying + Operating (25%+20%) |
| [04 - IAM & Service Accounts](lab-04-iam/README.md) | Roles, bindings, service accounts, workload identity, least privilege | IAM, Service Accounts | Domain 5 — Security (20%) |
| [05 - VPC Networking](lab-05-vpc/README.md) | VPCs, subnets, firewall rules, routes, VPC peering, Cloud NAT | VPC, Cloud NAT, Cloud DNS | Domain 2+3 — Planning + Deploying (17.5%+25%) |
| [06 - Load Balancing & MIGs](lab-06-load-balancing/README.md) | HTTP LB, MIGs, instance templates, autoscaling, health checks | Compute Engine, Cloud Load Balancing | Domain 3+4 — Deploying + Operating (25%+20%) |
| [07 - Google Kubernetes Engine](lab-07-gke/README.md) | Autopilot vs Standard, Deployments, Services, ConfigMaps, Secrets, HPA | GKE, Artifact Registry | Domain 3+4 — Deploying + Operating (25%+20%) |
| [08 - Serverless & PaaS](lab-08-serverless/README.md) | Cloud Run, Cloud Functions (2nd gen), App Engine, event triggers | Cloud Run, Cloud Functions, App Engine | Domain 3 — Deploying (25%) |
| [09 - Managed Databases](lab-09-databases/README.md) | Cloud SQL (Postgres), Firestore, Memorystore (Redis), read replicas | Cloud SQL, Firestore, Memorystore | Domain 2+3 — Planning + Deploying (17.5%+25%) |
| [10 - Operations & Observability](lab-10-operations/README.md) | Logs Explorer, metrics, dashboards, alerting, log sinks, Error Reporting | Cloud Monitoring, Cloud Logging | Domain 4 — Operating (20%) |
| [11 - Security](lab-11-security/README.md) | KMS key rings, CMEK, Secret Manager, Cloud Armor WAF, org policies | KMS, Secret Manager, Cloud Armor | Domain 5 — Security (20%) |
| [12 - Automation & CI/CD](lab-12-cicd/README.md) | Cloud Build triggers, Artifact Registry, build substitutions, deploy pipeline | Cloud Build, Artifact Registry | Domain 3 — Deploying (25%) |

---

## How to Work Through the Labs

All labs are self-contained directories. Every command is run from your local terminal
using `gcloud` (or `kubectl` / `gcloud storage` where noted).

Set your project ID at the start of every session:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"
echo "Working in project: ${PROJECT_ID}, region: ${REGION}"
```

Each lab README follows this structure:

- **Objectives** — what you will be able to do after completing the lab
- **Concepts** — the theory behind what you are doing, with comparison tables and AWS context
- **Setup** — prerequisites specific to that lab
- **Exercises** — step-by-step hands-on tasks with expected output snippets
- **Key Takeaways** — what to remember for the ACE exam
- **Cleanup** — `gcloud` commands to destroy every resource created

> Labs are designed to be done in order. Later labs assume familiarity with VPCs (lab 05),
> IAM (lab 04), and basic Compute Engine (lab 02). You do not need to keep resources from
> earlier labs running — each lab creates its own resources from scratch.

---

## Certification Relevance

The GCP Associate Cloud Engineer exam tests five domains. Every lab is mapped to at least
one domain, and the course is weighted to reflect the exam's own weighting.

### Domain 1 — Setting Up a Cloud Solution Environment (17.5%)

Creating and managing GCP projects, configuring billing accounts and budgets, understanding
the resource hierarchy (organization → folder → project), enabling APIs, and managing
IAM at the project level.

- **Lab 01** covers this domain in depth.
- Exam tip: know the difference between a GCP project, a folder, and an organization, and
  which IAM roles can be applied at each level.

### Domain 2 — Planning and Configuring a Cloud Solution (17.5%)

Selecting the right compute option (VM vs container vs serverless), choosing a storage
class or database type, sizing networks, and estimating cost with the pricing calculator.

- **Lab 05** (VPC networking) and **Lab 09** (databases) align here.
- Exam tip: memorize when to use Cloud SQL vs Firestore vs Bigtable vs Spanner — the exam
  asks scenario questions, not syntax questions.

### Domain 3 — Deploying and Implementing a Cloud Solution (25%)

The largest domain. Launching and configuring Compute Engine, GKE, Cloud Run, Cloud
Functions, App Engine, Cloud Storage, Cloud SQL, and Cloud Build pipelines.

- **Labs 02, 03, 05, 06, 07, 08, 09, and 12** align here.
- Exam tip: know the `gcloud` flags for creating VMs (`--machine-type`, `--image-family`,
  `--metadata`, `--service-account`). The exam tests flag knowledge.

### Domain 4 — Ensuring Successful Operation of a Cloud Solution (20%)

Managing running resources: VM snapshots, GKE rolling updates, autoscaling, log-based
metrics, alerting policies, and incident response.

- **Labs 06, 07, and 10** align here.
- Exam tip: understand the difference between a log-based metric and a Cloud Monitoring
  built-in metric, and when you would create each one.

### Domain 5 — Configuring Access and Security (20%)

IAM roles and bindings, service account best practices, workload identity, KMS encryption,
Secret Manager, Cloud Armor WAF policies, and org-level policy constraints.

- **Labs 04 and 11** align here.
- Exam tip: know the three role types (basic, predefined, custom) and when each is
  appropriate. Basic roles (`Owner`, `Editor`, `Viewer`) are almost always the wrong
  answer on the exam.

---

## Useful Reference Commands

```bash
# List all your projects
gcloud projects list

# Switch active project
gcloud config set project PROJECT_ID

# List enabled APIs in the current project
gcloud services list --enabled

# View current gcloud config
gcloud config list

# List available regions
gcloud compute regions list

# List available zones in a region
gcloud compute zones list --filter="region:us-central1"

# Describe your own identity
gcloud auth list
gcloud config get-value account
```
