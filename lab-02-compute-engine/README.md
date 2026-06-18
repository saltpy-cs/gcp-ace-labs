# Lab 02 — Compute Engine (Free-tier eligible with e2-micro)

> **Cost warning:** One e2-micro instance per month is free in `us-central1`, `us-west1`, and `us-east1`. All exercises use e2-micro. Destroy resources promptly when done.

---

## Objectives

After completing this lab you will be able to:

- Create Compute Engine instances with `gcloud compute instances create`
- Choose the right machine type family (e2, n2, c2, m2) for a given workload
- Compare disk types and select appropriately (pd-standard, pd-balanced, pd-ssd, pd-extreme, hyperdisk-balanced)
- Pass startup scripts via instance metadata and debug them with the serial console
- SSH into instances using `gcloud compute ssh` and query the metadata endpoint from inside the VM
- Create disk snapshots and restore them
- Create custom images from disks and launch new instances from them
- Attach, format, and mount additional persistent disks
- Create and use instance templates
- Explain the difference between Preemptible VMs and Spot VMs and their cost trade-offs
- Describe live migration, sole-tenant nodes, and committed use discounts

---

## Concepts

### The Compute Engine mental model

Compute Engine is GCP's Infrastructure-as-a-Service (IaaS) offering — the equivalent of AWS EC2. You get a virtual machine running on Google's hypervisor (KVM-based) with full root access. Unlike managed services (Cloud Run, App Engine), you are responsible for the OS, patching, and software stack.

Every GCE instance is made up of three independent things you configure separately:

```
Instance = Machine type (CPU+RAM) + Boot disk (OS image) + Network interface
```

This separation matters: you can take a disk snapshot, create a new instance from it, attach extra disks, or resize a disk without touching the others.

---

### Machine type families

GCP organises machine types into families. Choosing the wrong family wastes money or throttles performance.

| Family | Series | vCPU:RAM ratio | Best for | AWS equivalent |
|--------|--------|----------------|----------|----------------|
| General purpose | E2 | flexible | Dev, small web apps, low cost | t3 |
| General purpose | N2 / N2D | balanced | Most production workloads | m5 / m6a |
| General purpose | N4 | balanced, newer | Production with higher perf | m7i |
| Compute optimised | C2 / C2D | high CPU | CI/CD, gaming, HPC | c5 |
| Memory optimised | M2 / M3 | very high RAM | SAP HANA, in-memory databases | r5 |
| Accelerator optimised | A2 / G2 | GPU attached | ML training, inference | p3 / g4dn |

**E2 vs N2 — why does it matter?**

E2 uses a shared-core scheduler: your vCPUs may run on different physical hosts across time. This gives great cost efficiency but introduces slightly variable performance. N2 pins to a specific host with guaranteed vCPU allocation — use it when you need predictable latency. For the ACE exam, E2 = cost, N2 = predictable performance.

Within a family, predefined types have fixed vCPU:RAM ratios (e.g. `e2-standard-4` = 4 vCPU, 16 GB). Custom machine types let you set arbitrary vCPU and RAM independently — useful when the predefined ratio wastes money.

```bash
# List predefined E2 types
gcloud compute machine-types list --filter="name~'^e2-' AND zone:us-central1-a" \
  --format="table(name,guestCpus,memoryMb)"
```

Expected output (gcloud renders `guestCpus` as `CPUS` and converts `memoryMb` to `MEMORY_GB`):

```
NAME              CPUS  MEMORY_GB
e2-highcpu-16     16    16.00
e2-highcpu-2      2     2.00
e2-highcpu-32     32    32.00
e2-medium         2     4.00
e2-micro          2     1.00
e2-small          2     2.00
e2-standard-16    16    64.00
e2-standard-2     2     8.00
e2-standard-32    32    128.00
e2-standard-4     4     16.00
e2-standard-8     8     32.00
```

---

### Disk types

