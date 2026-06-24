#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
RESET='\033[0m'

SCORE=0
TOTAL=5

ask() {
  local scenario="$1"
  local question="$2"
  local correct="$3"
  local explanation="$4"
  shift 4
  local options=("$@")

  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}${scenario}${RESET}"
  echo ""
  echo "$question"
  echo ""

  PS3=$'\nYour answer: '
  select choice in "${options[@]}"; do
    if [[ -z "$choice" ]]; then
      echo "Invalid selection — try again."
      continue
    fi
    break
  done

  echo ""
  if [[ "$choice" == "$correct" ]]; then
    echo -e "${GREEN}Correct!${RESET}"
    SCORE=$((SCORE + 1))
  else
    echo -e "${RED}Incorrect.${RESET} The answer is: ${BOLD}${correct}${RESET}"
  fi

  echo ""
  echo -e "${YELLOW}Explanation:${RESET}"
  echo "$explanation"
}

echo ""
echo -e "${BOLD}Lab 08 — Serverless Quiz${RESET}"
echo "Five questions on serverless computing concepts."
echo ""

ask \
  "Scenario 1 — Cold Start Trade-offs" \
  "Your team runs a payment processing API on Cloud Run. It handles traffic 24/7 but experiences occasional latency spikes of 1-2 seconds on the first request after a quiet period. The service uses 512 MB of memory. What is the most targeted fix, and what is the cost implication?" \
  "Set --min-instances=1; you pay for one idle instance continuously even when no traffic is arriving" \
  "Cold starts happen when Cloud Run scales from zero. Setting --min-instances=1 keeps one instance warm at all times, eliminating the startup penalty. The cost trade-off is that Cloud Run bills for CPU and memory during idle time — you pay for that one instance even when it handles zero requests. --max-instances only caps scale-out and has no effect on cold starts. Concurrency controls how many requests one instance handles simultaneously, not whether an instance is pre-warmed. Moving to App Engine Flexible would eliminate cold starts (it never scales to zero) but at significantly higher cost and operational overhead." \
  "Set --min-instances=1; you pay for one idle instance continuously even when no traffic is arriving" \
  "Set --max-instances=1; this keeps a single instance warm and eliminates cold starts at no extra cost" \
  "Set --concurrency=1; this forces each request to its own instance, ensuring a warm path is always available" \
  "Migrate to App Engine Flexible; it never scales to zero so cold starts are impossible"

ask \
  "Scenario 2 — Choosing a Serverless Product" \
  "A team needs to process audit log entries that are published to a Pub/Sub topic. Each entry takes up to 45 minutes to fully process (enriching with external API calls and writing to BigQuery). The team wants no server management. Which product is the correct choice, and why?" \
  "Cloud Run with a Pub/Sub push subscription; it supports up to 60-minute request timeouts and handles event-driven workloads" \
  "Cloud Run (and Cloud Functions Gen 2) support up to 60-minute timeouts, making them suitable for 45-minute jobs. Cloud Functions Gen 2 also supports 60-minute timeouts but is deployed as a single function from source — either would work technically. However, App Engine Standard has a 10-minute max request timeout, which is too short. Cloud Functions Gen 1 has a 9-minute max timeout, which is also too short. For the ACE exam, the key fact is that App Engine Standard = 10 minutes max and Cloud Run / Functions Gen 2 = 60 minutes max. Anything over 60 minutes requires Compute Engine or Cloud Batch." \
  "Cloud Run with a Pub/Sub push subscription; it supports up to 60-minute request timeouts and handles event-driven workloads" \
  "Cloud Functions Gen 1 with a Pub/Sub trigger; it is the managed runtime optimised for exactly this event-driven pattern" \
  "App Engine Standard with a background thread; it has built-in task queue support for reliable async processing" \
  "Compute Engine with a startup script that polls Pub/Sub; only VMs support jobs longer than 10 minutes"

