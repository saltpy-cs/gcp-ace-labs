# Lab 05 — VPC Networking

> **Cost Warning:** VPC networks, subnets, and firewall rules are free. Cloud NAT costs ~$0.045/hr for the gateway plus ~$0.045/GB of processed data. This lab uses Cloud NAT briefly — destroy it promptly when done. Estimated total cost: **< $0.05**.

---

## Objectives

After completing this lab, you will be able to:

- Create custom-mode VPC networks and subnets with explicit CIDR ranges
- Write firewall rules targeting instances by network tag and by service account
- Launch instances without external IPs and explain why they cannot reach the internet by default
- Configure Cloud NAT to provide outbound internet access to private instances
- Enable Private Google Access so private instances can reach Google APIs and GCS
- Set up VPC peering between two networks and verify connectivity
- Demonstrate that transitive peering is not supported in GCP
- Create a Cloud DNS private zone, add A records, and query them from within a VPC
- Understand Shared VPC and VPC Service Controls at a conceptual level (exam knowledge)

---

## Concepts

### GCP Networking Model vs AWS

GCP networking differs from AWS in ways that consistently appear on the ACE exam. If you are coming from AWS, unlearn several habits before continuing.

| Concept | GCP | AWS |
|---|---|---|
| VPC scope | **Global** — one VPC spans all regions | Regional — one VPC per region |
| Subnet scope | Regional | Availability-Zone level |
| Internet access | Assign an external IP to the VM — no gateway resource | Requires Internet Gateway attached to VPC |
| Route tables | Automatically managed; no explicit resource to create | Explicit route tables attached to subnets |
| Firewall rules | Attached to the VPC, applied via tags or service accounts | Security groups attached to network interfaces; NACLs on subnets |
| Default network | Created automatically in every new project (auto-mode) | No default VPC in newer accounts |
| Transitive routing | Not supported via peering | Not supported via peering; use Transit Gateway |

The most important difference: **a GCP VPC is global**. You create one VPC and add subnets in whichever regions you need. Traffic between subnets in the same VPC (even across regions) routes internally over Google's network — you do not pay inter-region egress within a VPC for most traffic patterns, and you do not need to manage route tables.

---

### VPC Modes: Auto vs Custom

```
Auto-mode VPC
├── Automatically creates one subnet per region
├── CIDRs are fixed (10.128.0.0/9 block, pre-allocated per region)
├── Easy to get started — bad for production
└── Cannot be used in VPC peering if CIDR ranges overlap

Custom-mode VPC
├── No subnets created automatically
├── You define every subnet: region, primary CIDR, optional secondary ranges
├── Safe for VPC peering (you control the address space)
└── Required for Shared VPC host projects
```

**Always use custom-mode in production.** Auto-mode CIDRs overlap with the ranges commonly used by on-premises networks and other VPCs, which makes peering and VPN connections fragile.

You can convert an auto-mode VPC to custom-mode (one-way, irreversible):

```bash
gcloud compute networks update my-auto-vpc --switch-to-custom-subnet-mode
```

---

### Subnet Secondary Ranges

Each subnet can have secondary IP ranges in addition to its primary range. GKE uses secondary ranges to assign IPs to pods and Services without consuming addresses from the node's primary range.

```
Subnet: 10.10.0.0/24  (primary — used by VM interfaces)
  ├── Secondary range: pods    10.20.0.0/16
  └── Secondary range: services 10.30.0.0/20
```

You do not need secondary ranges in this lab, but you need to know they exist for GKE (Lab 07).

---

### Firewall Rule Anatomy

A GCP firewall rule has these components:

```
gcloud compute firewall-rules create RULE_NAME \
  --network        NETWORK          # which VPC this rule belongs to
  --direction      INGRESS|EGRESS   # direction of traffic being matched
  --priority       0-65535          # lower number = higher priority (default 1000)
  --action         ALLOW|DENY       # what to do with matched traffic
  --rules          tcp:22,icmp      # protocol and port
  --source-ranges  0.0.0.0/0        # INGRESS: where traffic comes from
  --target-tags    ssh-allowed      # which instances this rule applies to
```

**Priority:** Every VPC has two implied rules you cannot delete:
- Priority 65534: allow all egress
- Priority 65535: deny all ingress

Your rules sit above these. A lower priority number wins. If you create an ALLOW rule at 1000 and a DENY rule at 900 for the same traffic, the DENY wins.

**Targeting instances — two methods:**

| Method | How it works | When to use |
|---|---|---|
| Network tags | String labels assigned to VM instances | Simple, flexible, easy to manage manually |
| Service accounts | Rule applies to VMs running as a specific SA | Stronger — prevents accidental tag assignment; preferred for production |

> **ACE Exam Tip:** Firewall rules are **stateful** in GCP. If ingress is allowed for a TCP connection, the return traffic is automatically allowed — you do not need a separate egress rule for replies.

---

### Cloud NAT

Private instances (no external IP) cannot initiate outbound connections to the internet by default. Cloud NAT provides outbound-only internet access:

```
Private VM (10.10.1.5, no external IP)
    │
    ▼
Cloud Router (regional, holds BGP sessions)
    │
    ▼
Cloud NAT Gateway (translates source IP to NAT external IP)
    │
    ▼
Internet (sees traffic from NAT gateway IP, not from 10.10.1.5)
```