Every instance needs a boot disk. You can also attach additional persistent disks. The disk lives independently from the instance — deleting the instance does not automatically delete the disk (unless you check "Delete boot disk when instance is deleted", which is the default).

| Disk type | Backing storage | IOPS (per GB) | Throughput | Best for | Monthly cost (100 GB) |
|-----------|----------------|---------------|-----------|----------|----------------------|
| `pd-standard` | HDD | ~0.75 read / 1.5 write | ~120 MB/s | Cold data, backups | ~$4 |
| `pd-balanced` | SSD | 6 read / 6 write | ~240 MB/s | Most workloads (default) | ~$10 |
| `pd-ssd` | SSD | 30 read / 30 write | ~480 MB/s | Databases, high IOPS | ~$17 |
| `pd-extreme` | SSD | provisioned (up to 100k) | provisioned | Highest-perf DBs | ~$20+ |
| `hyperdisk-balanced` | Disaggregated SSD | provisioned independently | provisioned | New workloads needing flexibility | variable |

**Why hyperdisk?** Traditional persistent disks couple capacity to IOPS — you add capacity to get more IOPS even if you do not need storage. Hyperdisk separates the two: provision exactly the IOPS and throughput you need on any capacity.

**Boot disk vs additional disks**

The boot disk contains the OS and is attached at `/dev/sda`. Additional disks appear as `/dev/sdb`, `/dev/sdc`, etc. (or `/dev/nvme0n1` for NVMe-attached disks). Additional disks must be formatted and mounted manually — GCE does not do this for you.

Snapshots capture disk state. Images are snapshots promoted to a reusable base that can be shared across projects. The relationship:

```
Disk → Snapshot → Custom Image → New Instance
```

---

### Startup scripts and metadata

GCE exposes a metadata server at `http://metadata.google.internal/computeMetadata/v1/`. Every piece of instance configuration — zone, project, service account tokens, custom key-value pairs — is accessible from inside the VM without any credentials.

Startup scripts run as root on first boot (and on every reboot if you use `startup-script`, not `user-data`). This is how you install software, configure the OS, or pull application code automatically.

Two relevant metadata keys:

| Key | Behaviour |
|-----|-----------|
| `startup-script` | Runs on every boot. Managed by GCE's guest agent. |
| `startup-script-url` | Like above but fetches the script from a GCS URL first. |
| `user-data` | Cloud-init format. Runs once on first boot only. |

For the ACE exam: `startup-script` is the GCP-native approach. `user-data` is the AWS-style cloud-init approach that also works on GCE but is not recommended for new GCP workloads.

**Debugging startup scripts**

If a startup script fails, the instance boots but nginx is not there. The serial console shows script output before SSH is available:

```bash
gcloud compute instances get-serial-port-output INSTANCE_NAME --zone=ZONE
```

---

### OS Login vs metadata SSH keys

GCE has two SSH key management models:

| Model | How it works | Best practice |
|-------|-------------|---------------|
| Metadata SSH keys | Public key stored in instance or project metadata. Any key in metadata grants access. | Legacy, avoid for new setups. |
| OS Login | Links SSH access to IAM. A user needs `roles/compute.osLogin` (non-sudo) or `roles/compute.osAdminLogin` (sudo). Keys are managed by GCP. | Recommended. Audit trail in Cloud Audit Logs. |

OS Login is enabled per-project or per-instance via metadata key `enable-oslogin=TRUE`.

---

### Preemptible VMs vs Spot VMs

Both let GCP reclaim your VM with a 30-second warning when capacity is needed. In return you pay ~60–91% less.

| | Preemptible | Spot |
|--|------------|------|
| Maximum runtime | 24 hours | No hard limit |
| Pricing | Fixed discount | Variable (market-based), typically lower |
| Reclaim notice | 30 seconds | 30 seconds |
| Use cases | Batch jobs, CI runners, ML training | Same, plus long-running fault-tolerant workloads |
| AWS equivalent | Spot Instance (fixed duration) | Spot Instance |

