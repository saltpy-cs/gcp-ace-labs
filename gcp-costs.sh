#!/usr/bin/env bash
# gcp-costs.sh — show billing info and spend link for a GCP project
#
# Usage:
#   ./gcp-costs.sh                  # uses current gcloud project
#   ./gcp-costs.sh my-project-id    # specify a project explicitly

set -euo pipefail

PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"

if [[ -z "$PROJECT" ]]; then
  echo "Error: no project set." >&2
  echo "Run: gcloud config set project PROJECT_ID  or pass it as an argument." >&2
  exit 1
fi

echo "=== GCP Cost Summary: $PROJECT ==="
echo ""

# Billing account info
BILLING_JSON=$(gcloud billing projects describe "$PROJECT" --format=json)
BILLING_ACCOUNT_ID=$(echo "$BILLING_JSON" | jq -r '.billingAccountName' | sed 's|billingAccounts/||')
BILLING_ENABLED=$(echo "$BILLING_JSON" | jq -r '.billingEnabled')

echo "Billing account : $BILLING_ACCOUNT_ID"
echo "Billing enabled : $BILLING_ENABLED"

if [[ "$BILLING_ENABLED" != "true" ]]; then
  echo ""
  echo "Warning: billing is not enabled on this project — no charges will appear."
  exit 0
fi

# Budgets — requires billingbudgets.googleapis.com to be enabled
echo ""
echo "--- Budgets ---"
BUDGETS_OUTPUT=$(gcloud billing budgets list \
  --billing-account="$BILLING_ACCOUNT_ID" \
  --format="table(displayName,amount.specifiedAmount.units:label=LIMIT_USD)" \
  --quiet \
  2>&1 || true)

if echo "$BUDGETS_OUTPUT" | grep -q "API.*not enabled\|permission\|disabled"; then
  echo "(billingbudgets.googleapis.com not enabled — skipping)"
  echo "Enable at: https://console.developers.google.com/apis/api/billingbudgets.googleapis.com/overview?project=$PROJECT"
elif [[ -z "$BUDGETS_OUTPUT" ]]; then
  echo "(none configured)"
else
  echo "$BUDGETS_OUTPUT"
fi

# GCP does not expose total spend via a public CLI or REST API without a
# BigQuery billing export. The console reports page is the fastest way to
# see actual charges.
echo ""
echo "--- Spend report (console) ---"
echo "https://console.cloud.google.com/billing/$BILLING_ACCOUNT_ID/reports;projects=$PROJECT"
echo ""
echo "For programmatic cost data, enable BigQuery billing export:"
echo "https://console.cloud.google.com/billing/$BILLING_ACCOUNT_ID/export"