Key properties:
- Outbound only — inbound connections from the internet cannot reach the private VM
- You choose which subnets get NAT (can be subnet-specific)
- Cloud NAT requires a **Cloud Router** in the same region
- NAT does not affect traffic to Google APIs (Private Google Access handles that separately)

Compare to AWS NAT Gateway: GCP Cloud NAT works the same way conceptually, but you do not place it in a subnet — it is a regional, software-defined resource.

---

### Private Google Access

Private Google Access (PGA) allows VMs **without external IPs** to reach Google APIs and services (Cloud Storage, BigQuery, Pub/Sub, etc.) using internal IP addresses. Without PGA, a VM with no external IP cannot reach `storage.googleapis.com`.

PGA is enabled per-subnet:

```bash
gcloud compute networks subnets update my-subnet \
  --region=us-central1 \
  --enable-private-ip-google-access
```

Traffic to Google APIs takes the `private.googleapis.com` (199.36.153.8/30) or `restricted.googleapis.com` (199.36.153.4/30) VIPs. GCP routes these internally — the traffic never leaves Google's network.

> **ACE Exam Tip:** PGA and Cloud NAT are independent. PGA covers Google APIs. Cloud NAT covers general internet traffic. A private instance may need one, both, or neither depending on what it needs to reach.

---

### VPC Peering

VPC peering connects two VPCs so their internal IPs can communicate. Both VPCs can be in the same project or different projects/organizations.

**Critical constraint: transitive peering is not supported.**

```
VPC A  <──peered──>  VPC B  <──peered──>  VPC C
  │                                          │
  └──────────── NOT connected ───────────────┘
```

If A peers with B and B peers with C, instances in A cannot talk to instances in C. You must peer A directly with C if communication is needed. For hub-and-spoke topologies at scale, use **Network Connectivity Center** instead.

Peering requirements:
- CIDR ranges must not overlap between any two peered VPCs
- Peering must be created on **both sides** — each VPC creates its own peering resource pointing at the other
- You can export/import custom routes across a peering connection (disabled by default)

---

### Shared VPC (Conceptual)

Shared VPC is an organizational construct for multi-project deployments:

```
Host Project
└── VPC Network (owned and managed here)
    ├── subnet-a (us-central1)
    └── subnet-b (us-east1)

Service Project A ──────────────────┐
Service Project B ──────────────────┼──> use subnets from Host Project VPC
Service Project C ──────────────────┘
```

**Why this matters:** In large organizations, the networking team controls the host project (firewalls, subnets, IP ranges) while application teams deploy VMs into service projects. The VM's network interface lives in the host project's VPC; the VM resource lives in the service project.

You do not implement Shared VPC in this lab (it requires Organization-level IAM), but it appears on the exam. Key IAM roles:
- `compute.xpnAdmin` on the Organization — enables a project as host
- `compute.networkUser` on the host project or specific subnet — allows service project VMs to use that subnet

---

### VPC Service Controls (Conceptual)

VPC Service Controls create a security perimeter around Google managed services. Even if credentials are stolen, data cannot be exfiltrated outside the perimeter.

```
VPC Service Controls Perimeter
├── Projects: [project-a, project-b]
├── Services in perimeter: storage.googleapis.com, bigquery.googleapis.com
└── Access policy: only allow requests from within perimeter
```

This is an advanced topic tested at a high level on the ACE exam. Know the concept and that it protects against insider threats and credential compromise.

---

### Cloud DNS Private Zones

Cloud DNS private zones are visible only within the VPCs you authorize. They are independent of public DNS — you can use internal domain names that do not exist on the public internet.

```
Private Zone: internal.example.com
├── A record: db.internal.example.com → 10.10.1.100
├── A record: cache.internal.example.com → 10.10.1.101
└── Authorized networks: [vpc-lab05]
```

VMs in the authorized VPC resolve these names automatically. VMs in a peered VPC can also resolve them if DNS peering is configured.

---

## Setup

### Prerequisites

- Completed Lab 01 (project created, billing linked, gcloud configured)
- gcloud CLI authenticated and pointing at your project

### Confirm your environment

```bash
PROJECT_ID=$(gcloud config get-value project)
echo "Project: $PROJECT_ID"

gcloud config get-value compute/region
gcloud config get-value compute/zone
```

**Note:** All commands in this lab explicitly pass `--region=us-central1` and `--zone=us-central1-a`, so your default config values do not affect the lab. No changes needed regardless of what is set above.

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

---

## Exercises

### Exercise 1 — Create a Custom VPC and Subnets

**Why custom mode?** Auto-mode gives you subnets you did not ask for with CIDRs you cannot control. This lab creates two VPCs that will later be peered — overlapping CIDRs would break peering, so you must own the address plan.

Create the first VPC with no subnets:

```bash
gcloud compute networks create vpc-lab05 \
  --subnet-mode=custom \
  --description="Lab 05 primary VPC"
```

Expected output:

```
Created [https://www.googleapis.com/compute/v1/projects/.../networks/vpc-lab05].
NAME       SUBNET_MODE  BGP_ROUTING_MODE  IPV4_RANGE  GATEWAY_IPV4  INTERNAL_IPV6_RANGE
vpc-lab05  CUSTOM       REGIONAL
```

Add a subnet in us-central1 for your main workloads:

```bash
gcloud compute networks subnets create subnet-private \
  --network=vpc-lab05 \
  --region=us-central1 \
  --range=10.10.1.0/24 \
  --description="Private workload subnet"
```

Expected output:

