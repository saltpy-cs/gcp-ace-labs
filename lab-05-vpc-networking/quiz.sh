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
echo -e "${BOLD}Lab 05 — VPC Networking Quiz${RESET}"
echo "Five questions on VPC networking concepts."
echo ""

ask \
  "Scenario 1 — Multi-Region Deployment" \
  "Your team needs to deploy workloads in us-central1, us-east1, and europe-west1, all able to communicate using internal IPs without peering or gateways. Which VPC configuration achieves this with the least operational overhead?" \
  "Create one custom-mode VPC and add a subnet in each region." \
  "GCP VPCs are global — a single VPC can have subnets in any region. Traffic between subnets in the same VPC routes internally over Google's network regardless of region. No peering, gateways, or additional VPCs are needed. This is a fundamental difference from AWS, where each VPC is regional and cross-region communication requires Transit Gateway or peering." \
  "Create one custom-mode VPC and add a subnet in each region." \
  "Create three VPCs, one per region, and peer them together." \
  "Create one auto-mode VPC; it automatically provisions subnets in all regions." \
  "Create a regional VPC and use Cloud Interconnect to span the other regions."

ask \
  "Scenario 2 — Firewall Rule Conflict" \
  "A VPC has two firewall rules targeting the same instance for the same traffic (TCP port 443 ingress from 0.0.0.0/0): Rule A is ALLOW at priority 800, and Rule B is DENY at priority 900. What happens to inbound HTTPS traffic to that instance?" \
  "Traffic is allowed. Rule A wins because 800 is a lower number and therefore higher priority." \
  "GCP firewall rule priority is counterintuitive: a lower priority number means higher precedence. Priority 800 is evaluated before priority 900. Since Rule A (ALLOW, 800) is evaluated first and matches, the traffic is allowed. Rule B is never reached. Remember: priority 0 is the highest possible priority, and 65535 is the lowest (where the implied deny-all-ingress lives)." \
  "Traffic is allowed. Rule A wins because 800 is a lower number and therefore higher priority." \
  "Traffic is denied. Rule B wins because DENY always overrides ALLOW regardless of priority." \
  "Traffic is denied. Rule B wins because 900 is a higher number and therefore higher priority." \
  "Both rules apply and traffic is allowed on odd packets, denied on even packets."

ask \
  "Scenario 3 — Private Instance Internet Access" \
  "A VM has no external IP. You need it to: (1) download OS patches from the public internet, and (2) read objects from Cloud Storage. Which combination of features do you need?" \
  "Cloud NAT for patch downloads; Private Google Access for Cloud Storage." \
  "Cloud NAT and Private Google Access are independent features with separate scopes. Cloud NAT translates the VM's internal IP to an external NAT IP for general internet traffic (such as reaching apt.debian.org). Private Google Access routes traffic to Google APIs — including storage.googleapis.com — internally through Google's backbone without the VM needing an external IP or going through NAT. You may need one, both, or neither depending on what the VM needs to reach." \
  "Cloud NAT for patch downloads; Private Google Access for Cloud Storage." \
  "Private Google Access for both; it covers all outbound traffic from private instances." \
  "Cloud NAT for both; enabling NAT also activates Private Google Access automatically." \
  "Assign a temporary external IP for patches, then re-enable Private Google Access for Storage."

ask \
  "Scenario 4 — VPC Peering Topology" \
  "Three VPCs exist: vpc-prod (10.0.0.0/16), vpc-staging (10.1.0.0/16), and vpc-shared-services (10.2.0.0/16). vpc-prod is peered with vpc-shared-services. vpc-staging is peered with vpc-shared-services. A VM in vpc-prod needs to reach a VM in vpc-staging. What must you do?" \
  "Create a direct peering between vpc-prod and vpc-staging on both sides." \
  "GCP does not support transitive peering. Even though vpc-prod and vpc-staging are both peered with vpc-shared-services, that shared peer does not act as a router between them. Traffic from vpc-prod cannot traverse vpc-shared-services to reach vpc-staging. You must establish a direct peering between vpc-prod and vpc-staging. Both sides must create the peering resource; a one-sided peering stays INACTIVE. For large hub-and-spoke topologies, consider Network Connectivity Center instead of a full peering mesh." \
  "Create a direct peering between vpc-prod and vpc-staging on both sides." \
  "Nothing — traffic already routes transitively through vpc-shared-services." \
  "Enable custom route export on vpc-shared-services so it can relay routes between the other two VPCs." \
  "Create a static route in vpc-prod pointing to vpc-staging via the vpc-shared-services peering."

ask \
  "Scenario 5 — Firewall Targeting Security" \
  "A security audit finds that developers can grant themselves SSH access to production VMs by adding a network tag to the instance. Which change eliminates this risk while still allowing SSH access for authorised workloads?" \
  "Replace the tag-based SSH firewall rule with a rule that targets the production service account instead." \
  "Network tags can be added by any user with the compute.instances.setMetadata or compute.instances.addTags permission — a relatively low privilege. Changing a VM's service account requires the iam.serviceAccounts.actAs permission plus compute.instances.setServiceAccount, which is a much higher-privilege operation typically restricted to administrators. By targeting the firewall rule at a specific service account rather than a tag, you ensure that only VMs explicitly configured to run as that service account match the rule. Developers cannot escalate access simply by adding a tag." \
  "Replace the tag-based SSH firewall rule with a rule that targets the production service account instead." \
  "Set all firewall rule priorities to 0 so they cannot be overridden by new rules developers create." \
  "Move the VMs to a separate subnet and restrict the SSH rule to that subnet's CIDR." \
  "Require two firewall rules to match before SSH is allowed, using GCP's dual-rule approval feature."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE networking questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
