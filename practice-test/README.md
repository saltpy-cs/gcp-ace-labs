# GCP Associate Cloud Engineer Practice Test

A timed, hands-on exam simulation covering all five domains of the **GCP Associate Cloud
Engineer** exam. Every question requires you to run real `gcloud`, `kubectl`, or
`gcloud storage` commands against a live GCP project — there are no multiple-choice questions.

Questions progress from core CLI and IAM tasks through multi-service integration scenarios
that reflect the kind of judgement calls the ACE exam tests in its later sections.

---

## Format

| Item | Detail |
|------|--------|
| Questions | 15 |
| Total points | 120 |
| Suggested time | 120 minutes |
| Pass mark | 84 points (70%) |
| Distinction | 102 points (85%) |

**Allowed reference material** — you may consult:

- [cloud.google.com/sdk/gcloud/reference](https://cloud.google.com/sdk/gcloud/reference) — gcloud CLI reference
- [cloud.google.com/docs](https://cloud.google.com/docs) — GCP product documentation
- [cloud.google.com/kubernetes-engine/docs](https://cloud.google.com/kubernetes-engine/docs) — GKE documentation
- [kubectl.docs.kubernetes.io](https://kubectl.docs.kubernetes.io) — kubectl reference

You may **not** use tutorials, blog posts, course materials, AI assistants, or the lab
READMEs from this course.

---

## Difficulty Spread

| Questions | Level | Points each | Subtotal | Exam Domain |
|-----------|-------|-------------|----------|-------------|
| 1–4 | ACE core | 7 | 28 | Domains 1, 3, 3, 5 |
| 5–9 | ACE applied | 9 | 45 | Domains 2+3, 3, 3, 3+4, 4 |
| 10–13 | ACE professional-level scenarios | 8 | 32 | Domain 4, 4, 5, 3 |
| 14–15 | Multi-service integration | 6 | 15 | Domains 3+5, 3+5 |

> Note: Q14 and Q15 are worth 6 points each giving a total of 120 points.

---

## Prerequisites

- Google Cloud SDK installed and authenticated:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project YOUR_PROJECT_ID
  ```
- kubectl installed and configured:
  ```bash
  gcloud components install kubectl
  ```
- A GCP project with billing enabled
- The following APIs enabled (the setup script enables them if missing):
  - `compute.googleapis.com`
  - `container.googleapis.com`
  - `run.googleapis.com`
  - `sqladmin.googleapis.com`
  - `cloudbuild.googleapis.com`
  - `artifactregistry.googleapis.com`
  - `cloudkms.googleapis.com`
  - `secretmanager.googleapis.com`
  - `logging.googleapis.com`
  - `monitoring.googleapis.com`
  - `bigquery.googleapis.com`
  - `iap.googleapis.com`
- The practice environment has been provisioned (see Setup below)

---

## Setup

The setup script creates the pre-provisioned GCP resources that several questions operate
against. Run it once before starting the timer. It takes approximately 5–10 minutes.

```bash
# From the repo root
cd gcp-ace-labs/practice-test/setup

# Set your project (the setup script reads this)
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"

# Run the setup script
bash setup.sh
```

The setup provisions:

- A GCS bucket named `ace-practice-import-${PROJECT_ID}` for the Q3 lifecycle exercise
- A service account named `ace-practice-sa` for the Q4 IAM exercise
- A VPC network named `ace-practice-vpc` with subnet `ace-practice-subnet` (10.10.0.0/24)
  for the Q5 networking exercise
- A Cloud NAT router named `ace-practice-router` attached to `ace-practice-vpc`
- An Artifact Registry repository named `ace-practice-repo` in `us-central1` for Q13
- A Cloud KMS key ring named `ace-practice-keyring` with a key named `ace-practice-key`
  for Q11
- A BigQuery dataset named `ace_practice_logs` for Q10
- Output file `setup-outputs.env` — source this before starting the test:
  ```bash
  source gcp-ace-labs/practice-test/setup/setup-outputs.env
  ```

Do not start the timer until `setup.sh` completes and you have sourced `setup-outputs.env`.

> **Cost warning:** The setup creates a VPC, KMS key, and Artifact Registry repository —
> none of these bill significantly until you start creating VMs, GKE clusters, and Cloud SQL
> instances in the exercises. Q7 (GKE) and Q8 (Cloud SQL) are the highest-cost questions.
> Run the Cleanup commands promptly when you are done.

---

## Scoring

| Score | Result |
|-------|--------|
| 102–120 | Distinction — exam-ready with strong depth across all domains |
| 84–101 | Pass — solid ACE readiness; review the domains covering missed questions |
| 66–83 | Near miss — revisit the labs mapped to missed questions before retesting |
| < 66 | Needs more practice — complete all 12 labs before attempting this test again |

Each question is scored as complete or incomplete — there is no partial credit.

After completing each question, run the verification command listed in `questions.md`.
Mark it complete only when the verification command produces the expected output.

---

## Cleanup

After you have finished and recorded your score, destroy all resources created during
the test. Questions that create expensive resources (GKE, Cloud SQL) are called out
individually — destroy those first if you need to stop mid-test.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
ZONE="us-central1-a"

# Q2 — Compute Engine instance
gcloud compute instances delete ace-web-01 --zone="${ZONE}" --quiet

# Q5 — Private VM (if created)
gcloud compute instances delete ace-private-vm --zone="${ZONE}" --quiet

# Q6 — Cloud Run service
gcloud run services delete ace-hello --region="${REGION}" --quiet

# Q7 — GKE cluster (most expensive — destroy first if stopping early)
gcloud container clusters delete ace-practice-cluster \
  --region="${REGION}" --quiet

# Q8 — Cloud SQL instance (second most expensive)
gcloud sql instances delete ace-practice-db --quiet

# Q9 — Monitoring alert policy
POLICY_ID=$(gcloud alpha monitoring policies list \
  --filter="displayName='ace-cpu-alert'" \
  --format="value(name)" | head -1)
[ -n "${POLICY_ID}" ] && gcloud alpha monitoring policies delete "${POLICY_ID}" --quiet

# Q10 — Log sink
gcloud logging sinks delete ace-bq-sink --quiet

# Q11 — KMS key versions and Secret Manager secret
gcloud secrets delete ace-db-password --quiet

# Q12 — MIG, LB components
gcloud compute forwarding-rules delete ace-http-rule \
  --global --quiet
gcloud compute target-http-proxies delete ace-http-proxy --quiet
gcloud compute url-maps delete ace-url-map --quiet
gcloud compute backend-services delete ace-backend-svc \
  --global --quiet
gcloud compute health-checks delete ace-http-hc --quiet
gcloud compute instance-groups managed delete ace-web-mig \
  --region="${REGION}" --quiet
gcloud compute instance-templates delete ace-web-template --quiet

# Q13 — Cloud Build trigger
gcloud builds triggers delete ace-build-trigger --quiet

# Q14 — GKE + Cloud SQL (Workload Identity question)
# (cluster and SQL instance already deleted above)
kubectl delete namespace ace-wi-demo --ignore-not-found

# Q15 — Cloud Run + Cloud Armor
gcloud compute security-policies delete ace-armor-policy --quiet
gcloud run services delete ace-secure-svc --region="${REGION}" --quiet

# Setup resources — destroy last
bash gcp-ace-labs/practice-test/setup/cleanup.sh
```

> The KMS key created by setup cannot be deleted immediately — GCP enforces a minimum
> 24-hour scheduled destruction window. This incurs ~$0.001/month and can be left to
> expire on its own schedule.