```
Created [https://...subnets/subnet-private].
NAME            REGION       NETWORK    RANGE          STACK_TYPE  IPV6_ACCESS_TYPE  INTERNAL_IPV6_PREFIX  EXTERNAL_IPV6_PREFIX
subnet-private  us-central1  vpc-lab05  10.10.1.0/24   IPV4_ONLY
```

Add a second subnet in a different region to demonstrate that one VPC spans regions:

```bash
gcloud compute networks subnets create subnet-east \
  --network=vpc-lab05 \
  --region=us-east1 \
  --range=10.10.2.0/24 \
  --description="East region subnet (same VPC)"
```

List subnets to confirm both exist in one VPC:

```bash
gcloud compute networks subnets list --filter="network:vpc-lab05"
```

Expected output:

```
NAME            REGION       NETWORK    RANGE
subnet-east     us-east1     vpc-lab05  10.10.2.0/24
subnet-private  us-central1  vpc-lab05  10.10.1.0/24
```

> **ACE Exam Tip:** A custom VPC with subnets in multiple regions is still **one** VPC. There is no "peering" or "gateway" between regions within a single VPC — traffic routes internally.

---

### Exercise 2 — Firewall Rules with Tags and Connectivity Testing

A new custom VPC has no firewall rules except the two implied rules (allow-all-egress at 65534, deny-all-ingress at 65535). Nothing can reach your instances until you explicitly allow it.

Create a firewall rule allowing SSH only to instances tagged `ssh-allowed`:

```bash
gcloud compute firewall-rules create vpc-lab05-allow-ssh \
  --network=vpc-lab05 \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=ssh-allowed \
  --description="Allow SSH to tagged instances"
```

Create a rule allowing internal ICMP traffic between all instances in the VPC:

```bash
gcloud compute firewall-rules create vpc-lab05-allow-internal-icmp \
  --network=vpc-lab05 \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=icmp \
  --source-ranges=10.10.0.0/16 \
  --description="Allow ICMP within VPC address space"
```

Both rules use priority 1000 — and that is intentional. Priority only matters when two rules match the **same packet**. Because these rules match entirely different traffic (TCP port 22 vs ICMP, and tag-scoped vs CIDR-scoped), they can never compete. You only need to differentiate priorities when you have overlapping rules where one should win over another, such as a broad allow that a narrower deny needs to override.

Launch a public instance (with external IP) tagged `ssh-allowed`:

```bash
gcloud compute instances create vm-public \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --subnet=subnet-private \
  --tags=ssh-allowed \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

You may see this warning:

```
WARNING: Some requests generated warnings:
 - You are creating a global DNS VM. VM instances using global DNS are vulnerable
   to cross-regional outages...
```

This is expected and safe to ignore in a lab. By default, VMs use global DNS, meaning their internal hostnames are resolvable across all regions. GCP recommends zonal DNS for production workloads because it isolates hostname resolution to the zone — a regional outage cannot affect DNS lookups in other zones. For this lab it makes no difference.

Expected output:

```
NAME       ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
vm-public  us-central1-a  e2-micro                   10.10.1.2    34.XX.XX.XX    RUNNING
```

SSH in to verify access works:

```bash
gcloud compute ssh vm-public --zone=us-central1-a
```

Exit the SSH session:

```bash
exit
```

**Now intentionally break it** — remove the `ssh-allowed` tag and verify SSH is blocked:

```bash
gcloud compute instances remove-tags vm-public \
  --zone=us-central1-a \
  --tags=ssh-allowed
```

Try to SSH (this should fail or time out):

```bash
gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-o ConnectTimeout=10"
```

Expected output:

```
ssh: connect to host 34.XX.XX.XX port 22: Connection timed out
ERROR: (gcloud.compute.ssh) [/usr/bin/ssh] exited with return code [255].
```

The firewall rule is on the VPC, but without the tag, the rule does not apply to this instance. Restore the tag:

```bash
gcloud compute instances add-tags vm-public \
  --zone=us-central1-a \
  --tags=ssh-allowed
```

> **ACE Exam Tip:** Firewall rules target instances by tag, not by subnet. An instance in `subnet-private` with no tags has no INGRESS rules applying to it (beyond the implied deny). An instance in the same subnet with the right tag has SSH open. Subnets do not inherit firewall rules.

---

### Exercise 3 — Create a Private Instance and Verify No Internet Access

Create an instance with **no external IP**. This simulates a private workload — a database server, an internal API, a batch job runner.

```bash
gcloud compute instances create vm-private \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --subnet=subnet-private \
  --no-address \
  --tags=ssh-allowed \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

Expected output:

```
NAME        ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP  STATUS
vm-private  us-central1-a  e2-micro                   10.10.1.3                 RUNNING
```

Note the empty `EXTERNAL_IP` column. This instance has no route to the internet.

You cannot SSH directly to a private instance from your laptop (no external IP to connect to). Use `vm-public` as a bastion host. SSH to the bastion, then use the internal IP to reach the private instance:

```bash
gcloud compute ssh vm-public \
  --zone=us-central1-a \
  --command="ping -c 3 10.10.1.3"
```

Expected output (internal ICMP works because of the allow-internal-icmp rule):

```
PING 10.10.1.3 (10.10.1.3) 56(84) bytes of data.
64 bytes from 10.10.1.3: icmp_seq=1 ttl=64 time=1.23 ms
64 bytes from 10.10.1.3: icmp_seq=2 ttl=64 time=0.98 ms
64 bytes from 10.10.1.3: icmp_seq=3 ttl=64 time=1.01 ms
```

