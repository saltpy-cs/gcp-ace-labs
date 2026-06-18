#!/bin/bash
set -euo pipefail

ZONE=$(gcloud config get-value compute/zone)

echo "=== Instances ==="
gcloud compute instances list --filter="name~'^lab02-'" --zones=$ZONE 2>/dev/null

echo "=== Disks ==="
gcloud compute disks list --filter="name~'^lab02-'" --zones=$ZONE 2>/dev/null

echo "=== Snapshots ==="
gcloud compute snapshots list --filter="name~'^lab02-'" 2>/dev/null

echo "=== Images ==="
gcloud compute images list --filter="name~'^lab02-'" 2>/dev/null

echo "=== Instance templates ==="
gcloud compute instance-templates list --filter="name~'^lab02-'" 2>/dev/null

echo "=== Firewall rules ==="
gcloud compute firewall-rules list --filter="name=default-allow-http" --format="table(name,direction,allowed,targetTags,sourceRanges)"