ask \
  "Scenario 3 — App Engine Traffic Splitting Modes" \
  "You are splitting App Engine traffic 90/10 between a stable version and a canary. QA needs to repeatedly test the canary version from their laptops to validate a fix, but each refresh sends them to the stable version. Which traffic split mode should you switch to, and what is its mechanism?" \
  "cookie; App Engine sets a cookie on the first response and routes subsequent requests from the same client to the same version" \
  "App Engine supports three split-by modes. 'random' assigns each request independently with no affinity — callers bounce between versions. 'cookie' sets a GOOGAPPUID cookie on the initial response; subsequent requests carrying that cookie are routed to the same version, giving sticky sessions in a browser or cookie-aware HTTP client. 'ip' uses the client's source IP address to determine routing, which is sticky but can break behind NAT or proxies where many users share one IP. For QA browsers, 'cookie' is the right choice because it provides per-client stickiness without IP-based issues." \
  "cookie; App Engine sets a cookie on the first response and routes subsequent requests from the same client to the same version" \
  "ip; the client IP is hashed against the split percentages so QA laptops always resolve to the canary version" \
  "random; increasing the canary percentage to 50% gives QA a statistically even chance of hitting the canary on each request" \
  "header; App Engine reads an X-Canary header to pin requests to a named version"

ask \
  "Scenario 4 — Cloud Functions Gen 2 Architecture" \
  "A developer deploys a Cloud Functions Gen 2 function and notices it has a Cloud Run service URL (*.run.app) instead of the classic *.cloudfunctions.net URL. They also see the function listed when they run 'gcloud run services list'. Which statement best explains this behaviour?" \
  "Cloud Functions Gen 2 is built on Cloud Run; every Gen 2 function is a Cloud Run service under the hood, inheriting its execution environment, concurrency model, and URL format" \
  "Cloud Functions Gen 2 uses Cloud Run as its underlying execution environment. GCP provisions a Cloud Run service from your function source code using Cloud Build and buildpacks, which is why the service appears in 'gcloud run services list' and has a Cloud Run URL. This is not a bug or misconfiguration — it is by design and means Gen 2 functions inherit Cloud Run's longer timeouts (60 min vs 9 min), larger memory limits (32 GB vs 8 GB), higher concurrency (configurable vs 1), and Eventarc-based triggers. Gen 1 functions use a separate, older runtime and do not appear as Cloud Run services." \
  "Cloud Functions Gen 2 is built on Cloud Run; every Gen 2 function is a Cloud Run service under the hood, inheriting its execution environment, concurrency model, and URL format" \
  "The function was accidentally deployed as a Cloud Run service instead of a Cloud Function; the developer should delete the Cloud Run service and redeploy using the correct gcloud functions command" \
  "Cloud Functions Gen 2 uses Cloud Run only for HTTP-triggered functions; Pub/Sub-triggered functions run in the original Gen 1 runtime and will not appear in 'gcloud run services list'" \
  "Cloud Run and Cloud Functions Gen 2 share a URL namespace but are distinct runtimes; the *.run.app URL is a display alias and the function is not actually a Cloud Run service"

ask \
  "Scenario 5 — Cloud SQL Connectivity from Cloud Run" \
  "A Cloud Run service needs to connect to a Cloud SQL PostgreSQL instance. A teammate proposes enabling the Cloud SQL instance's public IP and storing the IP address and database password in environment variables on the Cloud Run service. What is wrong with this approach, and what is the recommended alternative?" \
  "Public IP exposure increases attack surface and environment variables are visible in the Cloud Run console; use --add-cloudsql-instances to mount the Cloud SQL Auth Proxy socket and authenticate via IAM service account" \
  "The recommended pattern is to use the Cloud SQL Auth Proxy via --add-cloudsql-instances on the 'gcloud run deploy' command. Cloud Run automatically runs the proxy as a sidecar container. The proxy authenticates to Cloud SQL using the service account identity (roles/cloudsql.client IAM role) — no credentials are stored in the proxy itself. Your application connects to a local Unix socket at /cloudsql/PROJECT:REGION:INSTANCE. This avoids exposing a public IP on the database and avoids storing credentials in environment variables (which appear in plain text in the Cloud Run console and deployment metadata). The database password remains a second factor, not the primary authentication mechanism." \
  "Public IP exposure increases attack surface and environment variables are visible in the Cloud Run console; use --add-cloudsql-instances to mount the Cloud SQL Auth Proxy socket and authenticate via IAM service account" \
  "There is no issue with this approach; Cloud Run environment variables are encrypted at rest and the public IP is protected by Cloud SQL's built-in firewall rules" \
  "The correct fix is to use VPC peering and a private IP address for Cloud SQL; the Cloud SQL Auth Proxy is only needed for Compute Engine VMs, not Cloud Run" \
  "Environment variables are acceptable for credentials but the public IP should be replaced with a Cloud SQL connection string in the format PROJECT:REGION:INSTANCE passed to the pg library directly"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE serverless questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
