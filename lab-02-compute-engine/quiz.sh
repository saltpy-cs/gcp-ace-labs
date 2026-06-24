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
echo -e "${BOLD}Lab 02 — Compute Engine Quiz${RESET}"
echo "Five questions on Compute Engine concepts."
echo ""

ask \
  "Question 1 — Machine Type Selection" \
  "Your team runs a latency-sensitive API serving production traffic. During load testing you notice occasional response-time spikes that correlate with CPU scheduling delays. The instances are currently e2-standard-4. What is the most likely cause and the correct remediation?" \
  "E2 uses a shared-core scheduler that can place vCPUs on different physical hosts over time, causing variable performance; migrate to N2 for guaranteed vCPU allocation." \
  "E2 uses a shared-core scheduler: vCPUs may move between physical hosts, introducing variable latency. N2 pins each vCPU to a specific physical host, providing predictable performance. For the ACE exam: E2 = lowest cost, N2 = predictable performance. Switching to a larger E2 type does not solve the scheduler variability — you need a different family." \
  "The e2-standard-4 has too few vCPUs; scale up to e2-standard-8 to reduce contention." \
  "E2 uses a shared-core scheduler that can place vCPUs on different physical hosts over time, causing variable performance; migrate to N2 for guaranteed vCPU allocation." \
  "E2 instances cannot serve external traffic without a load balancer; add an HTTP(S) load balancer." \
  "The pd-balanced boot disk has insufficient IOPS for API workloads; switch to pd-ssd."

ask \
  "Question 2 — Disk Types and IOPS" \
  "You are provisioning a disk for a PostgreSQL database that requires exactly 25,000 IOPS and 300 GB of storage. You check the pd-ssd spec and find it delivers 30 IOPS per GB, which means a 300 GB pd-ssd provides 9,000 IOPS — not enough. What is the correct disk type to meet the IOPS requirement without over-provisioning capacity?" \
  "hyperdisk-balanced, because it decouples IOPS provisioning from capacity, allowing you to set 25,000 IOPS independently of the 300 GB storage size." \
  "Traditional persistent disks (pd-standard, pd-balanced, pd-ssd) couple IOPS to capacity — to get more IOPS you must add storage even if you do not need it. pd-extreme supports very high IOPS but still ties them to disk size. Hyperdisk separates the two axes: you provision exactly the IOPS and throughput you need on any capacity. This is the key differentiator for Hyperdisk in the ACE exam." \
  "pd-extreme, because it supports provisioned IOPS up to 100,000 regardless of disk size." \
  "pd-ssd with a 1 TB disk, because a larger disk provides proportionally more IOPS." \
  "hyperdisk-balanced, because it decouples IOPS provisioning from capacity, allowing you to set 25,000 IOPS independently of the 300 GB storage size." \
  "pd-balanced, because it is the default disk type and suitable for all database workloads."

ask \
  "Question 3 — Startup Scripts and Metadata" \
  "A developer reports that an instance boots successfully and SSH works, but the expected application service is not running. They suspect the startup script failed partway through. The instance was created with --metadata-from-file=startup-script=setup.sh. Which tool should they reach for first to diagnose the failure, and why?" \
  "gcloud compute instances get-serial-port-output, because serial console output captures startup script logs before SSH is available and shows the script's exit status." \
  "The startup script runs as root during boot — before the SSH daemon is ready. Any errors are written to the serial console, which is always available regardless of instance state. The serial console shows 'startup-script exit status N' where non-zero indicates failure. SSH can only tell you the instance booted; it cannot tell you what happened during boot. Cloud Logging and the metadata server are not the right first tools here." \
  "SSH into the instance and check /var/log/syslog, because that is where all system events are recorded." \
  "Query the metadata server at http://metadata.google.internal/computeMetadata/v1/instance/attributes/ to read the script output." \
  "gcloud compute instances get-serial-port-output, because serial console output captures startup script logs before SSH is available and shows the script's exit status." \
  "Check Cloud Logging in the console, because GCE automatically streams startup script output to Cloud Logging."

ask \
  "Question 4 — Spot VMs vs Preemptible VMs" \
  "You are designing a large-scale genomics batch pipeline that processes jobs in independent chunks, each taking 2–6 hours. Cost is the primary constraint. You want to use discounted VMs. A colleague suggests Preemptible VMs. What is the most important reason to choose Spot VMs instead for this workload?" \
  "Preemptible VMs have a hard 24-hour maximum runtime, which would forcibly terminate any job chunk running longer than 24 hours; Spot VMs have no hard runtime limit." \
  "Preemptible VMs are deprecated in favour of Spot VMs, but more importantly they have a hard 24-hour cap — any instance running past 24 hours is terminated regardless of capacity availability. A job chunk that takes 6 hours and starts late in a 24-hour window would be terminated before completion. Spot VMs share the same 30-second preemption notice and similar pricing (often lower, as it is market-based), but impose no hard time limit. Both are unsuitable for stateful databases without replication." \
  "Spot VMs cannot be live-migrated, so they offer lower latency than Preemptible VMs during host maintenance events." \
  "Spot VMs use fixed pricing while Preemptible VMs use variable market-based pricing, making cost forecasting harder." \
  "Preemptible VMs have a hard 24-hour maximum runtime, which would forcibly terminate any job chunk running longer than 24 hours; Spot VMs have no hard runtime limit." \
  "Spot VMs provide a longer preemption notice window (5 minutes) compared to the 30-second notice given for Preemptible VMs."

ask \
  "Question 5 — Committed Use Discounts and Live Migration" \
  "A finance team runs an n2-standard-16 instance continuously for regulatory reporting. They want to maximise savings with a 3-year commitment but also need the flexibility to switch to n2-standard-32 next year if workload grows. Which committed use discount type should they choose, and what happens to the instance during GCP host maintenance?" \
  "Resource-based CUD, because the discount applies to any machine type using the committed vCPU and RAM resources in the region; and the instance is transparently live-migrated to another host with no reboot." \
  "Resource-based CUDs commit to a quantity of vCPU and RAM — not to a specific machine type. If the team upgrades from n2-standard-16 to n2-standard-32, the committed resources still apply to the larger type (covering the original 16 vCPU / RAM portion). Machine-type CUDs lock to a specific SKU and would not cover the new type, requiring a new commitment. For maintenance: standard N2 instances use ON_HOST_MAINTENANCE=MIGRATE by default, so GCP live-migrates them transparently with a brief pause (typically under 10 seconds) but no reboot." \
  "Machine-type CUD for the highest discount rate; and the instance is terminated and restarted on a new host, causing a brief outage." \
  "Resource-based CUD, because the discount applies to any machine type using the committed vCPU and RAM resources in the region; and the instance is transparently live-migrated to another host with no reboot." \
  "Machine-type CUD, because committing to n2-standard-16 explicitly also covers all larger N2 types in the same family." \
  "Resource-based CUD; and the instance requires a manual restart to complete the host maintenance event."

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}Score: ${SCORE}/${TOTAL}${RESET}"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
  echo -e "${GREEN}Perfect score — you're ready for the ACE Compute Engine questions.${RESET}"
elif [[ $SCORE -ge 3 ]]; then
  echo -e "${YELLOW}Good. Review the explanations for the ones you missed.${RESET}"
else
  echo -e "${RED}Review the Concepts section of the README and try again.${RESET}"
fi

echo ""
