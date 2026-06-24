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
echo -e "${BOLD}Lab 09 — Database Selection Quiz${RESET}"
echo "Five scenarios. Pick the best GCP database for each."
echo ""

ask \
  "Scenario A — Global Financial Ledger" \
  "Your company is building a global payment platform. Transactions must be ACID-compliant.
The platform serves users in North America, Europe, and Asia simultaneously. Consistency
is paramount — an account balance must never show stale data regardless of which region
serves the read." \
  "Cloud Spanner" \
  "Cloud SQL is ACID but single-region; cross-region replicas are asynchronous (eventual
consistency). Spanner uses TrueTime to provide externally consistent transactions across
regions. It is the only relational database that guarantees strong consistency globally.
Bigtable has no ACID transactions. BigQuery is analytical, not transactional." \
  "Cloud SQL" \
  "Cloud Spanner" \
  "Cloud Bigtable" \
  "BigQuery"

ask \
  "Scenario B — Mobile App User Profiles" \
  "A mobile app stores user profiles, settings, and social graph data. The data is
document-shaped (nested JSON). The mobile client needs to receive real-time updates when
a friend updates their profile, without polling. Expected scale: 10M users at launch." \
  "Firestore (Native mode)" \
  "Firestore's document model matches nested JSON naturally. Its real-time listeners push
updates to mobile clients without polling — this is a Native mode feature (Datastore mode
does not support it). Firestore scales horizontally without configuration. Cloud SQL has
no real-time push capability. Bigtable has no mobile SDK or real-time listener pattern.
Memorystore is a cache, not durable storage." \
  "Cloud SQL" \
  "Firestore (Native mode)" \
  "Cloud Bigtable" \
  "Memorystore Redis"

ask \
  "Scenario C — IoT Sensor Time Series" \
  "A manufacturing plant has 50,000 sensors each writing a reading every second (50,000
writes/sec). You need to store 3 years of history (~15 TB) and run time-windowed
aggregations. Writes must be extremely fast; reads scan large time ranges." \
  "Cloud Bigtable" \
  "Bigtable handles millions of writes per second and is optimised for time-series data.
The canonical row key pattern is sensor_id#timestamp, making time-range scans over a
sensor group efficient. At 15 TB, Bigtable is well within its strengths. Cloud SQL cannot
handle 50k writes/sec or 15 TB on a single instance. BigQuery is good for historical
analytics but not real-time ingest at this write rate. Firestore's document model is the
wrong fit for time-series at this scale." \
  "Cloud SQL" \
  "Firestore" \
  "Cloud Bigtable" \
  "BigQuery"

ask \
  "Scenario D — E-commerce Product Catalog with Cache" \
  "An e-commerce site runs a MySQL database on Cloud SQL. Product detail pages are slow
because the same queries run on every page load. The product catalogue rarely changes
(updates a few times per day). You want sub-millisecond response for catalogue queries." \
  "Keep Cloud SQL and add Memorystore Redis as a cache" \
  "The data is relational and rarely changes — a perfect cache candidate. Adding Memorystore
Redis in front of Cloud SQL (cache-aside pattern) delivers sub-millisecond reads: the app
checks Redis first, and on a miss queries Cloud SQL then populates the cache with a TTL.
There is no reason to migrate the existing MySQL data. Bigtable is over-engineered for a
product catalogue and has no SQL. Spanner is expensive and strong consistency is
unnecessary for a catalogue." \
  "Migrate to Cloud Spanner" \
  "Migrate to Cloud Bigtable" \
  "Keep Cloud SQL and add Memorystore Redis as a cache" \
  "Migrate to Firestore"

ask \
  "Scenario E — Sales Analytics Dashboard" \
  "The finance team needs a dashboard showing sales trends, revenue by region, and
top-selling products over 3 years. The source data is 500 GB of order records. Queries
run complex aggregations and take minutes. The team runs ~10 ad-hoc queries per day.
No requirement for real-time data." \
  "BigQuery" \
  "This is an OLAP (analytical) workload — BigQuery's sweet spot. Its columnar storage
reads only the columns needed for aggregations, making 500 GB queries fast and cheap.
Serverless pricing means you pay per query, not per idle hour. Cloud SQL is an OLTP
engine; complex aggregations over 500 GB would be very slow. Bigtable has no GROUP BY or
aggregation query capability. Spanner is a transactional database — expensive and wrong
for analytics." \
  "Cloud SQL" \
  "Cloud Spanner" \
  "Cloud Bigtable" \
  "BigQuery"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE database questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
