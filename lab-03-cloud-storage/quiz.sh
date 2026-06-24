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
echo -e "${BOLD}Lab 03 — Cloud Storage Quiz${RESET}"
echo "Five questions on Cloud Storage concepts."
echo ""

ask \
  "Scenario 1 — Storage class selection" \
  "Your company stores financial audit logs that must be retained for 7 years to satisfy a regulatory requirement. The logs are written once and almost never read — perhaps once every 18 months during an audit. Storage cost must be minimized. Which storage class should you use, and what is the key cost risk to communicate to stakeholders?" \
  "Archive — lowest monthly cost at \$0.0012/GB, but retrieval costs \$0.050/GB and there is a 365-day minimum storage duration billing penalty for early deletion" \
  "Archive is designed for data accessed less than once per year, exactly matching the ~18-month read cadence. At \$0.0012/GB/month it is the cheapest option. The critical gotchas are the \$0.050/GB retrieval fee (dwarfs storage savings if reads become frequent) and the 365-day minimum storage duration — deleting an object after 2 days still bills 365 days of storage. Coldline would cost more per GB stored (\$0.004 vs \$0.0012) for no benefit given the access pattern." \
  "Coldline — lowest retrieval cost among infrequent-access classes at \$0.020/GB" \
  "Nearline — 30-day minimum storage duration keeps early-deletion penalties low" \
  "Archive — lowest monthly cost at \$0.0012/GB, but retrieval costs \$0.050/GB and there is a 365-day minimum storage duration billing penalty for early deletion" \
  "Standard — no retrieval fee eliminates surprise costs during the annual audit"

ask \
  "Scenario 2 — Uniform vs fine-grained access" \
  "An auditor flags that some objects in a GCS bucket are publicly accessible even though the bucket's IAM policy grants no public access. You investigate and find per-object ACLs were set by a legacy ETL pipeline. You want to eliminate per-object ACLs permanently across the entire bucket. What do you do, and what is the long-term implication?" \
  "Enable uniform bucket-level access — this disables and ignores all per-object ACLs. After 90 consecutive days it locks automatically and cannot be reversed." \
  "Uniform bucket-level access disables per-object ACLs entirely: existing ACLs are ignored and no new ones can be set. All access is then controlled solely through Cloud IAM at the bucket or project level, giving a single authoritative place to audit. The 90-day lock is intentional for compliance — it prevents an attacker or careless operator from re-enabling fine-grained mode to sneak in a per-object ACL. The exam tests this 90-day behavior explicitly." \
  "Delete and recreate the bucket with --uniform-bucket-level-access — the only way to enforce it is at creation time" \
  "Run gcloud storage objects update --clear-acl on every object — uniform mode is not needed once ACLs are cleared" \
  "Enable uniform bucket-level access — this disables and ignores all per-object ACLs. After 90 consecutive days it locks automatically and cannot be reversed." \
  "Set an organization policy constraint to deny ACL writes — this is more scalable than bucket-level settings"

ask \
  "Scenario 3 — Object versioning and lifecycle rules" \
  "You enable object versioning on a bucket that stores daily database backups. Three months later your storage bill has tripled. What is the most likely cause, and what is the correct fix using only lifecycle rules (no manual deletion)?" \
  "Noncurrent (overwritten) versions are accumulating and each version is billed as regular storage. Fix: add a lifecycle rule with condition numNewerVersions: 1 and isLive: false to delete noncurrent versions." \
  "Every time a backup is overwritten, the previous version becomes noncurrent but remains stored and billed. After 90 days of daily overwrites, each object has ~90 billed versions instead of 1. The lifecycle condition numNewerVersions: 1 combined with isLive: false means: delete this noncurrent version when at least 1 newer live version exists — effectively keeping only the current version. You could also use numNewerVersions: N to retain the last N versions for rollback purposes." \
  "Versioning is writing duplicate live objects into the bucket. Fix: disable versioning and set a lifecycle rule to delete objects older than 1 day." \
  "The bucket default storage class has changed to Standard. Fix: add a lifecycle rule to transition all objects to Nearline after 1 day." \
  "Noncurrent (overwritten) versions are accumulating and each version is billed as regular storage. Fix: add a lifecycle rule with condition numNewerVersions: 1 and isLive: false to delete noncurrent versions." \
  "Lifecycle rules are being evaluated twice per day. Fix: set the condition age: 1 to prevent premature evaluation."

ask \
  "Scenario 4 — Signed URLs" \
  "A partner company needs to download a single confidential PDF from your private GCS bucket. They have no Google account and your security policy prohibits adding external identities to Cloud IAM. The access should expire automatically after 48 hours. What is the correct solution, and what is the correct way to revoke access before expiration if needed?" \
  "Generate a signed URL valid for 48 hours using a service account. To revoke early, rotate (delete and recreate) the service account key used to sign the URL." \
  "Signed URLs encode the expiration time and a cryptographic signature from the service account key. They require no GCP account on the recipient's side — access is controlled by possession of the URL. Because the signature is computed client-side at generation time, GCS has no server-side record of issued URLs. The only way to invalidate an unexpired signed URL is to rotate the signing service account key, which invalidates all URLs signed with that key. Temporary public access (allUsers) would expose the object to everyone, not just the partner." \
  "Make the object publicly readable via allUsers IAM binding, share the direct storage.googleapis.com URL, and remove the allUsers binding after 48 hours." \
  "Create a temporary GCP service account for the partner, grant it roles/storage.objectViewer on the specific object, and delete the account after 48 hours." \
  "Generate a signed URL valid for 48 hours using a service account. To revoke early, rotate (delete and recreate) the service account key used to sign the URL." \
  "Enable CORS on the bucket with a 48-hour maxAgeSeconds and share the object's direct URL — CORS expiry controls access duration."

ask \
  "Scenario 5 — Location types and availability" \
  "Your team is deploying a latency-sensitive application on Compute Engine in us-central1. The application reads and writes large objects from GCS continuously. A manager asks you to switch the GCS bucket from regional (us-central1) to multi-region (us) to get the higher 99.99% availability SLA. What tradeoffs should you raise before making this change?" \
  "Multi-region costs more per GB and may incur inter-region egress fees if data is served from a region other than us-central1. For a workload co-located in us-central1, regional gives lower latency, lower cost, and the data never leaves the region — the 99.9% vs 99.99% SLA difference is unlikely to matter." \
  "For workloads tightly coupled to a single Compute Engine region, a regional bucket offers data co-location (lowest latency, no egress charges), deterministic data residency, and lower storage cost. Multi-region distributes data across geographically separated regions — useful for global audiences but unnecessary (and more expensive) when all access originates in one region. The 99.9% regional SLA is still very high. Dual-region with turbo replication is the right middle ground if you need both a strong RPO SLA and data residency control." \
  "The change is safe and cost-neutral — multi-region and regional buckets have identical pricing, and the higher SLA justifies the switch with no downsides." \
  "Multi-region buckets do not support object versioning, so the existing versioning configuration would be lost during the migration." \
  "Multi-region costs more per GB and may incur inter-region egress fees if data is served from a region other than us-central1. For a workload co-located in us-central1, regional gives lower latency, lower cost, and the data never leaves the region — the 99.9% vs 99.99% SLA difference is unlikely to matter." \
  "Switching to multi-region requires re-uploading all objects — GCS does not support in-place storage class or location changes at the bucket level."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE Cloud Storage questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
