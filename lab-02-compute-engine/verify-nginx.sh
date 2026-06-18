#!/bin/bash
set -euo pipefail

ZONE=$(gcloud config get-value compute/zone)

EXTERNAL_IP=$(gcloud compute instances describe lab02-web \
  --zone=$ZONE \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "External IP: $EXTERNAL_IP"

until curl -sf --max-time 3 "http://$EXTERNAL_IP" > /dev/null; do
  echo "Waiting for nginx..."
  sleep 5
done

curl -s "http://$EXTERNAL_IP"