Now verify that the private instance cannot reach the internet. You will use vm-public as a bastion to reach vm-private using SSH agent forwarding — this allows vm-public to authenticate to vm-private using your local private key without copying it onto the bastion.

Agent forwarding requires the key to already be loaded in your local SSH agent. `gcloud compute ssh` does not do this automatically, so load it first:

```bash
# On your local machine
ssh-add ~/.ssh/google_compute_engine
```

Then SSH to vm-public with agent forwarding enabled:

```bash
gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-A"
```

From inside vm-public, SSH to vm-private using its internal IP:

```bash
# Inside vm-public
ssh -o StrictHostKeyChecking=no 10.10.1.3
```

From inside vm-private, attempt an outbound connection:

```bash
# Inside vm-private
curl --max-time 10 https://example.com
```

Expected output:

```
curl: (28) Connection timed out after 10001 milliseconds
```

The instance has no default route to the internet. Exit back to your local machine:

```bash
exit   # exit vm-private
exit   # exit vm-public
```

---

### Exercise 4 — Set Up Cloud NAT and Verify Outbound Internet Access

Cloud NAT gives private instances outbound internet access without assigning them external IPs. It requires a Cloud Router in the same region.

Create the Cloud Router:

```bash
gcloud compute routers create router-lab05 \
  --network=vpc-lab05 \
  --region=us-central1
```

Expected output:

```
Creating router [router-lab05]...done.
NAME          REGION       NETWORK
router-lab05  us-central1  vpc-lab05
```

Create the Cloud NAT gateway attached to the router:

```bash
gcloud compute routers nats create nat-lab05 \
  --router=router-lab05 \
  --region=us-central1 \
  --auto-allocate-nat-external-ips \
  --nat-custom-subnet-ip-ranges=subnet-private
```

The flag `--nat-custom-subnet-ip-ranges=subnet-private` limits NAT to only `subnet-private`. This is better than enabling NAT for all subnets — explicit is safer.

Expected output:

```
Creating NAT [nat-lab05] in router [router-lab05]...done.
```

Wait about 30 seconds for NAT to propagate, then test from the private instance. The Cloud NAT gateway takes a moment to become active after creation.

```bash
gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-A" \
  --command="ssh -o StrictHostKeyChecking=no 10.10.1.3 'curl --max-time 15 -s -o /dev/null -w \"%{http_code}\" https://example.com'"
```

Expected output:

```
200
```

HTTP 200 — the private instance reached the internet through Cloud NAT. The public internet sees the NAT gateway's external IP, not `10.10.1.3`.

Verify what external IP the private instance appears to use:

```bash
gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-A" \
  --command="ssh -o StrictHostKeyChecking=no 10.10.1.3 'curl -s https://ifconfig.me'"
```

