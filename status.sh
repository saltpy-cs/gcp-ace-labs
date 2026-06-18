#!/bin/bash
set -euo pipefail

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
ZONE=$(gcloud config get-value compute/zone 2>/dev/null)

echo "=== Project: $PROJECT_ID ==="
echo ""

echo "=== Compute Instances (lab02-) ==="
gcloud compute instances list --filter="name~'^lab02-'" --zones=$ZONE 2>/dev/null

echo "=== Compute Disks (lab02-) ==="
gcloud compute disks list --filter="name~'^lab02-'" --zones=$ZONE 2>/dev/null

echo "=== Compute Snapshots (lab02-) ==="
gcloud compute snapshots list --filter="name~'^lab02-'" 2>/dev/null

echo "=== Compute Images (lab02-) ==="
gcloud compute images list --filter="name~'^lab02-'" 2>/dev/null

echo "=== Instance Templates (lab02-) ==="
gcloud compute instance-templates list --filter="name~'^lab02-'" 2>/dev/null

echo "=== Firewall Rules ==="
gcloud compute firewall-rules list --filter="name=default-allow-http" \
  --format="table(name,direction,allowed,targetTags,sourceRanges)" 2>/dev/null

echo ""
echo "=== GCS Buckets (${PROJECT_ID}-*-lab) ==="
gcloud storage buckets list --filter="name~${PROJECT_ID}-.*-lab" 2>/dev/null
