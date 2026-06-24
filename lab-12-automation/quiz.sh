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
echo -e "${BOLD}Lab 12 — Automation Quiz${RESET}"
echo "Five questions on GCP automation and infrastructure-as-code concepts."
echo ""

ask \
  "Scenario 1: Cloud Build permissions failure" \
  "Your Cloud Build pipeline fails with a permissions error when attempting to push a container image to Artifact Registry. The cloudbuild.yaml is syntactically correct and worked in a colleague's project. What is the most likely cause?" \
  "The Cloud Build service account (PROJECT_NUMBER@cloudbuild.gserviceaccount.com) has not been granted the roles/artifactregistry.writer role in this project." \
  "Cloud Build runs as the project's Cloud Build service account, not as a human user. Each project has its own service account and its own IAM bindings. The service account needs roles/artifactregistry.writer to push images. The fact that it worked in a colleague's project is irrelevant — IAM bindings are project-scoped." \
  "The Cloud Build service account (PROJECT_NUMBER@cloudbuild.gserviceaccount.com) has not been granted the roles/artifactregistry.writer role in this project." \
  "The cloudbuild.yaml is referencing the wrong Artifact Registry hostname — it should use gcr.io instead of REGION-docker.pkg.dev." \
  "Cloud Build workers do not have internet access by default, so they cannot reach Artifact Registry." \
  "The Artifact Registry API is enabled in the colleague's project but not in yours — enable it and the push will work without any IAM changes."

ask \
  "Scenario 2: Substitutions in a shell script inside a build step" \
  "You are writing a cloudbuild.yaml build step that runs a bash script. Inside that script you need to use a shell variable named MY_VAR that you set with export. You also need to reference the Cloud Build built-in variable for the commit SHA. Which syntax is correct inside the shell script?" \
  "Use \$\$MY_VAR for the shell variable and \$\$SHORT_SHA for the Cloud Build substitution, so Cloud Build does not substitute them before the shell sees them." \
  "Cloud Build processes the cloudbuild.yaml and substitutes all single-dollar-sign variables (like \$SHORT_SHA) before the shell runs. If you use \$SHORT_SHA inside a shell script embedded in the YAML, Cloud Build replaces it with the actual SHA — which is what you want for the built-in variable. However, for a shell variable you define at runtime (\$MY_VAR), you must use double dollars (\$\$MY_VAR) to escape it so Cloud Build passes the literal string \$MY_VAR to the shell. In this scenario you want BOTH to be resolved by the shell at runtime, so both need double dollars." \
  "Use \$MY_VAR for the shell variable and \$SHORT_SHA for the Cloud Build substitution — single dollars work for both." \
  "Use \$\$MY_VAR for the shell variable and \$\$SHORT_SHA for the Cloud Build substitution, so Cloud Build does not substitute them before the shell sees them." \
  "Use \$MY_VAR for the shell variable and \$\$SHORT_SHA for the Cloud Build substitution — built-in variables always need escaping." \
  "Use \${MY_VAR} and \${SHORT_SHA} — curly braces prevent Cloud Build from substituting either variable."

ask \
  "Scenario 3: Choosing between Pub/Sub and Cloud Tasks" \
  "You are building a system where a single upstream service emits an event whenever an order is placed. Three downstream services — inventory, billing, and notifications — must each independently process every order event. Which GCP messaging service is the right choice and why?" \
  "Pub/Sub, because it supports fan-out: one topic with three separate subscriptions means each downstream service gets its own independent copy of every message." \
  "Pub/Sub topics fan out to all subscriptions — every subscription gets a copy of every message published after the subscription was created. This is exactly the fan-out pattern required here. Cloud Tasks is point-to-point: one task goes to one handler. Using Cloud Tasks would require the upstream service to explicitly enqueue a separate task for each of the three downstream services, coupling the producer to the consumer count." \
  "Cloud Tasks, because it provides fine-grained rate control that prevents the downstream services from being overwhelmed." \
  "Pub/Sub, because it supports fan-out: one topic with three separate subscriptions means each downstream service gets its own independent copy of every message." \
  "Cloud Tasks, because it guarantees exactly-once delivery, which Pub/Sub does not." \
  "Pub/Sub push subscriptions, but only if all three downstream services are hosted on Cloud Run — otherwise pull subscriptions must be used instead."

ask \
  "Scenario 4: Cloud Deployment Manager vs Terraform on the ACE exam" \
  "A question on your ACE exam asks: 'You need to provision GCP infrastructure declaratively using only native GCP tooling — no third-party tools. Your configuration must support Jinja2 templates for parameterisation. Which service should you use?' What is the correct answer?" \
  "Cloud Deployment Manager — it is GCP's native IaC service, uses YAML with optional Jinja2 or Python templates, and manages state within GCP itself." \
  "The ACE exam tests Cloud Deployment Manager, not Terraform (Terraform appears on the Professional Cloud DevOps Engineer exam). CDM is described in the question's constraints: native GCP tooling, Jinja2 support. Key differentiators: CDM uses YAML + Jinja2/Python, stores state in GCP (no external state file), and commands are gcloud deployment-manager deployments create/update/delete." \
  "Terraform with the google provider — it has better GCP coverage than Cloud Deployment Manager and a larger community." \
  "Cloud Build — you can write a cloudbuild.yaml that runs gcloud commands to create resources declaratively." \
  "Cloud Deployment Manager — it is GCP's native IaC service, uses YAML with optional Jinja2 or Python templates, and manages state within GCP itself." \
  "Config Connector — it is the Kubernetes-native way to manage GCP resources declaratively using YAML manifests."

ask \
  "Scenario 5: Cloud Deploy vs direct Cloud Build deployment" \
  "Your team is deploying a microservice to Cloud Run. You have three environments: dev, staging, and prod. Production deployments must be approved by a release manager before they proceed, and your compliance team requires a full audit trail of every promotion. Which deployment approach is most appropriate?" \
  "Cloud Deploy with a delivery pipeline defining dev, staging, and prod as targets — it provides built-in promotion gates, manual approval steps, and an audit trail of every release and promotion." \
  "Cloud Deploy is designed exactly for this scenario: ordered promotion through multiple environments, optional manual approval gates between stages, and a built-in audit trail (who promoted what to where, when). Direct Cloud Build deployment to Cloud Run is simpler but lacks promotion gates and structured audit history — it is appropriate for single-environment deployments where those controls are not needed." \
  "Cloud Build with separate triggers per environment — a push to the 'dev' branch deploys to dev, a push to 'staging' deploys to staging, and a push to 'prod' deploys to prod." \
  "Cloud Deploy with a delivery pipeline defining dev, staging, and prod as targets — it provides built-in promotion gates, manual approval steps, and an audit trail of every release and promotion." \
  "Cloud Scheduler — schedule nightly deployments to each environment in sequence, with a manual step between staging and prod." \
  "Cloud Run traffic splitting — deploy to a single service and use traffic splitting to shift traffic from old to new revisions, with manual approval handled outside GCP."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE automation questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
