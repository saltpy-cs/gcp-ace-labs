#!/bin/bash
set -euo pipefail

ZONE=$(gcloud config get-value compute/zone)

echo "=== Instances ==="
gcloud compute instances list --filter="name~'^lab02-'" --zones=$ZONE

echo "=== Disks ==="
gcloud compute disks list --filter="name~'^lab02-'" --zones=$ZONE

echo "=== Snapshots ==="
gcloud compute snapshots list --filter="name~'^lab02-'"

echo "=== Images ==="
gcloud compute images list --filter="name~'^lab02-'"

echo "=== Instance templates ==="
gcloud compute instance-templates list --filter="name~'^lab02-'"

echo "=== Firewall rules ==="
gcloud compute firewall-rules list --filter="name=default-allow-http" --format="table(name,direction,allowed,targetTags,sourceRanges)"
