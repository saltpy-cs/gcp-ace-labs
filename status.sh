#!/bin/bash
set -euo pipefail

# Optional argument: lab number (e.g. 02, 03). Defaults to all labs.
LAB=${1:-""}
PREFIX=${LAB:+"lab${LAB}-"}
PREFIX=${PREFIX:-"lab"}

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
ZONE=$(gcloud config get-value compute/zone 2>/dev/null)

echo "=== Project: $PROJECT_ID ==="
echo ""

echo "=== Compute Instances (${PREFIX}*) ==="
gcloud compute instances list --filter="name~'^${PREFIX}'" --zones=$ZONE 2>/dev/null

echo "=== Compute Disks (${PREFIX}*) ==="
gcloud compute disks list --filter="name~'^${PREFIX}'" --zones=$ZONE 2>/dev/null

echo "=== Compute Snapshots (${PREFIX}*) ==="
gcloud compute snapshots list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Compute Images (${PREFIX}*) ==="
gcloud compute images list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Instance Templates (${PREFIX}*) ==="
gcloud compute instance-templates list --filter="name~'^${PREFIX}'" 2>/dev/null

echo "=== Firewall Rules ==="
gcloud compute firewall-rules list --filter="name=default-allow-http" \
  --format="table(name,direction,allowed,targetTags,sourceRanges)" 2>/dev/null

echo ""
echo "=== GCS Buckets (${PROJECT_ID}-*-lab) ==="
gcloud storage buckets list --filter="name~${PROJECT_ID}-.*-lab" 2>/dev/null