> **ACE exam tip:** Preemptible VMs are deprecated in favour of Spot VMs for new workloads. Know that both give 30 seconds of notice and are unsuitable for workloads that cannot tolerate interruption (e.g. stateful databases without replication).

---

### Committed use discounts (CUDs)

If you know you will run a workload for 1 or 3 years, commit in advance for 37–55% savings. Two flavours:

- **Resource-based CUD**: commit to a quantity of vCPU and RAM. Flexible — the discount applies to any machine type in the region that uses those resources.
- **Machine-type CUD**: commit to a specific machine type (e.g. `n2-standard-8`). Higher discount but less flexible.

CUDs do not require you to keep a specific instance running — only that you are billed for the committed resources whether you use them or not.

---

### Live migration

When GCP needs to maintain the physical host (kernel patches, hardware failures), it transparently migrates your VM to another host with no reboot. This is the default `ON_HOST_MAINTENANCE=MIGRATE` setting. You will notice a brief pause (typically under 10 seconds) but no interruption.

Spot VMs and GPU/TPU instances cannot be live-migrated — they are terminated instead (`ON_HOST_MAINTENANCE=TERMINATE`).

---

### Sole-tenant nodes

For compliance workloads (financial, healthcare, gaming licensing) you may need to guarantee your VMs do not share physical hardware with other customers. Sole-tenant nodes give you a dedicated physical server billed by the node, not by the VM.

---

## Setup

Complete Lab 01 before this lab. You need:

```bash
# Confirm you have a project set
gcloud config get-value project

# Set your preferred zone (us-central1-a is free-tier eligible)
gcloud config set compute/zone us-central1-a
gcloud config set compute/region us-central1

# Store these in variables for use throughout the lab
PROJECT_ID=$(gcloud config get-value project)
ZONE=$(gcloud config get-value compute/zone)
REGION=$(gcloud config get-value compute/region)

echo "Project: $PROJECT_ID  Zone: $ZONE"
```

Enable the Compute Engine API if you have not already:

```bash
gcloud services enable compute.googleapis.com
```

Expected output after enable:
```
Operation "operations/acf.p2-..." finished successfully.
```

---

## Exercises

### Exercise 1 — Create an e2-micro instance

Create a basic instance using the minimum viable configuration. Every flag here is worth understanding.

```bash
gcloud compute instances create lab02-web \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server \
  --metadata=enable-oslogin=true
```

**What each flag does:**

- `--image-family=debian-12` — use the latest image in the `debian-12` family. GCP updates family pointers when new images are published, so this is more durable than pinning a specific image name.
- `--image-project=debian-cloud` — images are stored in separate projects. `debian-cloud` is Google-managed. Other useful image projects: `ubuntu-os-cloud`, `cos-cloud` (Container-Optimised OS), `windows-cloud`.
- `--tags=http-server` — network tags used by firewall rules. A firewall rule targeting this tag must exist in your project for traffic to reach the instance (Exercise 3 covers this).
- `--metadata=enable-oslogin=true` — use IAM-based SSH instead of metadata keys.

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/my-project/zones/us-central1-a/instances/lab02-web].
NAME      ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
lab02-web  us-central1-a  e2-micro                   10.128.0.2   34.67.xx.xx    RUNNING
```

Inspect the instance:

```bash
gcloud compute instances describe lab02-web --zone=$ZONE \
  --format="yaml(name,status,machineType,networkInterfaces,disks)"
```

---

### Exercise 2 — SSH in and explore the metadata endpoint

GCP's metadata server is only reachable from inside a VM. It requires the `Metadata-Flavor: Google` header — this is a security measure preventing SSRF attacks from tricking the metadata server into responding to external requests.

```bash
gcloud compute ssh lab02-web --zone=$ZONE
```

Expected output (first time, it will generate an SSH key pair):
```
Warning: Permanently added 'compute.NNNNN' (ECDSA) to the list of known hosts.
Linux lab02-web 6.1.0-18-cloud-amd64 ...
james_salt@lab02-web:~$
```

Once inside the VM, install `jq` then run these commands:

```bash
sudo apt-get install -y jq
```

```bash
# The metadata root — always this address, always port 80
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/" 

