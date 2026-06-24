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
echo -e "${BOLD}Lab 01 — Foundations Quiz${RESET}"
echo "Five questions on GCP foundations concepts."
echo ""

ask \
  "Question 1 — IAM Inheritance" \
  "Your security team needs to ensure that a new engineer can read logs across all 40 projects in the 'Engineering' folder, but must not have write access to any of them. The engineer should automatically get access to new projects added to the folder in the future. What is the most operationally efficient approach?" \
  "Grant roles/logging.viewer on the Engineering folder." \
  "IAM policies are inherited downward through the resource hierarchy. Granting a role on a folder automatically applies it to all current and future projects within that folder — no per-project bindings are needed. Granting on each project individually is operationally expensive and misses future projects. Granting at the organisation level is too broad (covers projects outside Engineering). You cannot block inherited IAM, so assigning a broader role at a higher level and trying to restrict below it would not work — IAM is additive only." \
  "Grant roles/logging.viewer on each of the 40 projects individually." \
  "Grant roles/logging.viewer on the Engineering folder." \
  "Grant roles/logging.viewer at the organisation level and use a deny policy on other folders." \
  "Grant roles/viewer on the Engineering folder so the engineer can read all resource types."

ask \
  "Question 2 — Authentication Method Selection" \
  "A Python application runs on a Compute Engine VM and needs to read objects from Cloud Storage. A colleague suggests putting a service account JSON key file on the VM. You disagree. What is the most secure alternative and why is the key file approach problematic?" \
  "Attach a service account directly to the VM; the metadata server provides short-lived credentials automatically." \
  "Attaching a service account to a VM (or using Workload Identity for GKE) means the metadata server automatically issues short-lived, auto-rotating credentials — no key file is stored anywhere. A JSON key file is a long-lived secret that never expires unless manually rotated; if the file is exposed (e.g. committed to git, copied in a snapshot), an attacker has permanent access until you revoke it. ADC (gcloud auth application-default login) is for local developer machines, not production VMs. User credentials on a server are inappropriate and tied to an individual's account." \
  "Run gcloud auth application-default login on the VM during startup so ADC is available." \
  "Store the JSON key file in Secret Manager and fetch it at runtime to reduce exposure." \
  "Attach a service account directly to the VM; the metadata server provides short-lived credentials automatically." \
  "Use gcloud auth login on the VM and configure the application to call gcloud to get tokens."

ask \
  "Question 3 — Resource Scope" \
  "A team runs a stateful application across two VMs: one in europe-west2-a and one in europe-west2-b. They want both VMs to share access to the same persistent disk for a read-heavy workload. A junior engineer suggests creating a pd-ssd disk in europe-west2-a and attaching it to both VMs. What is wrong with this plan?" \
  "Persistent disks are zonal resources; a disk in europe-west2-a cannot be attached to a VM in europe-west2-b." \
  "Persistent disks are zonal resources, tied to a single zone. A pd-ssd disk created in europe-west2-a can only be attached to VMs that also reside in europe-west2-a — it is not accessible from europe-west2-b. For cross-zone shared storage, alternatives include Cloud Filestore (which is regional) or Cloud Storage (which is global). Even within the same zone, a standard persistent disk can only be attached to multiple VMs in read-only mode; read-write multi-attach requires a specific Hyperdisk Multi configuration. The scope mismatch between the disk zone and the VM zone is the fundamental problem here." \
  "pd-ssd disks do not support multi-attach; only pd-standard disks can be shared between VMs." \
  "Persistent disks are zonal resources; a disk in europe-west2-a cannot be attached to a VM in europe-west2-b." \
  "The VMs must be in the same VPC network before a shared disk can be attached to both." \
  "Cloud Storage must be used instead because persistent disks cannot be shared across projects."

ask \
  "Question 4 — Labels vs Network Tags" \
  "A platform team manages 200 VMs across several projects. They need to: (a) apply a firewall rule that only allows inbound HTTPS traffic to VMs running web applications, and (b) generate a monthly cost report broken down by application tier (web, api, database). Which combination of mechanisms should they use?" \
  "Network tags to target the firewall rule; labels to track tiers for billing reports." \
  "Network tags are string identifiers applied to VM instances that firewall rules use as targets — a rule with target tag 'web-server' applies only to VMs carrying that tag. Labels are key-value metadata (e.g. tier=web) that GCP billing exports and the Cloud Billing console can use to break down costs by label value. Using labels for firewall targeting would not work — firewall rules do not read labels. Using network tags for billing would not work — billing data does not track network tags. These are entirely separate mechanisms that serve different purposes." \
  "Labels to target the firewall rule; network tags to track tiers for billing reports." \
  "Network tags for both — they can be used in firewall rules and filtered in billing exports." \
  "Labels for both — they can be used in firewall rules when combined with IAM conditions." \
  "Network tags to target the firewall rule; labels to track tiers for billing reports."

ask \
  "Question 5 — API Enablement and Project Identifiers" \
  "A developer with the roles/compute.admin role on a project tries to create a VM using the gcloud CLI and receives a PERMISSION_DENIED error. The project was created yesterday and the developer's IAM binding was confirmed correct by the security team. What are the two most likely causes to investigate first?" \
  "The Compute Engine API is not enabled on the project, or billing is not linked to the project." \
  "Two common causes of PERMISSION_DENIED errors that are unrelated to IAM role bindings: (1) The Compute Engine API (compute.googleapis.com) may not be enabled — GCP requires explicit API enablement per project before any calls to that service succeed, and the error message for a disabled API is PERMISSION_DENIED, which is misleading. (2) Billing may not be linked to the project — without an active billing account, resource-creating operations are blocked even for owners. Both are project-level prerequisites independent of IAM. The project ID being wrong would cause a 'project not found' error, not PERMISSION_DENIED. A missing zone default would cause a prompt for input, not an error." \
  "The developer is using the wrong project ID in their gcloud config, or their ADC token has expired." \
  "The Compute Engine API is not enabled on the project, or billing is not linked to the project." \
  "The developer needs roles/owner instead of roles/compute.admin to create the first VM in a new project." \
  "The default compute/zone is not set in the developer's gcloud configuration."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE foundations questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
