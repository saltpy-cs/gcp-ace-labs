#!/bin/bash
set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
SERVICE_NAME="lab08-hello"

SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

echo "Polling ${SERVICE_NAME} until it scales to zero..."

while true; do
  instance_count=$(gcloud run instances list \
    --service="${SERVICE_NAME}" \
    --region="${REGION}" \
    --project="${PROJECT_ID}" \
    --format="value(name)" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "${instance_count}" -eq 0 ]]; then
    echo "Scaled to zero. Firing cold-start request..."
    time curl -s -o /dev/null -w "HTTP %{http_code} — Total time: %{time_total}s\n" "${SERVICE_URL}"
    break
  fi

  echo "  ${instance_count} instance(s) still active — checking again in 30s"
  sleep 30
done