# Your instance's project ID
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/project/project-id"

# Your instance's zone
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/zone"

# The service account token — this is how code running on the VM authenticates to GCP APIs
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" \
  | jq .

# Custom metadata you set at instance creation
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/attributes/"
```

> **ACE exam tip:** Application code running on GCE should never have hardcoded credentials. The metadata server provides short-lived OAuth tokens automatically via the instance's attached service account. The Google Cloud client libraries call the metadata server transparently — you never see this in application code.

Try querying without the required header to see the security check in action:

```bash
# This should return a 403 — missing the required header
curl -s -o /dev/null -w "%{http_code}\n" \
  "http://metadata.google.internal/computeMetadata/v1/project/project-id"
```

Expected output:
```
403
```

Exit the VM:

```bash
exit
```

---

### Exercise 3 — Startup script: install nginx and verify

Delete the existing instance and recreate it with a startup script. This demonstrates the standard pattern for automating software installation on GCE.

```bash
gcloud compute instances delete lab02-web --zone=$ZONE --quiet
```

The instance will use the `http-server` tag to receive web traffic. That tag only works if a matching firewall rule exists in your project. Check whether it is already present:

```bash
gcloud compute firewall-rules list --filter="name=default-allow-http" --format="table(name,direction,allowed,targetTags)"
```

If the rule is missing (empty output), create it:

```bash
gcloud compute firewall-rules create default-allow-http \
  --allow=tcp:80 \
  --target-tags=http-server \
  --description="Allow HTTP from anywhere"
```

> **Why tags?** A firewall rule with `--target-tags=http-server` only applies to instances that have that tag. This means you can have many VMs in the same network but only the ones you explicitly tag receive HTTP traffic — a simple form of network segmentation.

The startup script is in this lab's directory (`startup.sh`). Make sure you are in that directory, then create the instance:

```bash
cd /path/to/gcp-ace-labs/lab-02-compute-engine
```

```bash
gcloud compute instances create lab02-web \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server \
  --metadata=enable-oslogin=true \
  --metadata-from-file=startup-script=startup.sh
```

The startup script runs `apt-get update` and installs nginx, which takes 2–4 minutes on an e2-micro. Run the verification script — it polls until nginx responds or times out after 5 minutes:

```bash
bash verify-nginx.sh
```

Expected output (zone will match your configured zone):
```
External IP: 34.x.x.x
Waiting for nginx... (0s elapsed)
Waiting for nginx... (5s elapsed)
...
<html><body>
<h1>Hello from lab02-web in europe-west2-a</h1>
</body></html>
```

**Intentional failure — what happens if the startup script crashes?**

Check the serial console output to simulate what you would do when a script silently fails:

```bash
gcloud compute instances get-serial-port-output lab02-web --zone=$ZONE | tail -30
```

You will see lines like:
```
startup-script: INFO Starting startup-script.
startup-script: INFO apt-get update -y
...
startup-script: INFO startup-script exit status 0
```

If the exit status were non-zero, this is where you would find the error. This is often the first tool you reach for when `gcloud compute ssh` connects but the expected service is not running.

---

### Exercise 4 — Create a snapshot of the boot disk

Snapshots are incremental backups stored in Cloud Storage under GCP's management. The first snapshot is a full copy; subsequent snapshots store only changed blocks. This is the primary disaster recovery tool for persistent disks.

```bash
# Create the snapshot
gcloud compute disks snapshot lab02-web \
  --zone=$ZONE \
  --snapshot-names=lab02-web-snap-01 \
  --description="Boot disk before nginx installed — lab02"
