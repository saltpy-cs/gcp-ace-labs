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
echo -e "${BOLD}Lab 10 — Operations Quiz${RESET}"
echo "Five questions on Cloud Operations (monitoring, logging, alerting) concepts."
echo ""

ask \
  "Scenario 1 — Missing Memory Metrics" \
  "A team creates a new GCE instance and builds a Cloud Monitoring dashboard. CPU utilization, network bytes, and disk I/O charts all display data. The memory utilization chart shows no data at all. What is the most likely cause?" \
  "The Ops Agent has not been installed on the instance" \
  "Memory utilization is not reported by default to Cloud Monitoring. CPU, network, and disk I/O metrics are collected automatically from GCE instances with no agent required. Memory metrics — along with per-process CPU/memory and disk fill percentage — require the Ops Agent. The Ops Agent supersedes the legacy Monitoring agent (collectd) and Logging agent (fluentd)." \
  "The instance does not have a public IP address" \
  "The Ops Agent has not been installed on the instance" \
  "The monitoring.timeSeries.create IAM permission is missing on the instance's service account" \
  "Memory utilization is a CUMULATIVE metric and requires a custom aggregation window before it appears"

ask \
  "Scenario 2 — Silent Alert Policy" \
  "An engineer creates an alerting policy with a metric threshold condition: 'CPU utilization > 80% for 5 minutes'. The VM's CPU has been at 95% for 20 minutes, but no notification has been received. The incident is open in the Cloud Console. What is the most likely explanation?" \
  "No notification channel has been attached to the alerting policy" \
  "An alerting policy without a notification channel will open an incident in the Cloud Console but send no external notification. Notification channels — email, PagerDuty, Slack, Pub/Sub, webhook, SMS — must be explicitly created and attached to the policy. The incident appearing in the console confirms the condition fired correctly; the missing piece is the outbound notification path." \
  "The alert condition duration of 300 seconds is too long for a threshold policy to evaluate correctly" \
  "The CPU utilization threshold should be expressed as 80, not 0.8, in the policy definition" \
  "No notification channel has been attached to the alerting policy" \
  "Cloud Monitoring requires a 15-minute warm-up period before new alerting policies can fire"

ask \
  "Scenario 3 — Audit Log Investigation" \
  "A security team is investigating an incident and needs to determine which user deleted a Cloud Storage bucket and when. They have not enabled any special logging. Which combination correctly identifies the right log type and query field to use?" \
  "Admin Activity audit log; filter on protoPayload.methodName" \
  "Admin Activity audit logs record all GCP resource configuration mutations — including bucket deletions — and are always enabled; they cannot be disabled and are free. They use protoPayload (not jsonPayload), so the correct query field is protoPayload.methodName (e.g. 'storage.buckets.delete'). The principal who performed the action is in protoPayload.authenticationInfo.principalEmail. Data Access logs, by contrast, must be explicitly enabled and record data reads/writes, not resource deletions." \
  "Data Access audit log; filter on jsonPayload.methodName" \
  "Admin Activity audit log; filter on protoPayload.methodName" \
  "System Event audit log; filter on protoPayload.resourceName" \
  "Admin Activity audit log; filter on jsonPayload.authenticationInfo.principalEmail"

ask \
  "Scenario 4 — Choosing the Right Log Sink Destination" \
  "A compliance team requires that all Cloud Audit Logs be retained for 7 years and must be queryable using standard SQL for annual compliance reports. They also need new audit events to be available for querying within minutes of occurring. Which log sink destination best meets these requirements?" \
  "BigQuery with --use-partitioned-tables" \
  "BigQuery supports unlimited retention at BigQuery storage pricing and allows full Standard SQL queries — ideal for compliance reports and ad-hoc analysis across years of data. The --use-partitioned-tables flag creates date-partitioned tables, dramatically reducing query cost when filtering by date. New log entries typically appear in BigQuery within minutes. GCS is cost-effective for cold archival but requires downloading files to query them. Pub/Sub is for real-time streaming to downstream consumers. A custom Log Bucket extends retention within Cloud Logging but is not queryable with SQL." \
  "Cloud Storage with a lifecycle policy set to 7 years" \
  "A custom Cloud Logging log bucket with 2555-day retention" \
  "BigQuery with --use-partitioned-tables" \
  "Pub/Sub with a long-retention subscription and a downstream BigQuery subscription"

ask \
  "Scenario 5 — Metric Kind and Alerting" \
  "A team wants to alert when the number of HTTP 5xx errors on a GCE instance exceeds 50 in any 5-minute window. They plan to create a log-based counter metric for this. Which aligner should they use in the alerting policy condition, and why?" \
  "ALIGN_SUM, because the log-based counter is a DELTA metric representing counts per alignment period" \
  "Log-based counter metrics are DELTA metrics — each data point represents the count of matching log entries during that alignment period, not a cumulative total. ALIGN_SUM therefore gives the total count within the 5-minute window, which maps directly to the '50 errors in 5 minutes' threshold. ALIGN_RATE would convert the count to errors-per-second, which is less intuitive for threshold alerting expressed as a count. ALIGN_MEAN would average across time series rather than sum them. ALIGN_FRACTION_TRUE is used for boolean (GAUGE) metrics like uptime check pass/fail." \
  "ALIGN_RATE, because the metric measures a rate of change over time" \
  "ALIGN_MEAN, because averaging across the window smooths transient spikes" \
  "ALIGN_FRACTION_TRUE, because log-based metrics are boolean pass/fail counters" \
  "ALIGN_SUM, because the log-based counter is a DELTA metric representing counts per alignment period"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE operations questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
