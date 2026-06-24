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
echo -e "${BOLD}Lab 07 — GKE Quiz${RESET}"
echo "Five questions on Google Kubernetes Engine concepts."
echo ""

ask \
  "Scenario 1 — Cluster Mode Selection" \
  "Your team is deploying a stateless web application to GKE. The app has no GPU requirements and no need for privileged containers. A security audit requires that pods cannot run as root and that host namespaces are blocked. Which GKE cluster mode best fits these requirements and minimises operational overhead?" \
  "GKE Autopilot — it enforces hardened security defaults (no root, no host namespaces) and Google manages the nodes, eliminating node pool operations." \
  "Autopilot is the right choice here: it automatically enforces the security constraints the audit requires (no root, no host namespaces, no privilege escalation), and because Google manages nodes, there is no node pool configuration or patching overhead. Standard would require you to configure those security policies yourself. Autopilot's zero-idle-cost model is also a bonus for a stateless app." \
  "GKE Autopilot — it enforces hardened security defaults (no root, no host namespaces) and Google manages the nodes, eliminating node pool operations." \
  "GKE Standard with a custom node pool — you can configure securityContext on every pod manually to block root access." \
  "GKE Standard with a Rapid upgrade channel — the latest Kubernetes release includes the strictest Pod Security Standards." \
  "GKE Autopilot with a node taint — tainting the node pool prevents privileged pods from scheduling."

ask \
  "Scenario 2 — Service Type and Load Balancer Choice" \
  "Your company runs five HTTP microservices on GKE, each previously exposed with 'type: LoadBalancer'. The platform team wants to reduce costs and consolidate external exposure under a single IP with path-based routing. Which change achieves this most efficiently?" \
  "Replace all five LoadBalancer Services with ClusterIP Services and create a single Kubernetes Ingress, which provisions one GCP HTTP(S) Load Balancer shared across all five services." \
  "A 'type: LoadBalancer' Service provisions a separate GCP L4 Network Load Balancer for each service — five services means five NLBs, each with its own cost and IP. A Kubernetes Ingress in GKE provisions a single GCP HTTP(S) (L7) Load Balancer that can route to multiple backend Services based on hostname and URL path, sharing one external IP. The backend Services should be ClusterIP (reachable only inside the cluster), with the Ingress as the single external entry point." \
  "Replace all five LoadBalancer Services with ClusterIP Services and create a single Kubernetes Ingress, which provisions one GCP HTTP(S) Load Balancer shared across all five services." \
  "Replace all five LoadBalancer Services with NodePort Services — NodePort is cheaper because it does not create a GCP load balancer." \
  "Keep all five LoadBalancer Services but put a GCP Traffic Director in front of them to merge the IPs into one." \
  "Replace all five LoadBalancer Services with a single LoadBalancer Service and use path-based routing inside the service selector."

ask \
  "Scenario 3 — Workload Identity Setup" \
  "A pod needs to read objects from Cloud Storage. Your security policy prohibits mounting service account JSON key files. You annotate the Kubernetes Service Account (KSA) with 'iam.gke.io/gcp-service-account=my-sa@project.iam.gserviceaccount.com', but the pod still receives a 403 error when calling the GCS API. What is the most likely missing step?" \
  "The GCP Service Account has not been granted 'roles/iam.workloadIdentityUser' for the KSA member 'serviceAccount:PROJECT_ID.svc.id.goog[namespace/ksa-name]'." \
  "Workload Identity requires three things: (1) the cluster must be created with '--workload-pool=PROJECT_ID.svc.id.goog', (2) the KSA must be annotated with 'iam.gke.io/gcp-service-account', and (3) the GCP SA must be granted 'roles/iam.workloadIdentityUser' for the KSA identity. Annotating the KSA alone is not enough — the GCP SA must also be configured to trust that KSA via the IAM binding. Missing the workloadIdentityUser role means the GKE token exchange is rejected and the pod falls back to the node's default service account, which has no GCS permission." \
  "The GCP Service Account has not been granted 'roles/iam.workloadIdentityUser' for the KSA member 'serviceAccount:PROJECT_ID.svc.id.goog[namespace/ksa-name]'." \
  "The pod's container image does not include the Cloud Storage client library — the library must be bundled in the image for Workload Identity to work." \
  "The KSA annotation uses the wrong format — it should reference the GCP SA's numeric ID, not the email address." \
  "The GCP Service Account must also be annotated with 'iam.gke.io/kubernetes-service-account' pointing back to the KSA to complete the bidirectional binding."