```

Expected output:
```
Created snapshot(s) [lab02-web-snap-01].
```

List snapshots and see their size:

```bash
gcloud compute snapshots list \
  --format="table(name,diskSizeGb,storageBytes,status,creationTimestamp)"
```

Expected output:
```
NAME                DISK_SIZE_GB  STORAGE_BYTES  STATUS  CREATION_TIMESTAMP
lab02-web-snap-01   10            XXXXXXXXX      READY   2026-06-17T...
```

> **ACE exam tip:** Snapshots are stored globally — they are not zone-specific. You can restore a snapshot into any zone. This is the standard way to move a disk from one zone to another.

Describe the snapshot to see its source:

```bash
gcloud compute snapshots describe lab02-web-snap-01 \
  --format="yaml(name,sourceDisk,diskSizeGb,storageBytes,status)"
```

---

### Exercise 5 — Create a custom image from the disk

A custom image is a snapshot promoted to a reusable base image. The difference: images can be used directly in `--image` flags when creating instances, shared across projects, and deprecated/deleted with lifecycle management. Snapshots are point-in-time backups.

Best practice: stop the instance before imaging to ensure filesystem consistency.

```bash
gcloud compute instances stop lab02-web --zone=$ZONE

# Wait for it to stop
gcloud compute instances describe lab02-web --zone=$ZONE \
  --format="get(status)"
```

Expected output: `TERMINATED`

Create the image from the boot disk (same name as the instance by default):

```bash
gcloud compute images create lab02-nginx-image \
  --source-disk=lab02-web \
  --source-disk-zone=$ZONE \
  --family=lab02-custom \
  --description="Debian 12 with nginx pre-installed — lab02" \
  --labels=lab=lab02,env=training
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/my-project/global/images/lab02-nginx-image].
NAME               PROJECT      FAMILY        DEPRECATED  STATUS
lab02-nginx-image  my-project   lab02-custom              READY
```

List your custom images:

```bash
gcloud compute images list --filter="family=lab02-custom" \
  --format="table(name,family,status,diskSizeGb,creationTimestamp)"
```

---

### Exercise 6 — Launch an instance from the custom image

This proves the image works as a base for new instances. In production, this pattern is called a "golden image" or "baked image" — you install your application and dependencies once, image the disk, and launch multiple instances from it instead of running startup scripts every boot.

```bash
gcloud compute instances start lab02-web --zone=$ZONE

gcloud compute instances create lab02-from-image \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image=lab02-nginx-image \
  --image-project=$PROJECT_ID \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server \
  --metadata=enable-oslogin=true
```

Verify nginx is already running (no startup script needed):

```bash
IMAGE_INSTANCE_IP=$(gcloud compute instances describe lab02-from-image \
  --zone=$ZONE \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

# Should respond immediately — nginx was baked into the image
curl -s "http://$IMAGE_INSTANCE_IP"
```

Expected output:
```
<html><body>
<h1>Hello from lab02-web in us-central1-a</h1>
</body></html>
```

Notice the hostname still says `lab02-web` — it was captured at image creation time. In a real baked image you would replace this with a startup script that fetches only the hostname dynamically, while everything else is pre-installed.

---

### Exercise 7 — Attach an additional persistent disk, format, and mount it

This is the most common operations task for Compute Engine: adding storage to a running instance.

```bash
# Create a new blank persistent disk
gcloud compute disks create lab02-data-disk \
  --zone=$ZONE \
  --size=20GB \
  --type=pd-balanced \
  --description="Additional data disk — lab02"
```

Expected output:
```
NAME              ZONE           SIZE_GB  TYPE         STATUS
lab02-data-disk   us-central1-a  20       pd-balanced  READY
```

Attach the disk to the running instance:

```bash
gcloud compute instances attach-disk lab02-web \
  --disk=lab02-data-disk \
  --zone=$ZONE \
  --device-name=data-disk
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/my-project/zones/us-central1-a/instances/lab02-web].
```

SSH in and format and mount the disk:

```bash
gcloud compute ssh lab02-web --zone=$ZONE
```

Inside the VM:

```bash
# List block devices — you should see sdb (or nvme0n1p1 on newer types)
lsblk

