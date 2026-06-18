#!/bin/bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <sa-email> <gs://bucket-path>"
  exit 1
fi

SA_EMAIL="$1"
GCS_PATH="$2"

export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT="$SA_EMAIL"
gcloud --verbosity=error auth list
gcloud --verbosity=error storage ls "$GCS_PATH"
