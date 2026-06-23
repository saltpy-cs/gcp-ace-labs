#!/bin/bash
set -euo pipefail

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
SERVICE_NAME="lab08-hello"

SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}" \
  --region="${REGION}" \
  --format="value(status.url)" \
  --project="${PROJECT_ID}")

echo "Polling Cloud Logging for ${SERVICE_NAME} container lifecycle events..."

while true; do
  latest=$(gcloud logging read \
    "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"${SERVICE_NAME}\" AND (textPayload:\"starting container\" OR textPayload:\"container stopped\")" \
    --project="${PROJECT_ID}" \
    --freshness=15m \
    --limit=1 \
    --format="value(textPayload)" 2>/dev/null | head -1)

  if [[ -z "${latest}" || "${latest}" == *"stopped"* ]]; then
    echo "Service has scaled to zero. Firing cold-start request..."
    time curl -s -o /dev/null -w "HTTP %{http_code} — Total time: %{time_total}s\n" "${SERVICE_URL}"
    break
  fi

  echo "  Container still running — checking again in 30s"
  sleep 30
done