# The device name maps to /dev/disk/by-id/google-data-disk
ls -la /dev/disk/by-id/ | grep data-disk

# Format with ext4
sudo mkfs.ext4 -F /dev/disk/by-id/google-data-disk

# Create mount point
sudo mkdir -p /mnt/data

# Mount it
sudo mount /dev/disk/by-id/google-data-disk /mnt/data

# Verify
df -h /mnt/data
```

Expected output from `df`:
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sdb         20G   24K   19G   1% /mnt/data
```

Make the mount persistent across reboots by adding it to `/etc/fstab`:

```bash
# Get the UUID of the disk (more reliable than device name which can change)
DISK_UUID=$(sudo blkid -s UUID -o value /dev/disk/by-id/google-data-disk)

echo "UUID=$DISK_UUID /mnt/data ext4 discard,defaults,nofail 0 2" | \
  sudo tee -a /etc/fstab

# Verify fstab is correct (dry run mount)
sudo findmnt --verify

# Write a test file
echo "lab02 data disk test" | sudo tee /mnt/data/test.txt
cat /mnt/data/test.txt
```

Expected output:
```
lab02 data disk test
```

Exit the VM:

```bash
exit
```

> **ACE exam tip:** The `nofail` option in fstab is critical on GCE. Without it, if the disk is detached before the instance is rebooted (e.g. for maintenance), the instance will fail to boot and become inaccessible. Always use `nofail` for attached persistent disks.

---

### Exercise 8 — Create a Spot VM and compare with on-demand pricing

Spot VMs use spare GCP capacity at a significant discount. You will create one and examine what makes it different from a standard instance.

```bash
gcloud compute instances create lab02-spot \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --metadata=enable-oslogin=true
```

**Key flags explained:**

- `--provisioning-model=SPOT` — requests Spot pricing. Alternative: `STANDARD` (default).
- `--instance-termination-action=STOP` — when GCP reclaims this instance, stop it instead of deleting it. The alternative is `DELETE`. `STOP` preserves the disk for inspection; `DELETE` is useful for stateless batch workers.

Verify the Spot configuration on the instance:

```bash
gcloud compute instances describe lab02-spot \
  --zone=$ZONE \
  --format="yaml(name,scheduling)"
```

Expected output:
```yaml
name: lab02-spot
scheduling:
  automaticRestart: false
  instanceTerminationAction: STOP
  onHostMaintenance: TERMINATE
  preemptible: false
  provisioningModel: SPOT
```

Notice `onHostMaintenance: TERMINATE` — Spot VMs cannot be live-migrated because GCP needs to be able to reclaim them at any time.

**Simulate a preemption (what your code must handle)**

```bash
gcloud compute ssh lab02-spot --zone=$ZONE
```

Inside the VM:

```bash
# In a real Spot workload you would poll for the preemption notice
# GCP sets this metadata key 30 seconds before termination
curl -s -H "Metadata-Flavor: Google" \
  "http://metadata.google.internal/computeMetadata/v1/instance/preempted"
```

Expected output when not preempted:
```
FALSE
```

When GCP is about to preempt, this returns `TRUE`. A robust Spot workload polls this endpoint and checkpoints its work when it sees `TRUE`.

Exit the VM:

```bash
exit
```

**Compare pricing (fetch current SKUs)**

```bash
# Show on-demand vs Spot price for e2-micro in us-central1
gcloud compute machine-types describe e2-micro \
  --zone=$ZONE \
  --format="yaml(name,guestCpus,memoryMb)"
```

> At time of writing, an e2-micro in us-central1 costs approximately $0.0084/hour on-demand vs $0.0025/hour Spot — about 70% savings. Prices vary by region and over time. Check https://cloud.google.com/compute/vm-instance-pricing for current rates.

