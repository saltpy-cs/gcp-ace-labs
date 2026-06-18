#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <gcs-object-url> <service-account-email>"
  echo "Example: $0 gs://my-bucket/private/report.txt sa@project.iam.gserviceaccount.com"
  exit 1
fi

OBJECT=$1
SA_EMAIL=$2
REGION=$(gcloud config get-value compute/region)
TIMEOUT=120
ELAPSED=0

echo "Signing URL for $OBJECT using $SA_EMAIL..."

until SIGNED_URL=$(gcloud storage sign-url "$OBJECT" \
  --duration=1h \
  --impersonate-service-account="$SA_EMAIL" \
  --region="$REGION" 2>/dev/null); do
  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "Timed out after ${TIMEOUT}s waiting for IAM to propagate."
    exit 1
  fi
  echo "IAM not yet propagated, retrying... (${ELAPSED}s elapsed)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

echo "Signed URL:"
echo "$SIGNED_URL"
