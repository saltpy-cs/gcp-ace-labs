#!/bin/bash
set -euo pipefail

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
echo "Enabling all APIs used in this course for project: $PROJECT_ID"
echo "This takes 60-90 seconds..."

gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  dns.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  run.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  appengine.googleapis.com \
  sqladmin.googleapis.com \
  redis.googleapis.com \
  pubsub.googleapis.com \
  bigquery.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com \
  cloudtrace.googleapis.com \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT_ID"

gcloud services enable \
  cloudscheduler.googleapis.com \
  deploymentmanager.googleapis.com \
  sourcerepo.googleapis.com \
  clouddeploy.googleapis.com \
  servicenetworking.googleapis.com \
  vpcaccess.googleapis.com \
  eventarc.googleapis.com \
  --project="$PROJECT_ID"

echo "Done. All course APIs are enabled."