---

### Exercise 9 — Create an instance template

Instance templates are immutable configuration blueprints. They are required for managed instance groups (covered in Lab 06) and make it easy to create consistent instances at scale.

```bash
gcloud compute instance-templates create lab02-web-template \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server \
  --metadata=enable-oslogin=true \
  --metadata-from-file=startup-script=/tmp/startup.sh \
  --description="Lab02 web server template with nginx startup script"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/my-project/global/instanceTemplates/lab02-web-template].
```

Inspect the template:

```bash
gcloud compute instance-templates describe lab02-web-template \
  --format="yaml(name,properties.machineType,properties.tags,properties.metadata)"
```

Create two instances from the template in one command — this is why templates exist:

```bash
gcloud compute instances create lab02-tmpl-1 lab02-tmpl-2 \
  --zone=$ZONE \
  --source-instance-template=lab02-web-template
```

Expected output:
```
NAME          ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
lab02-tmpl-1  us-central1-a  e2-micro                   10.128.0.5   34.67.xx.xx    RUNNING
lab02-tmpl-2  us-central1-a  e2-micro                   10.128.0.6   34.67.xx.yy    RUNNING
```

> **ACE exam tip:** Instance templates are global resources (not zonal). They cannot be modified after creation — if you need to change the machine type or startup script, create a new template version. This immutability is intentional: it ensures every instance in a managed instance group is identical.

List all templates:

```bash
gcloud compute instance-templates list \
  --format="table(name,properties.machineType,creationTimestamp)"
```

---

### Exercise 10 — Use the serial console to debug a broken startup script

This exercise intentionally introduces a broken startup script to practice the most common debugging workflow for GCE: checking serial console output when SSH fails or the expected service is not running.

Create a new instance with a broken startup script:

```bash
cat > /tmp/broken-startup.sh << 'EOF'
#!/bin/bash
set -euxo pipefail

apt-get update -y

# Intentional error: package does not exist
apt-get install -y totally-fake-package-that-does-not-exist

# This line will never be reached
apt-get install -y nginx
systemctl start nginx
EOF

gcloud compute instances create lab02-broken \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-balanced \
  --tags=http-server \
  --metadata=enable-oslogin=true \
  --metadata-from-file=startup-script=/tmp/broken-startup.sh
```

Wait 30 seconds then check if nginx is running (it should not be):

```bash
BROKEN_IP=$(gcloud compute instances describe lab02-broken \
  --zone=$ZONE \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

curl --max-time 5 "http://$BROKEN_IP" || echo "nginx not responding — as expected"
```

Now diagnose the failure using serial console output:

```bash
gcloud compute instances get-serial-port-output lab02-broken \
  --zone=$ZONE 2>&1 | grep -A5 -i "startup-script\|error\|failed\|E:"
```

Expected output (look for the package error):
```
startup-script: + apt-get install -y totally-fake-package-that-does-not-exist
startup-script: E: Unable to locate package totally-fake-package-that-does-not-exist
startup-script: ERROR: startup-script exit status 100
```

You can also stream the serial console live (useful for long-running scripts):

```bash
# Press Ctrl+C to stop streaming
gcloud compute instances tail-serial-port-output lab02-broken \
  --zone=$ZONE
```

**Fix the broken instance without recreating it** by updating the metadata:

```bash
gcloud compute instances add-metadata lab02-broken \
  --zone=$ZONE \
  --metadata-from-file=startup-script=/tmp/startup.sh
```

The startup script only runs automatically on boot. Force it to run again by resetting the instance:

```bash
gcloud compute instances reset lab02-broken --zone=$ZONE
```

After ~60 seconds:

```bash
until curl -sf --max-time 3 "http://$BROKEN_IP" > /dev/null; do
  echo "Waiting for nginx..."
  sleep 5
done
echo "nginx is up"
curl -s "http://$BROKEN_IP"
```

