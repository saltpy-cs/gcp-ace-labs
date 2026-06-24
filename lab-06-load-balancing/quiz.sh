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
echo -e "${BOLD}Lab 06 — Load Balancing Quiz${RESET}"
echo "Five questions on load balancing concepts."
echo ""

ask \
  "Scenario 1 — Instance Template Immutability" \
  "Your team's MIG is running lab06-web-template. A developer wants to change the startup script environment variable APP_ENV from 'staging' to 'production'. What is the correct approach?" \
  "Create a new instance template with the updated startup script, then perform a rolling update on the MIG to the new template." \
  "Instance templates are immutable — you cannot modify them after creation. Any change, even a small metadata update, requires creating a new template version. The rolling update then replaces MIG instances one by one using the new template, keeping the service running throughout." \
  "Edit the existing instance template's metadata using gcloud compute instance-templates update." \
  "Create a new instance template with the updated startup script, then perform a rolling update on the MIG to the new template." \
  "SSH into each MIG instance and update the environment variable in place." \
  "Delete and recreate the MIG using a new instance template with the updated script."

ask \
  "Scenario 2 — Auto-Healing Grace Period" \
  "Your MIG's autohealing policy has initialDelaySec=120 and the health check has unhealthy-threshold=3 with check-interval=10s. A new instance finishes booting after 90 seconds but nginx takes a total of 150 seconds to fully start. What happens?" \
  "The MIG deletes and replaces the instance, because the 120-second grace period expires before nginx is ready and the instance will have accumulated 3 consecutive health check failures." \
  "The initialDelaySec=120 grace period on the autohealing policy is the time the MIG waits before acting on health check failures for a new instance. Since nginx is not ready until 150 seconds — 30 seconds after the grace period ends — the health checker will have recorded 3 consecutive failures within that window, triggering replacement. The fix is to increase initialDelaySec beyond the application's startup time." \
  "Nothing — the health check's check-interval pauses automatically while a new instance is starting up." \
  "The MIG deletes and replaces the instance, because the 120-second grace period expires before nginx is ready and the instance will have accumulated 3 consecutive health check failures." \
  "The instance is marked UNHEALTHY but kept running because initialDelaySec prevents deletion." \
  "The load balancer stops sending traffic to the instance but the MIG does not replace it until initialDelaySec=300 elapses."

ask \
  "Scenario 3 — Load Balancer Component Stack" \
  "An engineer needs to add a routing rule so that all requests to example.com/api/* are sent to a new backend-service-api, while all other traffic continues to backend-service-web. Which single GCP resource must they modify?" \
  "The URL map." \
  "The URL map is the routing brain of the global HTTP(S) load balancer. It inspects host headers and URL paths and routes requests to different backend services. The forwarding rule binds the IP/port, the target proxy terminates SSL and evaluates the map, the backend service holds MIGs and health checks — none of those are where path-based routing rules live." \
  "The forwarding rule." \
  "The target HTTP(S) proxy." \
  "The backend service." \
  "The URL map."

ask \
  "Scenario 4 — Source IP Preservation" \
  "A gaming company needs a GCP load balancer for a UDP-based game protocol. Their game servers must see each player's real source IP address to enforce regional matchmaking rules. Which load balancer type should they use?" \
  "External passthrough Network LB (Layer 4, regional)." \
  "The passthrough Network LB is the only GCP load balancer that preserves the client's source IP — it does not proxy or SNAT the connection. All Layer 7 load balancers (global and regional HTTP(S) LBs) terminate the connection and forward traffic using GCP's own IP, hiding the original client address. The passthrough Network LB also supports any TCP/UDP protocol, making it the only option for non-TCP/HTTP protocols like UDP game traffic." \
  "Global external HTTP(S) LB (Layer 7, global)." \
  "Regional internal HTTP(S) LB (Layer 7, regional)." \
  "Global external SSL Proxy LB (Layer 4, global)." \
  "External passthrough Network LB (Layer 4, regional)."

ask \
  "Scenario 5 — Autoscaler Behaviour Under Sustained Low Load" \
  "A MIG's autoscaler is configured with target-cpu-utilization=0.60 and a default stabilization window. CPU has been at 15% for the past 4 minutes. The autoscaler has not yet scaled in. Why?" \
  "The stabilization window (default 10 minutes) has not elapsed — the autoscaler requires load to be consistently below target for the full window before removing instances." \
  "Scale-in is deliberately slower than scale-out to prevent oscillation. The cooldown period (configured via --cool-down-period, default 60 s) governs how long the autoscaler waits after adding instances before re-evaluating. The separate stabilization window (default 10 minutes, not configurable via gcloud) controls scale-in: CPU must stay below the target for the entire 10-minute window before instances are removed. At 4 minutes the window has not elapsed, so no scale-in occurs yet." \
  "The cooldown period (default 60 seconds) has not elapsed since the last scaling event." \
  "Autoscalers never scale below min-num-replicas=2, and the current instance count is already at the minimum." \
  "The autoscaler only evaluates the metric once every 10 minutes, so it has not checked yet." \
  "The stabilization window (default 10 minutes) has not elapsed — the autoscaler requires load to be consistently below target for the full window before removing instances."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE load balancing questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
