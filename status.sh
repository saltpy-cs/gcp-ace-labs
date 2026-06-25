#!/bin/bash
set -uo pipefail

LAB=${1:-""}
PREFIX=${LAB:+$(printf "lab%02d-" "$LAB")}
PREFIX=${PREFIX:-"lab"}

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
REGION=${2:-us-central1}

echo "=== Project: $PROJECT_ID | Filter: ${PREFIX}* ==="
echo ""

# Compute
echo "=== Compute Instances ==="
gcloud compute instances list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Compute Disks ==="
gcloud compute disks list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Compute Snapshots ==="
gcloud compute snapshots list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Compute Images ==="
gcloud compute images list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Instance Templates ==="
gcloud compute instance-templates list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Managed Instance Groups ==="
gcloud compute instance-groups managed list --filter="name~'^${PREFIX}'" 2>/dev/null

# Networking
echo "=== Firewall Rules ==="
gcloud compute firewall-rules list --filter="name~'^${PREFIX}'" \
  --format="table(name,direction,allowed,targetTags,sourceRanges)" 2>/dev/null

echo "=== VPC Networks ==="
gcloud compute networks list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Subnets ==="
gcloud compute networks subnets list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== VPC Peerings ==="
gcloud compute networks list --filter="name~'^${PREFIX}'" --format="value(name)" 2>/dev/null | \
  xargs -I{} gcloud compute networks peerings list --network={} 2>/dev/null

echo "=== Cloud NAT Configs ==="
gcloud compute routers list --filter="name~'^${PREFIX}'" --format="value(name,region)" 2>/dev/null | \
  while read name region; do
    gcloud compute routers nats list --router="$name" --region="$region" 2>/dev/null
  done

echo "=== Subnet Private Google Access ==="
gcloud compute networks subnets list --filter="name~'^${PREFIX}'" \
  --format="table(name,region,privateIpGoogleAccess)" 2>/dev/null

echo "=== Cloud Routers ==="
gcloud compute routers list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Forwarding Rules ==="
gcloud compute forwarding-rules list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Backend Services ==="
gcloud compute backend-services list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== URL Maps ==="
gcloud compute url-maps list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Health Checks ==="
gcloud compute health-checks list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Static IP Addresses ==="
gcloud compute addresses list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== DNS Managed Zones ==="
gcloud dns managed-zones list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== DNS Record Sets ==="
gcloud dns managed-zones list --filter="name~'^${PREFIX}'" --format="value(name)" 2>/dev/null | \
  xargs -I{} gcloud dns record-sets list --zone={} 2>/dev/null

# Containers
echo "=== GKE Clusters ==="
gcloud container clusters list --filter="name~'^${PREFIX}'" 2>/dev/null

# Serverless
echo "=== Cloud Run Services ==="
gcloud run services list --platform=managed --region="$REGION" \
  --filter="metadata.name~'^${PREFIX}'" 2>/dev/null || true

# Messaging
echo "=== Pub/Sub Topics ==="
gcloud pubsub topics list --filter="name~'${PREFIX}'" \
  --format="table(name)" 2>/dev/null

echo "=== Pub/Sub Subscriptions ==="
gcloud pubsub subscriptions list --filter="name~'${PREFIX}'" \
  --format="table(name,topic,pushConfig.pushEndpoint)" 2>/dev/null

# Databases
echo "=== Cloud SQL Instances ==="
gcloud sql instances list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Memorystore (Redis) Instances ==="
gcloud redis instances list --region="$REGION" \
  --filter="name~'${PREFIX}'" 2>/dev/null

# Storage
echo "=== GCS Buckets ==="
gcloud storage buckets list --filter="name~'${PREFIX}'" \
  --format="table(name, location, default_storage_class, uniform_bucket_level_access)" 2>/dev/null

echo "=== Artifact Registry Repositories ==="
gcloud artifacts repositories list --location="$REGION" \
  --filter="name~'${PREFIX%%-}'" \
  --format="table(name.basename(),format,location)" 2>/dev/null || true

# Operations
echo "=== BigQuery Datasets ==="
bq ls --project_id="$PROJECT_ID" 2>/dev/null | grep -i "${PREFIX}" || true

echo "=== Log Sinks ==="
gcloud logging sinks list --filter="name~'${PREFIX}'" 2>/dev/null

echo "=== Alerting Policies ==="
gcloud monitoring policies list --filter="displayName~'${PREFIX}'" \
  --format="table(displayName,enabled,conditions[0].displayName)" 2>/dev/null

# Security
echo "=== Secret Manager Secrets ==="
gcloud secrets list --filter="name~'${PREFIX}'" 2>/dev/null

echo "=== Cloud Armor Security Policies ==="
gcloud compute security-policies list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== KMS Key Rings ==="
gcloud kms keyrings list --location="$REGION" \
  --filter="name~'${PREFIX}'" 2>/dev/null

# Automation
echo "=== Cloud Scheduler Jobs ==="
gcloud scheduler jobs list --location="$REGION" \
  --filter="name~'${PREFIX}'" 2>/dev/null

echo "=== Cloud Build Triggers ==="
gcloud builds triggers list --filter="name~'${PREFIX}'" 2>/dev/null

echo "=== Deployment Manager Deployments ==="
gcloud deployment-manager deployments list --filter="name~'^${PREFIX}'" 2>/dev/null

# IAM
echo "=== Service Accounts (non-default) ==="
gcloud iam service-accounts list \
  --filter="NOT email~'(compute|appspot|cloudservices)\.' AND NOT email~'^[0-9]+-compute@'" \
  --format="table(email, displayName, disabled)" 2>/dev/null

echo "=== Custom IAM Roles ==="
gcloud iam roles list --project="$PROJECT_ID" \
  --format="table(name, title, stage)" 2>/dev/null
