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
echo -e "${BOLD}Lab 04 — IAM Quiz${RESET}"
echo "Five questions on Identity and Access Management concepts."
echo ""

ask \
  "Scenario 1 — Unexpected Access" \
  "A junior developer, Alice, reports that she can list and read objects in every Cloud Storage bucket across all projects in your organisation, even though her team's project has no IAM bindings for her. Which is the most likely explanation?" \
  "Alice has a role granted at the organisation or folder level, which is inherited by all child projects." \
  "GCP IAM policy inheritance flows downward through the hierarchy: Organisation → Folder → Project → Resource. A binding at a parent level applies to every child. Children cannot revoke what a parent grants. The correct diagnostic step is to check 'gcloud organizations get-iam-policy' and 'gcloud resource-manager folders get-iam-policy', not just the project policy." \
  "Alice has a role granted at the organisation or folder level, which is inherited by all child projects." \
  "Someone must have granted Alice the role directly on each individual bucket." \
  "The default Compute Engine service account has broad access, and Alice is benefiting from it." \
  "allAuthenticatedUsers has been granted viewer access on the project, so any Google account has read access."

ask \
  "Scenario 2 — Authenticating from a VM" \
  "Your application runs on a Compute Engine instance and needs to write objects to a Cloud Storage bucket. A colleague suggests downloading a JSON service account key and placing it on the VM. What is the recommended approach instead, and why?" \
  "Attach a service account to the VM and use the metadata server; the application obtains short-lived tokens automatically without any key file on disk." \
  "VMs on GCE can authenticate as an attached service account via the metadata server at 169.254.169.254. The token is short-lived and rotated automatically, so there is nothing to leak or expire. JSON key files are long-lived, can be copied off the VM, and are the leading cause of credential leaks in GCP. Setting --scopes=cloud-platform on the instance means IAM roles on the attached SA are the sole access gate." \
  "Attach a service account to the VM and use the metadata server; the application obtains short-lived tokens automatically without any key file on disk." \
  "Download a JSON key file, store it in a Secret Manager secret, and have the VM fetch it on startup." \
  "Use 'gcloud auth application-default login' on the VM to generate long-lived credentials." \
  "Grant the VM's default Compute Engine service account roles/storage.objectAdmin at the project level."

ask \
  "Scenario 3 — Role Selection" \
  "You need to give a service account the ability to read and list objects in a specific Cloud Storage bucket. The predefined role roles/storage.objectViewer grants slightly more access than you want. Which approach best follows the principle of least privilege?" \
  "Create a custom IAM role with only storage.objects.get and storage.objects.list, and bind it to the service account on the bucket, not the project." \
  "Custom roles let you specify exactly the permissions needed — no more. Binding at the bucket level (rather than the project level) further narrows the scope: the SA can only act on that bucket. Primitive roles like roles/viewer are far too broad. Predefined roles are a good default but custom roles exist precisely for when they are still wider than required." \
  "Create a custom IAM role with only storage.objects.get and storage.objects.list, and bind it to the service account on the bucket, not the project." \
  "Grant roles/storage.objectViewer at the project level — the extra permissions it includes are read-only so there is no real risk." \
  "Grant roles/viewer at the project level since it is the narrowest primitive role." \
  "Grant roles/storage.objectAdmin on the bucket so the service account can manage the objects it reads."

ask \
  "Scenario 4 — Service Account Dual Nature" \
  "A developer needs to be able to start VMs that run as a specific service account (deploy-sa), but should NOT be able to generate tokens and impersonate deploy-sa directly from their workstation. Which role should you grant the developer, and on which resource?" \
  "Grant roles/iam.serviceAccountUser on the deploy-sa service account resource (not the project)." \
  "roles/iam.serviceAccountUser allows a principal to attach a service account to a VM or other compute resource — it does not allow token generation or direct impersonation. roles/iam.serviceAccountTokenCreator is the more powerful role that allows generating tokens (impersonation). Granting either role on the SA resource (rather than at project level) limits the scope to just that SA. Service accounts are simultaneously an identity (principal) and a resource that has its own IAM policy." \
  "Grant roles/iam.serviceAccountUser on the deploy-sa service account resource (not the project)." \
  "Grant roles/iam.serviceAccountTokenCreator on the deploy-sa service account resource." \
  "Grant roles/iam.serviceAccountUser at the project level so the developer can use any service account." \
  "Grant roles/iam.serviceAccountTokenCreator at the project level so the developer can impersonate deploy-sa."

ask \
  "Scenario 5 — Audit Logs" \
  "A security incident response team needs to determine who modified an IAM policy on a project at 14:32 UTC yesterday, and confirm whether any service accounts were created in the same window. Which log type should they query, and do they need to enable anything first?" \
  "Query Admin Activity audit logs in Cloud Logging — they are always enabled, always free, and record all IAM policy changes and service account creation." \
  "Admin Activity logs capture configuration changes including SetIamPolicy and CreateServiceAccount API calls. They are always on and cannot be disabled — no setup required. Data Access logs (who read or wrote data) are a separate category that must be explicitly enabled per service and incur cost. System Event logs record Google-initiated actions like live migration. For the question asked — 'who changed this IAM policy?' — Admin Activity logs are the definitive source." \
  "Query Admin Activity audit logs in Cloud Logging — they are always enabled, always free, and record all IAM policy changes and service account creation." \
  "Query Data Access audit logs — these record all API calls including IAM changes and must be enabled before the incident to be useful." \
  "Query System Event audit logs — they record all administrative actions taken within a project." \
  "Export VPC Flow Logs to BigQuery and correlate timestamps with IAM API calls to reconstruct the change."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE IAM questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