ask \
  "Scenario 4 — ConfigMap and Secret Update Propagation" \
  "A Deployment mounts a ConfigMap key 'config.yaml' as a file at '/etc/app/config.yaml' AND injects a separate ConfigMap key 'LOG_LEVEL' as an environment variable. An operator updates both keys in the ConfigMap. Which statement correctly describes what happens to the running pods?" \
  "The '/etc/app/config.yaml' file inside running pods updates automatically within about 60 seconds. The LOG_LEVEL environment variable does NOT update — it retains the value from when the pod started." \
  "Environment variables are set once at pod startup from a snapshot of the ConfigMap. Changing the ConfigMap does not push a new value into the running process — the env var is frozen. Volume-mounted ConfigMap files, however, are periodically re-synced by the kubelet; the file on disk updates within roughly 60 seconds of the ConfigMap change. To propagate an env var change, you must restart the pods (e.g. 'kubectl rollout restart deployment'). This asymmetry applies equally to Secrets mounted as files vs injected as env vars." \
  "The '/etc/app/config.yaml' file inside running pods updates automatically within about 60 seconds. The LOG_LEVEL environment variable does NOT update — it retains the value from when the pod started." \
  "Neither the file nor the environment variable updates — Kubernetes never mutates a running pod; you must delete and recreate all pods." \
  "Both the file and the environment variable update automatically within 60 seconds — kubelet syncs all ConfigMap data into running pods on the same schedule." \
  "The environment variable updates immediately via inotify, but the file update requires a pod restart because the volume mount is cached by the container runtime."

ask \
  "Scenario 5 — HPA vs Cluster Autoscaler" \
  "A GKE Standard cluster has a Horizontal Pod Autoscaler configured for a Deployment with min=2, max=20 replicas at 60% CPU target. During a traffic spike, the HPA scales the Deployment to 15 replicas, but 5 of the new pods remain in 'Pending' state for several minutes. 'kubectl describe pod' on a Pending pod shows: 'Insufficient cpu'. Cluster autoscaling is NOT enabled on the node pool. What is the correct diagnosis and fix?" \
  "The node pool has no remaining CPU capacity for the 5 pending pods. Enable cluster autoscaling on the node pool ('--enable-autoscaling') so GKE can add nodes when pods cannot be scheduled." \
  "HPA and the cluster autoscaler are complementary but independent. HPA adjusts the number of pod replicas based on metrics — it does not add nodes. The cluster autoscaler watches for Pending pods and adds nodes to satisfy their resource requests. Without cluster autoscaling, the HPA can scale up to 20 replicas but pods will stay Pending if the existing nodes are full. The fix is to enable cluster autoscaling on the node pool. In Autopilot, both layers scale automatically and this scenario cannot occur." \
  "The node pool has no remaining CPU capacity for the 5 pending pods. Enable cluster autoscaling on the node pool ('--enable-autoscaling') so GKE can add nodes when pods cannot be scheduled." \
  "The HPA max of 20 is too high — reduce it to match the current node capacity so the HPA stops scheduling pods the cluster cannot run." \
  "The Pending pods need a 'PriorityClass' set to high priority so the Kubernetes scheduler evicts lower-priority pods and frees CPU for them." \
  "This is an Autopilot limitation — migrate to Autopilot, which automatically provisions nodes for pending pods without requiring cluster autoscaling to be enabled."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE GKE questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