---

## Key Takeaways

- **Machine type families serve distinct workloads:** E2 for cost-efficient dev/test, N2 for balanced production, C2 for compute-heavy workloads, M2 for memory-intensive workloads like SAP HANA.
- **Persistent disks are independent from instances.** Deleting an instance does not automatically delete its disk. Snapshots are incremental and stored globally; images are snapshots promoted to reusable bases.
- **Startup scripts run as root on every boot** (`startup-script` key). Use the serial console (`get-serial-port-output`) as the first debugging tool when a script fails — it is available before SSH.
- **The metadata server at `http://metadata.google.internal`** provides instance identity, project info, and service account tokens. All GCP client libraries use it automatically. Always require `Metadata-Flavor: Google` header.
- **OS Login is the recommended SSH key model.** It ties SSH access to IAM roles (`roles/compute.osLogin`, `roles/compute.osAdminLogin`) and produces audit logs. Metadata SSH keys are the legacy model.
- **Spot VMs save ~60–91%** but can be reclaimed with 30 seconds notice. Robust workloads poll `instance/preempted` metadata and checkpoint their state.
- **Instance templates are immutable** and required for managed instance groups. Changing configuration requires creating a new template.
- **`nofail` in `/etc/fstab`** is mandatory for attached persistent disks. Without it, detaching a disk before a reboot will prevent the instance from booting.
- **Live migration** (`ON_HOST_MAINTENANCE=MIGRATE`) is the default for standard instances. Spot VMs and GPU instances use `TERMINATE` instead.
- **Committed use discounts** give 37–55% savings for 1 or 3 year commitments. Resource-based CUDs are more flexible than machine-type CUDs.
- **Sole-tenant nodes** are required when compliance mandates physical isolation from other GCP customers.
- For the ACE exam: know **when to use Spot vs on-demand**, **which disk type for which IOPS requirement**, and **how startup script debugging works via the serial console**.

---

## Cleanup

Run these commands to destroy all resources created in this lab. Order matters — instances must be deleted before you can delete disks that were not set to auto-delete.

```bash
PROJECT_ID=$(gcloud config get-value project)
ZONE=$(gcloud config get-value compute/zone)

# Delete all instances created in this lab
gcloud compute instances delete \
  lab02-web \
  lab02-from-image \
  lab02-spot \
  lab02-tmpl-1 \
  lab02-tmpl-2 \
  lab02-broken \
  --zone=$ZONE \
  --quiet

# Delete the additional data disk (was not set to auto-delete)
gcloud compute disks delete lab02-data-disk \
  --zone=$ZONE \
  --quiet

# Delete the instance template
gcloud compute instance-templates delete lab02-web-template --quiet

# Delete the custom image
gcloud compute images delete lab02-nginx-image --quiet

# Delete the snapshot
gcloud compute snapshots delete lab02-web-snap-01 --quiet

# Delete the firewall rule if you created it in Exercise 3
# (skip this if default-allow-http already existed in your project)
gcloud compute firewall-rules delete default-allow-http --quiet

# Verify nothing remains
echo "=== Remaining instances ==="
gcloud compute instances list --filter="name~'^lab02-'" --zones=$ZONE

echo "=== Remaining disks ==="
gcloud compute disks list --filter="name~'^lab02-'" --zones=$ZONE

echo "=== Remaining snapshots ==="
gcloud compute snapshots list --filter="name~'^lab02-'"

echo "=== Remaining images ==="
gcloud compute images list --filter="name~'^lab02-'"

echo "=== Remaining templates ==="
gcloud compute instance-templates list --filter="name~'^lab02-'"
```

Expected output after cleanup (all lists should be empty):
```
=== Remaining instances ===
Listed 0 items.
=== Remaining disks ===
Listed 0 items.
=== Remaining snapshots ===
Listed 0 items.
=== Remaining images ===
Listed 0 items.
=== Remaining templates ===
Listed 0 items.
```