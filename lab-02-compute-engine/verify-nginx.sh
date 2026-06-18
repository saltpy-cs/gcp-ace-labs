#!/bin/bash
set -euo pipefail

ZONE=$(gcloud config get-value compute/zone)
TIMEOUT=180
ELAPSED=0

EXTERNAL_IP=$(gcloud compute instances describe lab02-web \
  --zone=$ZONE \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

echo "External IP: $EXTERNAL_IP"

until curl -sf --max-time 3 "http://$EXTERNAL_IP" > /dev/null; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Timed out after ${TIMEOUT}s. Checking serial port output for startup script errors:"
    gcloud compute instances get-serial-port-output lab02-web --zone=$ZONE | tail -30
    exit 1
  fi
  echo "Waiting for nginx... (${ELAPSED}s elapsed)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

curl -s "http://$EXTERNAL_IP"
