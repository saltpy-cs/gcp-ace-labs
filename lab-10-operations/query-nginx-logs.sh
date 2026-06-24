#!/bin/bash
set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)

VM_IP=$(gcloud compute instances describe lab10-vm \
  --zone="us-central1-a" \
  --project="${PROJECT_ID}" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "Sending request to nginx at ${VM_IP}..."
curl -s "http://${VM_IP}" > /dev/null

echo "Waiting for log entry to appear in Cloud Logging..."
until gcloud logging read \
  'resource.type="gce_instance" AND logName:"nginx_access"' \
  --project="${PROJECT_ID}" \
  --limit=1 \
  --format="value(timestamp)" 2>/dev/null | grep -q .; do
  echo "  not yet — retrying in 5s..."
  sleep 5
done

echo "Log entry found. Fetching nginx access logs:"
gcloud logging read \
  'resource.type="gce_instance" AND logName:"nginx_access"' \
  --project="${PROJECT_ID}" \
  --limit=5 \
  --format="table(timestamp,jsonPayload.message)"