Expected output (an external IP belonging to Google's NAT pool, not your instance):

```
34.XX.XX.XX
```

Describe the NAT gateway to see its allocated external IPs:

```bash
gcloud compute routers nats describe nat-lab05 \
  --router=router-lab05 \
  --region=us-central1
```

> **ACE Exam Tip:** Cloud NAT is **one-way**. The internet cannot initiate a connection to `10.10.1.3`. There is no NAT table entry until the private instance opens the connection first. This is equivalent to AWS NAT Gateway behavior — no inbound connections possible.

---

### Exercise 5 — Enable Private Google Access

Right now, `vm-private` can reach the general internet (via Cloud NAT), but imagine you wanted to keep it isolated from the public internet while still allowing it to read from Cloud Storage. Private Google Access (PGA) solves this — it routes Google API traffic internally without going through Cloud NAT or requiring an external IP.

**First, disable Cloud NAT so you can clearly see PGA working independently:**

```bash
gcloud compute routers nats delete nat-lab05 \
  --router=router-lab05 \
  --region=us-central1 \
  --quiet
```

Verify the private instance cannot reach the internet again:

```bash
gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-A" \
  --command="ssh -o StrictHostKeyChecking=no 10.10.1.3 'curl --max-time 10 -s -o /dev/null -w \"%{http_code}\" https://example.com'"
```

Expected output:

```
000
```

`000` is curl's HTTP code when the connection times out before any response is received — confirmation that the private instance has no internet route.

Good — no internet. Now enable Private Google Access on the subnet:

```bash
gcloud compute networks subnets update subnet-private \
  --region=us-central1 \
  --enable-private-ip-google-access
```

Expected output:

```
Updated [https://...subnets/subnet-private].
```

Confirm PGA is enabled:

```bash
gcloud compute networks subnets describe subnet-private \
  --region=us-central1 \
  --format="get(privateIpGoogleAccess)"
```

Expected output:

```
True
```

Create a GCS bucket and upload a test file so you have something to read:

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="lab05-pga-test-${PROJECT_ID}"

gcloud storage buckets create gs://${BUCKET_NAME} \
  --location=us-central1 \
  --uniform-bucket-level-access

echo 'Private Google Access works!' | gcloud storage cp - gs://${BUCKET_NAME}/test.txt
```

Now verify the private instance can access GCS using its service account (it has no external IP and NAT is disabled):

```bash
gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-A" \
  --command="ssh -o StrictHostKeyChecking=no 10.10.1.3 'gcloud storage cat gs://${BUCKET_NAME}/test.txt'"
```

Expected output:

```
Private Google Access works!
```

`gcloud` on the private instance authenticates automatically using the attached service account — no token extraction needed. The file was fetched from GCS without an external IP and without Cloud NAT, proving PGA routes the traffic through Google's internal backbone.

> **ACE Exam Tip:** PGA works because GCP's internal routing redirects traffic destined for `*.googleapis.com` IP ranges (199.36.153.0/24, 199.36.152.0/24) via Google's internal backbone when PGA is enabled. It never leaves Google's network.

Re-enable Cloud NAT for subsequent exercises:

```bash
gcloud compute routers nats create nat-lab05 \
  --router=router-lab05 \
  --region=us-central1 \
  --auto-allocate-nat-external-ips \
  --nat-custom-subnet-ip-ranges=subnet-private
```

---

### Exercise 6 — Create a Second VPC and Set Up VPC Peering

VPC peering connects two VPCs so instances in each can communicate using internal IPs. You will create a second VPC (simulating a separate team's network or a separate environment) and peer it with `vpc-lab05`.

Create the second VPC and subnet. The CIDR must not overlap with `vpc-lab05` (10.10.0.0/16):

```bash
gcloud compute networks create vpc-peer \
  --subnet-mode=custom \
  --description="Lab 05 peering target VPC"

gcloud compute networks subnets create subnet-peer \
  --network=vpc-peer \
  --region=us-central1 \
  --range=10.20.1.0/24 \
  --description="Peer VPC subnet"
```

Add firewall rules to allow ICMP and SSH within the peer VPC:

```bash
gcloud compute firewall-rules create vpc-peer-allow-icmp \
  --network=vpc-peer \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=icmp \
  --source-ranges=10.0.0.0/8

gcloud compute firewall-rules create vpc-peer-allow-ssh \
  --network=vpc-peer \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=ssh-allowed
```

Launch an instance in the peer VPC:

```bash
gcloud compute instances create vm-peer \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --subnet=subnet-peer \
  --tags=ssh-allowed \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

Expected output:

```
NAME     ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
vm-peer  us-central1-a  e2-micro                   10.20.1.2    34.YY.YY.YY    RUNNING
```

Before peering, verify that `vm-public` (10.10.1.2) cannot ping `vm-peer` (10.20.1.2):

```bash
gcloud compute ssh vm-public --zone=us-central1-a \
  --command="ping -c 3 -W 2 10.20.1.2"
```

Expected output:

```
PING 10.20.1.2 (10.20.1.2) 56(84) bytes of data.

--- 10.20.1.2 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss
```

No connectivity — the VPCs are isolated. Now create the peering connection. **Both sides must create the peering:**

Side 1 — from `vpc-lab05` to `vpc-peer`:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute networks peerings create peering-lab05-to-peer \
  --network=vpc-lab05 \
  --peer-project=${PROJECT_ID} \
  --peer-network=vpc-peer \
  --export-custom-routes \
  --import-custom-routes
```

Expected output (the full network object in YAML, truncated here for brevity):

```
Updated [https://www.googleapis.com/compute/v1/projects/.../networks/vpc-lab05].
---
...
peerings:
- ...
  name: peering-lab05-to-peer
  network: https://.../networks/vpc-peer
  state: INACTIVE
  stateDetails: '[...]: Waiting for peer network to connect.'
...
```

The peering shows `INACTIVE` — this is expected. VPC peering requires both sides to create the connection. The state will become `ACTIVE` once side 2 is created below.

Side 2 — from `vpc-peer` to `vpc-lab05`:

```bash
gcloud compute networks peerings create peering-peer-to-lab05 \
  --network=vpc-peer \
  --peer-project=${PROJECT_ID} \
  --peer-network=vpc-lab05 \
  --export-custom-routes \
  --import-custom-routes
```

Check the peering status:

```bash
gcloud compute networks peerings list --network=vpc-lab05
```

Expected output:

```
NAME                   NETWORK    PEER_PROJECT    PEER_NETWORK  STACK_TYPE  PEER_MTU  IMPORT_CUSTOM_ROUTES  EXPORT_CUSTOM_ROUTES  UPDATE_STRATEGY  STATE   STATE_DETAILS
peering-lab05-to-peer  vpc-lab05  YOUR_PROJECT    vpc-peer      IPV4_ONLY             True                  True                  INDEPENDENT      ACTIVE  [...]: Connected.
```

Both sides must show `ACTIVE`. Now test connectivity:

```bash
gcloud compute ssh vm-public --zone=us-central1-a \
  --command="ping -c 3 10.20.1.2"
```

Expected output:

```
PING 10.20.1.2 (10.20.1.2) 56(84) bytes of data.
64 bytes from 10.20.1.2: icmp_seq=1 ttl=63 time=1.87 ms
64 bytes from 10.20.1.2: icmp_seq=2 ttl=63 time=1.92 ms
64 bytes from 10.20.1.2: icmp_seq=3 ttl=63 time=1.78 ms
```

Internal IPs now route between the two VPCs.

---

### Exercise 7 — Demonstrate That Transitive Peering Does Not Work

Transitive peering is one of the most commonly tested VPC networking facts on the ACE exam. You will prove it fails.

Create a third VPC peered only with `vpc-peer` (not with `vpc-lab05`):

```bash
gcloud compute networks create vpc-third \
  --subnet-mode=custom \
  --description="Lab 05 third VPC (transitive peering demo)"

gcloud compute networks subnets create subnet-third \
  --network=vpc-third \
  --region=us-central1 \
  --range=10.30.1.0/24

gcloud compute firewall-rules create vpc-third-allow-icmp \
  --network=vpc-third \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=icmp \
  --source-ranges=10.0.0.0/8

gcloud compute firewall-rules create vpc-third-allow-ssh \
  --network=vpc-third \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=ssh-allowed
```

Launch an instance in the third VPC:

```bash
gcloud compute instances create vm-third \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --subnet=subnet-third \
  --tags=ssh-allowed \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

Expected output:

```
NAME      ZONE           MACHINE_TYPE  INTERNAL_IP  EXTERNAL_IP    STATUS
vm-third  us-central1-a  e2-micro      10.30.1.2    34.ZZ.ZZ.ZZ    RUNNING
```

Peer `vpc-peer` with `vpc-third` (both sides):

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute networks peerings create peering-peer-to-third \
  --network=vpc-peer \
  --peer-project=${PROJECT_ID} \
  --peer-network=vpc-third

gcloud compute networks peerings create peering-third-to-peer \
  --network=vpc-third \
  --peer-project=${PROJECT_ID} \
  --peer-network=vpc-peer
```

The peering topology now looks like this:

```
vpc-lab05 (10.10.0.0/16)
    │
    │  peered
    │
vpc-peer (10.20.0.0/16)
    │
    │  peered
    │
vpc-third (10.30.0.0/16)
```

`vpc-lab05` is **not** directly peered with `vpc-third`. According to transitive peering rules, `vm-public` in `vpc-lab05` should not be able to reach `vm-third` in `vpc-third`. Prove it:

```bash
gcloud compute ssh vm-public --zone=us-central1-a \
  --command="ping -c 3 -W 2 10.30.1.2"
```

Expected output:

```
PING 10.30.1.2 (10.30.1.2) 56(84) bytes of data.

--- 10.30.1.2 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss
```

`vm-public` cannot reach `vm-third` even though both are peered with `vpc-peer`. This is transitive peering — and it does not work.

Contrast this with `vm-peer`, which is **directly** in `vpc-peer` and has direct peerings with both networks:

```bash
gcloud compute ssh vm-peer --zone=us-central1-a \
  --command="ping -c 3 10.30.1.2"
```

Expected output:

```
64 bytes from 10.30.1.2: icmp_seq=1 ttl=64 time=1.44 ms
64 bytes from 10.30.1.2: icmp_seq=2 ttl=64 time=1.39 ms
64 bytes from 10.30.1.2: icmp_seq=3 ttl=64 time=1.41 ms
```

`vm-peer` can reach `vm-third` because `vpc-peer` is directly peered with `vpc-third`.

> **ACE Exam Tip:** Transitive peering does not work. If you need A to talk to C and B is between them, you need a direct peering between A and C. At scale, use **Network Connectivity Center** (hub-and-spoke model) instead of a full mesh of peerings.

---

### Exercise 8 — Cloud DNS Private Zone and A Records

Create a Cloud DNS private zone so your instances can resolve internal names like `db.internal.lab05` to internal IPs without using `/etc/hosts` on every VM.

Create the private DNS zone, authorized for `vpc-lab05`:

```bash
gcloud dns managed-zones create lab05-internal \
  --description="Lab 05 internal DNS zone" \
  --dns-name="internal.lab05." \
  --visibility=private \
  --networks=vpc-lab05
```

Expected output:

```
Created [https://dns.googleapis.com/dns/v1/projects/.../managedZones/lab05-internal].
```

Add an A record pointing `db.internal.lab05` to `vm-private`'s internal IP:

```bash
VM_PRIVATE_IP=$(gcloud compute instances describe vm-private \
  --zone=us-central1-a \
  --format="get(networkInterfaces[0].networkIP)")

echo "vm-private internal IP: ${VM_PRIVATE_IP}"

gcloud dns record-sets create db.internal.lab05. \
  --zone=lab05-internal \
  --type=A \
  --ttl=300 \
  --rrdatas="${VM_PRIVATE_IP}"
```

Expected output:

```
NAME                TYPE  TTL  DATA
db.internal.lab05.  A     300  10.10.1.3
```

Add a second A record pointing to `vm-public`'s internal IP:

```bash
VM_PUBLIC_INTERNAL_IP=$(gcloud compute instances describe vm-public \
  --zone=us-central1-a \
  --format="get(networkInterfaces[0].networkIP)")

gcloud dns record-sets create app.internal.lab05. \
  --zone=lab05-internal \
  --type=A \
  --ttl=300 \
  --rrdatas="${VM_PUBLIC_INTERNAL_IP}"
```

List the records in the zone:

```bash
gcloud dns record-sets list --zone=lab05-internal
```

Expected output:

```
NAME                TYPE  TTL    DATA
internal.lab05.     NS    21600  ns-gcp-private.googleapis.com.
internal.lab05.     SOA   21600  ns-gcp-private.googleapis.com. cloud-dns-hostmaster.google.com. 1 21600 3600 259200 300
app.internal.lab05. A     300    10.10.1.2
db.internal.lab05.  A     300    10.10.1.3
```

Private DNS zones use `ns-gcp-private.googleapis.com` as their nameserver rather than the public-facing `ns-cloud-*.googledomains.com` nameservers used for public zones.

Install `dnsutils` on `vm-public` so `nslookup` is available:

```bash
gcloud compute ssh vm-public --zone=us-central1-a \
  --command="sudo apt-get install -y -q dnsutils"
```

Test DNS resolution from `vm-public` (which is in `vpc-lab05`, the authorized network):

```bash
gcloud compute ssh vm-public --zone=us-central1-a \
  --command="nslookup db.internal.lab05"
```

Expected output:

```
Server:         169.254.169.254
Address:        169.254.169.254#53

Non-authoritative answer:
Name:   db.internal.lab05
Address: 10.10.1.3
```

`169.254.169.254` is the GCP metadata server — it acts as the DNS resolver for VMs and forwards to Cloud DNS. The A record resolved to `10.10.1.3` — the internal IP of `vm-private`.

Now verify the private zone is NOT visible from `vpc-peer` (a different, non-authorized VPC):

```bash
gcloud compute ssh vm-peer --zone=us-central1-a \
  --command="sudo apt-get install -y -q dnsutils && nslookup db.internal.lab05"
```

Expected output:

```
Server:         169.254.169.254
Address:        169.254.169.254#53

** server can't find db.internal.lab05: NXDOMAIN
```

`NXDOMAIN` — the private zone is invisible to VMs in non-authorized VPCs. To expose a private zone to a peered VPC, you would configure DNS peering between the zones.

> **ACE Exam Tip:** Private DNS zones are authorized to specific VPC networks. Peered VPCs do **not** automatically inherit DNS zone visibility. You must explicitly add the peered VPC to the zone's authorized networks list, or set up DNS peering.

---

### Exercise 9 — Firewall Rule Targeting by Service Account

Network tags are convenient but have a security gap: any user with permission to modify an instance can add a tag and change which firewall rules apply to it. Service account-based firewall targeting eliminates this — only instances running as a specific service account match the rule, and SA assignment is controlled at the IAM level.

Create a dedicated service account for a hypothetical "backend" workload:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud iam service-accounts create sa-backend \
  --display-name="Backend workload service account" \
  --description="Used for backend VM firewall targeting"
```

Expected output:

```
Created service account [sa-backend].
```

Create a firewall rule that **only allows SSH to instances running as `sa-backend`**, regardless of tags:

```bash
gcloud compute firewall-rules create vpc-lab05-allow-ssh-sa-backend \
  --network=vpc-lab05 \
  --direction=INGRESS \
  --priority=900 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges=0.0.0.0/0 \
  --target-service-accounts=sa-backend@${PROJECT_ID}.iam.gserviceaccount.com \
  --description="Allow SSH to instances running as sa-backend"
```

Note `--priority=900` — higher priority than the tag-based rule (priority 1000). Service account rules and tag rules are independent; an instance can match one, both, or neither.

Create an instance that runs as `sa-backend`. First, grant the SA the ability to create a VM:

```bash
# Allow the default compute SA to use this service account on VMs
gcloud iam service-accounts add-iam-policy-binding \
  sa-backend@${PROJECT_ID}.iam.gserviceaccount.com \
  --member="serviceAccount:$(gcloud projects describe ${PROJECT_ID} \
      --format='get(projectNumber)')-compute@developer.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

Create the instance running as `sa-backend` and with **no network tags**:

```bash
gcloud compute instances create vm-backend \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --subnet=subnet-private \
  --no-address \
  --service-account=sa-backend@${PROJECT_ID}.iam.gserviceaccount.com \
  --scopes=cloud-platform \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

Expected output:

```
NAME        ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP  STATUS
vm-backend  us-central1-a  e2-micro                   10.10.1.4                 RUNNING
```

No external IP, no tags. Yet the firewall rule allows SSH **because of its service account**. Verify by checking which rules would apply to this instance:

```bash
gcloud compute instances describe vm-backend \
  --zone=us-central1-a \
  --format="get(serviceAccounts[0].email)"
```

Expected output:

```
sa-backend@YOUR_PROJECT.iam.gserviceaccount.com
```

Inspect all effective firewall rules for this instance:

```bash
gcloud compute instances describe vm-backend \
  --zone=us-central1-a \
  --format="table(name, networkInterfaces[0].network.basename())"

gcloud compute firewall-rules list \
  --filter="network:vpc-lab05" \
  --format="table(name,direction,priority,action,targetServiceAccounts,targetTags,allowed[].map().firewall_rule().list():label=ALLOW)"
```

Expected output (showing the SA-targeted rule):

```
NAME                              DIRECTION  PRIORITY  ACTION  TARGET_SERVICE_ACCOUNTS           ALLOWED
vpc-lab05-allow-internal-icmp     INGRESS    1000      ALLOW                                     icmp
vpc-lab05-allow-ssh               INGRESS    1000      ALLOW                                     tcp:22
vpc-lab05-allow-ssh-sa-backend    INGRESS    900       ALLOW   sa-backend@PROJECT.iam...         tcp:22
```

**Demonstrate the security advantage.** Create a second instance with the `ssh-allowed` tag but a different service account — it gets SSH access via the tag rule. Then remove the tag — now it has no SSH access. With SA-based rules, you cannot accidentally grant SSH by adding a tag because the rule targets a SA that only Google controls assignment of.

```bash
gcloud compute instances create vm-notag-nobackend \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --subnet=subnet-private \
  --no-address \
  --image-family=debian-12 \
  --image-project=debian-cloud
```

This instance has no external IP, no tags, and the default compute SA. Neither the tag-based SSH rule nor the SA-based SSH rule applies to it. Prove it:

```bash
VM_NOTAG_IP=$(gcloud compute instances describe vm-notag-nobackend \
  --zone=us-central1-a \
  --format="get(networkInterfaces[0].networkIP)")

gcloud compute ssh vm-public --zone=us-central1-a --ssh-flag="-A" \
  --command="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ${VM_NOTAG_IP}"
```

Expected output:

```
ssh: connect to host 10.10.1.X port 22: Connection timed out
```

The connection times out rather than being refused — the VPC firewall silently drops the packet. There is no rule matching this instance, so traffic never reaches it.

> **ACE Exam Tip:** Service account-based firewall targeting is more secure than tag-based targeting in production environments. You need `compute.instances.setServiceAccount` permission to change a VM's SA — a much higher-privilege operation than adding a tag. This prevents privilege escalation through tag manipulation.

---

## Key Takeaways

- **GCP VPCs are global** — one VPC can have subnets in every region. AWS VPCs are regional. This is one of the most important architectural differences.
- **Custom-mode VPCs are required for production** — auto-mode CIDRs can overlap with peered networks and on-premises ranges. Convert early; it is a one-way operation.
- **There is no Internet Gateway resource in GCP** — an external IP is all a VM needs for internet access. Cloud NAT provides outbound-only internet access for VMs without external IPs.
- **Firewall rules are on the VPC, not the instance** — they are applied by tag or service account. Changing tags changes which rules apply without modifying the rule itself.
- **Cloud NAT and Private Google Access are independent** — NAT handles general internet traffic; PGA handles Google APIs. A VM may need one, both, or neither.
- **Transitive VPC peering is NOT supported** — A peered with B, B peered with C does not give A access to C. Use direct peering or Network Connectivity Center for hub-and-spoke topologies.
- **VPC peering requires both sides to create a peering resource** — one-sided peering remains inactive. Both peerings must be ACTIVE before traffic flows.
- **Cloud DNS private zones are authorized to specific VPCs** — they are not visible to peered VPCs by default. Add the peered VPC to the authorized networks list or configure DNS peering.
- **Service account-based firewall rules are more secure than tag-based rules** — SA assignment requires elevated IAM permissions; tag assignment does not.
- **Shared VPC separates network management from workload management** — the host project team controls networking; service project teams deploy VMs into controlled subnets. This is the standard pattern for enterprise GCP organizations.
- **VPC Service Controls restrict Google API access by perimeter** — even valid credentials cannot access protected services from outside the perimeter. This protects against data exfiltration.
- **Firewall rules are stateful** — return traffic for allowed connections is automatically permitted. You do not need explicit egress rules to allow replies to allowed ingress connections.
- **Priority 0 = highest priority, 65535 = lowest** — the implied deny-all-ingress rule sits at 65535. Your rules override it at lower numbers.

---

## Cleanup

Destroy all resources in reverse dependency order. Run these commands from your local terminal (not from inside any of the VMs).

```bash
# Check what exists before cleanup
../status.sh 5
```

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET_NAME="lab05-pga-test-${PROJECT_ID}"

# Delete VM instances
gcloud compute instances delete vm-public vm-private vm-peer vm-backend vm-third vm-notag-nobackend \
  --zone=us-central1-a \
  --quiet

# Delete Cloud NAT and Cloud Router
gcloud compute routers nats delete nat-lab05 \
  --router=router-lab05 \
  --region=us-central1 \
  --quiet

gcloud compute routers delete router-lab05 \
  --region=us-central1 \
  --quiet

# Delete DNS zone and records
gcloud dns record-sets delete db.internal.lab05. \
  --zone=lab05-internal \
  --type=A

gcloud dns record-sets delete app.internal.lab05. \
  --zone=lab05-internal \
  --type=A

gcloud dns managed-zones delete lab05-internal --quiet

# Delete VPC peering connections
gcloud compute networks peerings delete peering-lab05-to-peer \
  --network=vpc-lab05 \
  --quiet

gcloud compute networks peerings delete peering-peer-to-lab05 \
  --network=vpc-peer \
  --quiet

gcloud compute networks peerings delete peering-peer-to-third \
  --network=vpc-peer \
  --quiet

gcloud compute networks peerings delete peering-third-to-peer \
  --network=vpc-third \
  --quiet

# Delete firewall rules
gcloud compute firewall-rules delete \
  vpc-lab05-allow-ssh \
  vpc-lab05-allow-internal-icmp \
  vpc-lab05-allow-ssh-sa-backend \
  vpc-peer-allow-icmp \
  vpc-peer-allow-ssh \
  vpc-third-allow-icmp \
  vpc-third-allow-ssh \
  --quiet

# Delete subnets
gcloud compute networks subnets delete subnet-private \
  --region=us-central1 \
  --quiet

gcloud compute networks subnets delete subnet-east \
  --region=us-east1 \
  --quiet

gcloud compute networks subnets delete subnet-peer \
  --region=us-central1 \
  --quiet

gcloud compute networks subnets delete subnet-third \
  --region=us-central1 \
  --quiet

# Delete VPC networks
gcloud compute networks delete vpc-lab05 vpc-peer vpc-third --quiet

# Delete GCS bucket
gcloud storage rm --recursive gs://${BUCKET_NAME}

# Delete service account
gcloud iam service-accounts delete \
  sa-backend@${PROJECT_ID}.iam.gserviceaccount.com \
  --quiet
```

Verify no billable resources remain:

```bash
# Confirm all instances are deleted
gcloud compute instances list

../status.sh 5
```

Expected output: all sections empty (only the `default` network may remain if you have not deleted it from a previous lab).