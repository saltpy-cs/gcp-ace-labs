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
echo -e "${BOLD}Lab 11 — Security Quiz${RESET}"
echo "Five questions on GCP security concepts."
echo ""

ask \
  "Scenario 1 — CMEK Break-Glass" \
  "A financial services company stores regulated customer data in a Cloud Storage bucket protected by CMEK. A security breach is detected and the team needs to immediately make all data in the bucket inaccessible while the investigation runs, with the option to restore access later once the threat is contained. What is the correct action?" \
  "Disable the KMS key version used to encrypt the bucket objects" \
  "Disabling a KMS key version is reversible — it makes data temporarily inaccessible and can be re-enabled once the threat is contained. Destroying the key version would also halt access, but it is irreversible: the data would be permanently unrecoverable. Revoking the GCS service agent's IAM role would also block access, but does not prevent anyone who already has the plaintext key material from decrypting data. Deleting the bucket immediately destroys the data — not appropriate while evidence may be needed for investigation." \
  "Destroy the KMS key version used to encrypt the bucket objects" \
  "Disable the KMS key version used to encrypt the bucket objects" \
  "Revoke the GCS service agent's cloudkms.cryptoKeyEncrypterDecrypter role on the key" \
  "Delete the Cloud Storage bucket"

ask \
  "Scenario 2 — Secret Manager vs Cloud KMS" \
  "Your application running on Cloud Run needs to read a database password at startup. A separate compliance requirement mandates that all secrets stored in GCP must be encrypted with a customer-managed key so your organisation retains the ability to revoke access. Which combination of services satisfies both requirements?" \
  "Store the password in Secret Manager; configure the secret to use a Cloud KMS CMEK key for encryption" \
  "Secret Manager is the correct service for storing secret values such as database passwords — it provides versioning, access control at the secret level, and audit logging of every access. Cloud KMS is for managing encryption keys and performing cryptographic operations, not for storing secret values directly. Combining the two (encrypting the Secret Manager secret with a CMEK key) satisfies the compliance requirement: you own the encryption key and can revoke access by disabling it. Storing the password directly as a KMS-encrypted blob in GCS is operationally complex and does not provide the versioning or fine-grained access control that Secret Manager offers." \
  "Store the password in Cloud KMS as an ENCRYPT_DECRYPT key; grant Cloud Run the cryptoKeyDecrypter role" \
  "Store the password in Secret Manager; use GMEK (default Google-managed encryption)" \
  "Store the password in Secret Manager; configure the secret to use a Cloud KMS CMEK key for encryption" \
  "Encrypt the password with gcloud kms encrypt and store the ciphertext in Cloud Storage"

ask \
  "Scenario 3 — Cloud Armor Rule Evaluation" \
  "A Cloud Armor security policy has the following rules: priority 300 — allow 10.0.0.0/8; priority 500 — deny(403) 10.20.0.0/16; priority 2147483647 — deny(403) all. A request arrives from IP address 10.20.5.10. What response does Cloud Armor return?" \
  "200 OK — the request is allowed" \
  "Cloud Armor evaluates rules in ascending priority order — lower number means higher precedence. Priority 300 is evaluated before priority 500. The source IP 10.20.5.10 falls within 10.0.0.0/8 (it matches the /8 range), so rule 300 matches first and the request is allowed. Rule 500 (which would deny 10.20.0.0/16) is never reached because the first matching rule wins. This is a common ACE exam trap: a more-specific deny rule at a higher priority number loses to a less-specific allow rule at a lower priority number." \
  "200 OK — the request is allowed" \
  "403 Forbidden — matched by the deny rule at priority 500" \
  "403 Forbidden — matched by the default deny rule at priority 2147483647" \
  "The request is dropped with no response — Cloud Armor blocks it at the network layer"

ask \
  "Scenario 4 — OS Login vs Metadata SSH Keys" \
  "A company's security audit finds that a former employee still has SSH access to several Compute Engine VMs, two weeks after their Google account was disabled by the identity provider. The admin confirms the employee's account is disabled in the IdP. What is the most likely cause, and what is the recommended fix going forward?" \
  "SSH keys are stored in project metadata and are not tied to account status; enable OS Login so access is controlled by IAM and Google account state" \
  "By default, Compute Engine manages SSH access through public keys stored in project or instance metadata. These keys persist independently of Google account status — disabling the IdP account does not remove metadata keys. OS Login replaces metadata-based SSH key management with IAM: access is granted via roles/compute.osLogin or roles/compute.osAdminLogin, and it is controlled by the user's Google account. When the account is disabled by the IdP, the IAM bindings become inactive and SSH access is automatically revoked. This is the recommended approach for managing SSH access at scale." \
  "The employee exported their private key before leaving; rotate all SSH key pairs immediately" \
  "SSH keys are stored in project metadata and are not tied to account status; enable OS Login so access is controlled by IAM and Google account state" \
  "IAM permissions were not revoked correctly; remove the employee's roles/compute.instanceAdmin binding" \
  "The VMs are using Shielded VM with vTPM which bypasses standard authentication; disable vTPM"

ask \
  "Scenario 5 — VPC Service Controls vs IAM" \
  "A security team discovers that a data analyst with legitimate BigQuery access has been copying query results to a GCS bucket in a personal external project, exfiltrating sensitive data. The team wants to prevent this class of attack even if an analyst's credentials are later compromised. IAM policies already follow least-privilege. What additional control should be implemented?" \
  "VPC Service Controls — create a service perimeter around BigQuery and the company's GCS buckets to block cross-perimeter data movement" \
  "VPC Service Controls (VPC-SC) enforce perimeter boundaries around GCP services and projects, blocking API calls that would move data across the perimeter regardless of IAM permissions. A user with legitimate BigQuery access cannot copy data to a GCS bucket outside the perimeter even if they have write access to that external bucket — the BigQuery API call itself is blocked at the perimeter boundary. IAM alone cannot prevent this because the analyst has legitimate access; IAM controls who can access a resource, while VPC-SC controls from where. Cloud Armor operates at L7 on HTTP(S) load balancers and cannot inspect BigQuery API calls. Security Command Center can detect the exfiltration after the fact but does not prevent it." \
  "Cloud Armor — add a WAF rule to block BigQuery export API calls from analyst IP ranges" \
  "Security Command Center — enable Event Threat Detection to alert on anomalous data access patterns" \
  "VPC Service Controls — create a service perimeter around BigQuery and the company's GCS buckets to block cross-perimeter data movement" \
  "Binary Authorization — enforce that only approved container images can run jobs that access BigQuery"

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE security questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
