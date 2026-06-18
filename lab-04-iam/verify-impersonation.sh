#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <sa-email> <gs://bucket-path>"
  exit 1
fi

SA_EMAIL="$1"
GCS_PATH="$2"
TIMEOUT=120
ELAPSED=0

until gcloud storage ls "$GCS_PATH" --impersonate-service-account="$SA_EMAIL" 2>/dev/null; do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Timed out after ${TIMEOUT}s waiting for impersonation to work."
    exit 1
  fi
  echo "IAM not yet propagated, retrying... (${ELAPSED}s elapsed)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done
