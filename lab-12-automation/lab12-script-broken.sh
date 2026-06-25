#!/bin/bash
set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
TOPIC_NAME="lab12-script-topic"
SUB_NAME="lab12-script-sub"
BUCKET_NAME="INVALID BUCKET NAME WITH SPACES"

echo "=== Lab 12 multi-step gcloud script (broken version) ==="
echo "Project: ${PROJECT_ID}"
echo "Topic:   ${TOPIC_NAME}"
echo "Bucket:  ${BUCKET_NAME}"
echo ""

# ── Cleanup function (runs on exit, success or failure) ───────────────────────
cleanup() {
  local exit_code=$?
  echo ""
  echo "=== Cleanup (exit code: ${exit_code}) ==="

  echo "Deleting Pub/Sub subscription..."
  gcloud pubsub subscriptions delete "${SUB_NAME}" \
    --quiet --project="${PROJECT_ID}" 2>/dev/null \
    || echo "  Subscription not found — skipping."

  echo "Deleting Pub/Sub topic..."
  gcloud pubsub topics delete "${TOPIC_NAME}" \
    --quiet --project="${PROJECT_ID}" 2>/dev/null \
    || echo "  Topic not found — skipping."

  echo "Deleting Cloud Storage bucket..."
  gcloud storage rm -r "gs://${BUCKET_NAME}" \
    --quiet 2>/dev/null \
    || echo "  Bucket not found — skipping."

  echo "=== Cleanup complete ==="
  exit ${exit_code}
}

# Register the cleanup function to run on any exit
trap cleanup EXIT

# ── Step 1: Check preconditions ───────────────────────────────────────────────
echo "--- Step 1: Checking preconditions ---"

for api in pubsub.googleapis.com storage.googleapis.com; do
  if ! gcloud services list --enabled \
       --format="value(config.name)" \
       --project="${PROJECT_ID}" | grep -q "^${api}$"; then
    echo "ERROR: API ${api} is not enabled. Run: gcloud services enable ${api}"
    exit 1
  fi
done
echo "All required APIs are enabled."

# ── Step 2: Create Pub/Sub topic and subscription ─────────────────────────────
echo ""
echo "--- Step 2: Creating Pub/Sub topic and subscription ---"

gcloud pubsub topics create "${TOPIC_NAME}" \
  --project="${PROJECT_ID}"
echo "Topic created: ${TOPIC_NAME}"

gcloud pubsub subscriptions create "${SUB_NAME}" \
  --topic="${TOPIC_NAME}" \
  --ack-deadline=60 \
  --message-retention-duration=1h \
  --project="${PROJECT_ID}"
echo "Subscription created: ${SUB_NAME}"

# ── Step 3: Create a Cloud Storage bucket (intentional break: invalid name) ──
echo ""
echo "--- Step 3: Creating Cloud Storage bucket ---"

gcloud storage buckets create "gs://${BUCKET_NAME}" \
  --location="${REGION}" \
  --uniform-bucket-level-access \
  --project="${PROJECT_ID}"
echo "Bucket created: gs://${BUCKET_NAME}"

# ── Step 4: Publish a message ─────────────────────────────────────────────────
echo ""
echo "--- Step 4: Publishing test message ---"

MESSAGE_ID=$(gcloud pubsub topics publish "${TOPIC_NAME}" \
  --message='{"event":"lab12-test","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' \
  --project="${PROJECT_ID}" \
  --format="value(messageIds[0])")

echo "Published message ID: ${MESSAGE_ID}"

# ── Step 5: Pull and verify the message ───────────────────────────────────────
echo ""
echo "--- Step 5: Pulling and verifying message ---"

PULLED=$(gcloud pubsub subscriptions pull "${SUB_NAME}" \
  --limit=1 \
  --auto-ack \
  --format="table[no-heading](message.data)" \
  --project="${PROJECT_ID}")

if [ -z "${PULLED}" ]; then
  echo "ERROR: No message received from subscription."
  exit 1
fi

echo "Message received: ${PULLED}"
echo ""
echo "=== All steps succeeded ==="
