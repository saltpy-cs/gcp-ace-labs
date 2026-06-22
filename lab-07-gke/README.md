# Lab 07 — Google Kubernetes Engine

> **Cost warning:** A GKE Autopilot cluster costs nothing at rest — you pay only for running pod resources (~$0.06/vCPU/hr, ~$0.006/GB memory/hr). A LoadBalancer Service creates an L4 Network Load Balancer (~$0.025/hr). Estimated for this lab: **~$0.50–1.00**. The Workload Identity exercise creates a Standard cluster (~$0.10/hr cluster management fee + node costs). Destroy all clusters promptly when done.

---

## Objectives

After completing this lab you will be able to:

- Create GKE clusters in both Autopilot and Standard modes and explain when to use each
- Authenticate `kubectl` to a GKE cluster using the `gke-gcloud-auth-plugin`
- Deploy a containerised application using a Kubernetes `Deployment`
- Expose applications using `ClusterIP`, `NodePort`, and `LoadBalancer` Services
- Scale a Deployment manually and with a Horizontal Pod Autoscaler (HPA)
- Mount configuration data into pods using `ConfigMap` as environment variables and volume files
- Mount sensitive data into pods using `Secret` as environment variables and volume files
- Perform a rolling update, inspect rollout history, and roll back to a previous revision
- Configure Workload Identity so pods authenticate to GCP APIs without service account key files
- Explain GKE networking: VPC-native clusters, pod CIDR, service CIDR, and alias IPs
- Manage node pools in a Standard cluster and understand node pool upgrade channels

---

## Concepts

### GKE Modes: Autopilot vs Standard

GKE offers two fundamentally different operating models. The mode you choose affects cost, control, and operational overhead.

**Autopilot** is Google's fully managed mode. You describe what workloads you want to run (pods, deployments, services) and GKE provisions, sizes, and manages the underlying nodes for you. You never see or manage individual nodes. Nodes are created on demand when pods are scheduled and removed when pods are deleted. You pay only for the pod resource requests (vCPU, memory, ephemeral storage), not for idle node capacity.

Autopilot enforces security hardened defaults: pods cannot run as root, host namespaces are disallowed, and privilege escalation is blocked. This is intentional — because Google manages the nodes, it enforces a security baseline so that tenants cannot compromise the shared infrastructure.

**Standard** gives you full control over node pools. You choose the machine type, disk size, image type, and number of nodes in each pool. You pay per node whether or not pods are scheduled on it. Standard is required when you need specific hardware (GPUs, local SSDs, specific machine families), custom node configurations, or workloads that Autopilot's security policy rejects.

| | Autopilot | Standard |
|---|---|---|
| Node management | Google manages nodes | You manage node pools |
| Billing | Per pod resource request | Per node (running or idle) |
| Security defaults | Hardened, enforced by GCP | Configurable |
| Idle cost | Zero (no pods = no cost) | You pay for nodes even if idle |
| Node access | Not available (no SSH) | SSH to nodes is possible |
| Custom node config | Not available | Full control |
| Best for | Most production workloads | GPU/specialised hardware, legacy apps needing root |

On AWS, the closest equivalents are **EKS with Fargate** (Autopilot) and **EKS with EC2 node groups** (Standard). The key difference is that GKE Autopilot is a fully integrated mode of the same cluster, while EKS Fargate is a bolt-on profile.

> **ACE exam tip:** The exam will ask you to choose a cluster mode. Default to Autopilot unless the question mentions specific node configuration requirements, GPUs, local SSDs, or workloads that need privileged containers. Autopilot is the recommended mode for new GKE workloads as of 2023.

### GKE Networking: VPC-Native Clusters

GKE clusters must be created as **VPC-native** (also called alias IP clusters). In a VPC-native cluster, each pod gets a real VPC IP address — not a NAT'd private address internal to the node. This is in contrast to older routes-based clusters where pod IPs were only reachable through custom routes.

```
VPC-native cluster (alias IPs):
  Node subnet CIDR:     10.0.0.0/24   (node IPs)
  Pod secondary CIDR:   10.4.0.0/14   (pod IPs — real VPC IPs)
  Service secondary CIDR: 10.0.32.0/20  (ClusterIP service IPs — virtual, only inside cluster)
```

Because pod IPs are real VPC addresses, on-premises networks and other VPCs can reach pods directly (via VPN or Interconnect) without any special configuration. There is no NAT hop for pod-to-pod or pod-to-external traffic within the same VPC.

The cluster uses three IP ranges:
- **Node subnet**: Primary range for the node VMs
- **Pod secondary range**: Alias IP range, one `/24` block allocated per node (up to 110 pods/node), carved from this larger range
- **Service secondary range**: Used for `ClusterIP` addresses — these are virtual IPs that only exist inside the cluster's `kube-proxy` iptables rules

```
Single node receives a /24 slice of pod CIDR:
  Node IP:    10.0.0.5     (from node subnet)
  Pod range:  10.4.2.0/24  (alias IP block on this node's NIC)
  Pod A:      10.4.2.1     (fully routable VPC IP)
  Pod B:      10.4.2.2     (fully routable VPC IP)
```

> **ACE exam tip:** VPC-native clusters are the default and are required for all new clusters. The exam may contrast them with older routes-based clusters. Remember: VPC-native = alias IPs on node NICs = pods have real VPC IPs.

### Services: ClusterIP, NodePort, LoadBalancer

Kubernetes Services give pods a stable DNS name and IP address, independent of which pods are currently running.

| Service type | Reachable from | How it works | Use when |
|---|---|---|---|
| `ClusterIP` | Inside the cluster only | Virtual IP on service CIDR, balanced to pods via kube-proxy iptables | Internal microservice-to-microservice communication |
| `NodePort` | Any node's external IP + port | Exposes a port (30000–32767) on every node, forwards to ClusterIP | Development, direct node access, custom LB in front of nodes |
| `LoadBalancer` | Internet (external IP) | Creates a GCP L4 Network Load Balancer with a static IP, forwards to NodePort on each node | Production external exposure of a single service |

In GKE, `type: LoadBalancer` creates a **passthrough Network Load Balancer** (formerly called External TCP/UDP LB) pointing to your nodes. GKE manages the LB lifecycle — create the Service and GKE provisions the LB; delete the Service and GKE deletes the LB.

For HTTP/HTTPS traffic at scale, prefer GKE **Ingress** (covered in the concept section below) which creates an HTTP(S) Load Balancer instead of a per-service L4 NLB.

### GKE Ingress

A Kubernetes `Ingress` resource in GKE provisions a **global HTTP(S) Load Balancer** (the same product you built manually in lab 06) using the `gce` Ingress class. One Ingress can route multiple hostnames and URL paths to different backend Services, sharing a single external IP and SSL certificate.

```
Internet → [HTTPS LB] → Ingress → /api/*   → Service: api-svc  → API pods
                                 → /app/*   → Service: app-svc  → App pods
                                 → default  → Service: web-svc  → Web pods
```

This is more efficient than creating a `LoadBalancer` Service for every application — each L4 NLB has a cost and its own IP. One Ingress with an HTTP(S) LB handles all your HTTP traffic.

> **ACE exam tip:** `Service type=LoadBalancer` creates an L4 NLB (one per service, TCP/UDP). `Ingress` creates an L7 HTTP(S) LB (one for many services, host/path routing, SSL termination, CDN). Know which to use: Ingress for HTTP/HTTPS applications, LoadBalancer for non-HTTP or simple single-service exposure.

### Node Pools

A **node pool** is a group of nodes within a Standard cluster that all share the same configuration: machine type, disk size, image type, labels, taints, and accelerators. A single cluster can have multiple node pools.

```
cluster: prod-cluster
  ├── node-pool: general     (n2-standard-4, 3 nodes)  ← stateless workloads
  ├── node-pool: memory-opt  (n2-highmem-8, 2 nodes)   ← memory-intensive apps
  └── node-pool: gpu-pool    (n1-standard-4 + T4, 1 node) ← ML inference
```

You direct pods to specific node pools using **node labels** and **node selectors**, or using **taints and tolerations** to prevent pods from being scheduled on a pool unless they explicitly tolerate the taint.

Node pools can be upgraded independently. GKE upgrade channels (Rapid / Regular / Stable) control how aggressively the cluster master and node pools are upgraded:

| Channel | Update cadence | Use when |
|---|---|---|
| Rapid | Latest Kubernetes release within days | Dev/test, you want new features early |
| Regular | ~2–3 months after release | Most production workloads (default) |
| Stable | ~5–6 months after release | Stability-critical production workloads |
| None | Manual only | You manage upgrade timing entirely |

### Workload Identity

Pods that need to call GCP APIs (Cloud Storage, Pub/Sub, BigQuery, etc.) used to need a GCP service account JSON key file mounted into the pod as a secret. This is insecure: keys can be exfiltrated, they do not rotate automatically, and they persist even after the pod is deleted.

**Workload Identity** replaces key files with an identity binding. A Kubernetes Service Account (KSA) in the cluster is linked to a GCP Service Account (GSA). When a pod using that KSA calls the GCP metadata server for a token, GKE's workload identity server intercepts the request and exchanges the KSA identity for a short-lived GCP token for the bound GSA.

```
Pod (KSA: my-app-ksa)
  → calls metadata server for token
  → GKE Workload Identity Webhook intercepts
  → exchanges KSA identity proof for GSA token
  → pod receives a short-lived OAuth2 token for my-gcp-sa@project.iam.gserviceaccount.com
  → pod calls Cloud Storage API with that token
```

The binding requires two annotations:
1. The KSA is annotated with `iam.gke.io/gcp-service-account=GSA_EMAIL`
2. The GSA is granted the `roles/iam.workloadIdentityUser` role for the KSA's identity

```yaml
# Kubernetes Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-ksa
  namespace: default
  annotations:
    iam.gke.io/gcp-service-account: my-gcp-sa@PROJECT_ID.iam.gserviceaccount.com
```

```bash
# Grant the GSA permission to be impersonated by the KSA
gcloud iam service-accounts add-iam-policy-binding \
  my-gcp-sa@PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:PROJECT_ID.svc.id.goog[default/my-app-ksa]"
```

> **ACE exam tip:** Workload Identity is the recommended way for pods to authenticate to GCP APIs. Never use service account key files mounted in pods — they are a security risk and the exam will steer you away from them. If a question asks "how should a GKE pod access Cloud Storage without key files?", the answer is Workload Identity.

### Horizontal Pod Autoscaler

The **Horizontal Pod Autoscaler (HPA)** watches a metric (CPU utilisation, memory, or custom metrics) and adjusts the number of pod replicas in a Deployment to keep the metric at a target value. It is different from the **cluster autoscaler**, which adds and removes nodes.

```
HPA:            adjusts pod count  → scales the app layer
Cluster autoscaler: adjusts node count → scales the infrastructure layer

Together:
  Load increases → HPA adds pods → pods cannot be scheduled (no capacity)
  → cluster autoscaler adds nodes → pods schedule → HPA stable
```

Both work automatically in Autopilot. In Standard, you must enable cluster autoscaling per node pool.

### ConfigMaps and Secrets

**ConfigMaps** store non-sensitive configuration data as key-value pairs. Pods consume ConfigMaps either as environment variables or as files mounted into a volume. Changing a ConfigMap does not automatically restart running pods — you must restart the pods to pick up changes if using environment variables; if using a volume mount, files update automatically (with a ~1 minute propagation delay).

**Secrets** store sensitive data (passwords, tokens, TLS certificates) encoded in base64. The base64 encoding is not encryption — anyone who can read the Secret object can decode it. For real security, use **Secret Manager** (lab 11) and access it via the application or via the Secret Manager add-on for GKE. Within a cluster, RBAC controls who can read Secret objects.

| | ConfigMap | Secret |
|---|---|---|
| Data sensitivity | Non-sensitive | Sensitive |
| Storage encoding | Plain text | Base64 (not encrypted by default) |
| Env var injection | `envFrom: configMapRef` | `envFrom: secretRef` |
| Volume mount | Files from config keys | Files from secret keys |
| Auto-update in volume | Yes (~1 min delay) | Yes (~1 min delay) |
| Auto-update as env var | No — requires pod restart | No — requires pod restart |
| RBAC | Standard K8s RBAC | Standard K8s RBAC (more restrictive recommended) |

---

## Setup

### Install the `gke-gcloud-auth-plugin`

GKE clusters require the `gke-gcloud-auth-plugin` component to authenticate `kubectl`. Without it, every `kubectl` command will fail with an auth error.

```bash
# Install the plugin
gcloud components install gke-gcloud-auth-plugin

# Verify
gke-gcloud-auth-plugin --version
```

Expected output:
```
Kubernetes Commands On GKE Gcloud Auth Plugin
Version: 0.5.x
```

If you are using a package-managed `gcloud` (e.g. via apt or brew) rather than the installer, install the plugin via the same package manager:

```bash
# Debian/Ubuntu
sudo apt-get install google-cloud-cli-gke-gcloud-auth-plugin

# macOS via Homebrew
brew install --cask google-cloud-sdk  # already includes plugin
```

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"
echo "Project: ${PROJECT_ID}, Region: ${REGION}"
```

---

## Exercises

### Exercise 1 — Create an Autopilot Cluster

Autopilot is the recommended mode for most workloads. You specify the cluster name and region — GKE handles all node management automatically.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud container clusters create-auto lab07-autopilot \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

This command takes 3–5 minutes. GKE provisions the control plane, enables Workload Identity, and configures networking. Expected output once complete:

```
Creating cluster lab07-autopilot in us-central1...done.
NAME              LOCATION     MASTER_VERSION   MASTER_IP      MACHINE_TYPE   NODE_VERSION   NUM_NODES  STATUS
lab07-autopilot   us-central1  1.29.x-gke.xxxx  xx.xxx.xxx.xxx  e2-small       1.29.x-gke.x   3          RUNNING
```

The `NUM_NODES` shown is a floor — Autopilot reports some baseline nodes but scales them dynamically based on your pod requests. You are not charged for idle nodes.

Describe the cluster to see its configuration:

```bash
gcloud container clusters describe lab07-autopilot \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(name,status,autopilot,networkConfig,privateClusterConfig)"
```

Expected output (partial):
```yaml
autopilot:
  enabled: true
name: lab07-autopilot
networkConfig:
  datapathProvider: ADVANCED_DATAPATH
  dnsConfig:
    clusterDns: CLOUD_DNS
    clusterDnsDomain: cluster.local
    clusterDnsScope: CLUSTER_SCOPE
  enableIntraNodeVisibility: true
  gatewayApiConfig:
    channel: CHANNEL_STANDARD
  network: projects/YOUR_PROJECT/global/networks/default
  serviceExternalIpsConfig: {}
  subnetwork: projects/YOUR_PROJECT/regions/us-central1/subnetworks/default
privateClusterConfig:
  privateEndpoint: 10.x.x.x
  publicEndpoint: x.x.x.x
status: RUNNING
```

Note `autopilot.enabled: true` confirming the mode.

> **Why Autopilot for this lab?** Autopilot's zero-idle-cost model means the cluster is affordable for learning. The GKE concepts — Deployments, Services, ConfigMaps, Secrets, HPA — work identically on Autopilot and Standard. The Workload Identity exercise in Exercise 9 uses a Standard cluster because Autopilot's security policy blocks the specific pod annotation pattern needed to demonstrate the pod-level setup.

---

### Exercise 2 — Connect kubectl to the Cluster

`kubectl` is the Kubernetes command-line client. To talk to your GKE cluster, you need to add the cluster's API server address and credentials to your local `~/.kube/config` file. The `get-credentials` command does this in one step.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud container clusters get-credentials lab07-autopilot \
  --region="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Fetching cluster endpoint and auth data.
kubeconfig entry generated for lab07-autopilot.
```

Verify `kubectl` can reach the cluster:

```bash
kubectl cluster-info
```

Expected output:
```
Kubernetes control plane is running at https://xx.xxx.xxx.xxx
GLBCDefaultBackend is running at https://xx.xxx.xxx.xxx/api/v1/namespaces/kube-system/services/default-http-backend:http/proxy
KubeDNS is running at https://xx.xxx.xxx.xxx/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

Check that the cluster nodes are visible (Autopilot shows system nodes):

```bash
kubectl get nodes
```

Expected output:
```
NAME                                            STATUS   ROLES    AGE     VERSION
gk3-lab07-autopilot-default-pool-xxxx-xxxx      Ready    <none>   3m      v1.29.x-gke.xxxx
```

Check the current kubectl context to confirm you are talking to the right cluster:

```bash
kubectl config current-context
```

Expected output:
```
gke_YOUR_PROJECT_us-central1_lab07-autopilot
```

> **ACE exam tip:** `gcloud container clusters get-credentials` is always the first step after creating a cluster. It writes a context entry to `~/.kube/config`. You can have multiple clusters configured — use `kubectl config use-context CONTEXT_NAME` to switch between them, or pass `--context` to individual `kubectl` commands.

---

### Exercise 3 — Deploy a Web Application

A Kubernetes **Deployment** declares the desired state for a set of pods: which container image to run, how many replicas, resource requests, and update strategy. The Deployment controller continuously reconciles the actual state (running pods) with the desired state.

Create a Deployment that runs three replicas of a simple nginx web server:

```bash
kubectl apply -f lab07-web-deployment.yaml
```

Expected output:
```
deployment.apps/lab07-web created
```

On Autopilot, GKE provisions nodes to satisfy the resource requests (3 × 100m CPU, 3 × 128Mi memory). This may take 60–90 seconds while nodes are provisioned. Watch the pods come up:

```bash
kubectl get pods -l app=lab07-web --watch
```

Expected output (progresses from Pending to Running):
```
NAME                        READY   STATUS    RESTARTS   AGE
lab07-web-7d9f8b6c9-abcde   0/1     Pending   0          10s
lab07-web-7d9f8b6c9-fghij   0/1     Pending   0          10s
lab07-web-7d9f8b6c9-klmno   0/1     Pending   0          10s
lab07-web-7d9f8b6c9-abcde   1/1     Running   0          75s
lab07-web-7d9f8b6c9-fghij   1/1     Running   0          80s
lab07-web-7d9f8b6c9-klmno   1/1     Running   0          82s
```

Press `Ctrl+C` to stop watching. Check the Deployment status:

```bash
kubectl get deployment lab07-web
```

Expected output:
```
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
lab07-web   3/3     3            3           2m
```

`3/3` means 3 desired replicas, all 3 ready.

Inspect one of the pods:

```bash
kubectl describe pod -l app=lab07-web | head -40
```

Expected output (partial):
```
Name:             lab07-web-7d9f8b6c9-abcde
Namespace:        default
Node:             gk3-lab07-autopilot-default-pool-xxxx-xxxx/10.128.0.5
Status:           Running
IP:               10.4.2.7
Containers:
  web:
    Image:          nginx:1.25
    Port:           80/TCP
    Limits:
      cpu:     250m
      memory:  256Mi
    Requests:
      cpu:     100m
      memory:  128Mi
    Ready:          True
```

Note the pod IP (e.g. `10.4.2.7`) — this is a real VPC IP from the pod secondary CIDR range, demonstrating VPC-native networking.

> **Why resource requests matter on Autopilot:** Autopilot bills based on the resource _requests_ you declare, not actual utilisation. If you declare no requests, Autopilot applies default values. Always set explicit requests to control costs and ensure predictable scheduling.

---

### Exercise 4 — Expose the Deployment with a LoadBalancer Service

A `ClusterIP` Service (the default) makes the pods reachable only inside the cluster. A `LoadBalancer` Service provisions a GCP L4 Network Load Balancer with a public IP, making the application reachable from the internet.

Create the LoadBalancer Service:

```bash
kubectl apply -f lab07-web-svc.yaml
```

Expected output:
```
service/lab07-web-svc created
```

Wait for GKE to provision the load balancer and assign an external IP (takes 1–2 minutes):

```bash
kubectl get service lab07-web-svc --watch
```

Expected output (EXTERNAL-IP changes from `<pending>` to an IP):
```
NAME            TYPE           CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE
lab07-web-svc   LoadBalancer   10.0.32.100   <pending>     80:31234/TCP   30s
lab07-web-svc   LoadBalancer   10.0.32.100   34.xxx.xxx.xxx   80:31234/TCP   90s
```

Press `Ctrl+C` once the external IP appears.

Test the application:

```bash
EXTERNAL_IP=$(kubectl get service lab07-web-svc \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Application URL: http://${EXTERNAL_IP}"
curl -s "http://${EXTERNAL_IP}" | head -5
```

Expected output:
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

Inspect the full Service definition to see how GKE wired up the load balancer:

```bash
kubectl describe service lab07-web-svc
```

Expected output (partial):
```
Name:                     lab07-web-svc
Namespace:                default
Type:                     LoadBalancer
IP:                       10.0.32.100
LoadBalancer Ingress:     34.xxx.xxx.xxx
Port:                     <unset>  80/TCP
NodePort:                 <unset>  31234/TCP
Endpoints:                10.4.2.7:80,10.4.2.8:80,10.4.2.9:80
```

The `Endpoints` line lists the actual pod IPs behind the service. The `NodePort` is the port on each node that the NLB forwards to.

> **Understand the traffic flow:** Internet → NLB (34.xxx.xxx.xxx:80) → Node NodePort (31234) → ClusterIP (10.0.32.100:80) → Pod (10.4.2.x:80). The NLB is a passthrough L4 balancer — it does not terminate the TCP connection, it forwards the packets to a node's NodePort. kube-proxy on that node then forwards to one of the pod IPs via iptables NAT rules.

---

### Exercise 5 — Scale the Deployment Manually and with HPA

#### Step 5a — Manual Scaling

Scale the Deployment from 3 replicas to 5:

```bash
kubectl scale deployment lab07-web --replicas=5
```

Expected output:
```
deployment.apps/lab07-web scaled
```

Watch the new pods come up:

```bash
kubectl get pods -l app=lab07-web --watch
```

Expected output:
```
NAME                        READY   STATUS    RESTARTS   AGE
lab07-web-7d9f8b6c9-abcde   1/1     Running   0          5m
lab07-web-7d9f8b6c9-fghij   1/1     Running   0          5m
lab07-web-7d9f8b6c9-klmno   1/1     Running   0          5m
lab07-web-7d9f8b6c9-pqrst   1/1     Running   0          30s
lab07-web-7d9f8b6c9-uvwxy   1/1     Running   0          30s
```

Scale back down to 3:

```bash
kubectl scale deployment lab07-web --replicas=3
```

#### Step 5b — Horizontal Pod Autoscaler

An HPA automatically adjusts the replica count based on observed metrics. Create an HPA targeting 50% CPU utilisation, allowing between 2 and 10 replicas:

```bash
kubectl autoscale deployment lab07-web \
  --min=2 \
  --max=10 \
  --cpu=50%
```

Expected output:
```
horizontalpodautoscaler.autoscaling/lab07-web autoscaled
```

Inspect the HPA:

```bash
kubectl get hpa lab07-web
```

Expected output:
```
NAME        REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
lab07-web   Deployment/lab07-web   0%/50%    2         10        3          30s
```

`TARGETS` shows `0%/50%` — current CPU is 0% (idle nginx pods), target is 50%. Since actual usage is below target, the HPA will scale down to `MINPODS=2` after the default 5-minute stabilization window (which prevents thrashing). Watch until `REPLICAS` drops to 2, then Ctrl+C:

```bash
watch -n 15 kubectl get hpa lab07-web
```

Expected output after scale-in:
```
NAME        REFERENCE              TARGETS   MINPODS   MAXPODS   REPLICAS   AGE
lab07-web   Deployment/lab07-web   0%/50%    2         10        2          5m
```

The HPA scaled the Deployment from 3 to 2 replicas because load was consistently below the 50% target.

Describe the HPA to see the scaling events:

```bash
kubectl describe hpa lab07-web
```

Expected output (partial):
```
Events:
  Type    Reason             Age    From                       Message
  ----    ------             ----   ----                       -------
  Normal  SuccessfulRescale  2m     horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
```

> **ACE exam tip:** HPA scales pods; the **cluster autoscaler** scales nodes. They work together: HPA requests more pods → pods are pending because there are not enough nodes → cluster autoscaler adds nodes → pods are scheduled. In Autopilot this node-level scaling is automatic. In Standard you must enable cluster autoscaling on node pools with `--enable-autoscaling`.

---

### Exercise 6 — Use a ConfigMap for Application Configuration

A ConfigMap decouples configuration from the container image. Instead of baking environment-specific values into your Docker image, you inject them at runtime. This means the same image can be deployed to development, staging, and production with different configurations.

Create a ConfigMap with application settings:

```bash
kubectl apply -f lab07-app-config.yaml
```

Expected output:
```
configmap/lab07-app-config created
```

Inspect the ConfigMap:

```bash
kubectl describe configmap lab07-app-config
```

Expected output:
```
Name:         lab07-app-config
Namespace:    default
Data
====
APP_ENV:
----
production
LOG_LEVEL:
----
info
MAX_CONNECTIONS:
----
100
welcome.html:
----
<!DOCTYPE html>
...
```

Now create a Deployment that consumes the ConfigMap two ways: as environment variables (for the key-value pairs) and as a mounted file (for `welcome.html`):

```bash
kubectl apply -f lab07-configmap-demo-deployment.yaml
```

Expected output:
```
deployment.apps/lab07-configmap-demo created
```

Wait for the pod to be running:

```bash
kubectl wait deployment lab07-configmap-demo \
  --for=condition=available \
  --timeout=120s
```

Exec into the pod to verify the environment variables and mounted file:

```bash
POD_NAME=$(kubectl get pod -l app=lab07-configmap-demo -o jsonpath='{.items[0].metadata.name}')

# Check environment variables
kubectl exec "${POD_NAME}" -- env | grep -E "^(APP_ENV|LOG_LEVEL|MAX_CONNECTIONS|welcome)"
```

Expected output:
```
LOG_LEVEL=info
MAX_CONNECTIONS=100
welcome.html=<!DOCTYPE html>
<html>
<head><title>Lab 07 - GKE</title></head>
...
APP_ENV=production
```

> **Note:** `welcome.html` appears as an env var because `envFrom: configMapRef` injects every key in the ConfigMap — including file contents. In practice, keep file-content keys in a separate ConfigMap from key-value config, or inject files only via volume mounts.

```bash
# Check the mounted file
kubectl exec "${POD_NAME}" -- cat /usr/share/nginx/html/welcome.html
```

Expected output:
```html
<!DOCTYPE html>
<html>
<head><title>Lab 07 - GKE</title></head>
<body>
<h1>Hello from GKE!</h1>
<p>Environment: production</p>
<p>Configured via ConfigMap</p>
</body>
</html>
```

> **The critical difference between env var and volume mount injection:** If you update the ConfigMap's `welcome.html` key, the file inside the pod will update automatically within ~60 seconds — no pod restart needed. But if you update `APP_ENV`, the environment variable inside the running pod does NOT change. Environment variables are set once at pod startup from the ConfigMap's snapshot. To propagate env var changes, you must restart the pods (e.g. `kubectl rollout restart deployment lab07-configmap-demo`).

---

### Exercise 7 — Use a Secret for Sensitive Configuration

Secrets work like ConfigMaps but are intended for sensitive data. The exam and real-world guidance is to never put passwords, API keys, or TLS certs in ConfigMaps.

Create a Secret with a simulated database password and API key:

```bash
# Secrets are created with --from-literal or from files.
# The values are automatically base64 encoded by kubectl.
kubectl create secret generic lab07-db-secret \
  --from-literal=DB_PASSWORD="s3cr3t-db-p@ssword" \
  --from-literal=API_KEY="lab07-api-key-12345"
```

Expected output:
```
secret/lab07-db-secret created
```

Inspect the Secret — notice the values are base64 encoded:

```bash
kubectl get secret lab07-db-secret -o yaml
```

Expected output:
```yaml
apiVersion: v1
data:
  API_KEY: bGFiMDctYXBpLWtleS0xMjM0NQ==
  DB_PASSWORD: czNjcjN0LWRiLXBAc3N3b3Jk
kind: Secret
metadata:
  name: lab07-db-secret
  namespace: default
type: Opaque
```

The values are base64 — decode them to verify:

```bash
echo "bGFiMDctYXBpLWtleS0xMjM0NQ==" | base64 --decode
```

Expected output:
```
lab07-api-key-12345
```

This confirms that base64 is encoding, not encryption. Anyone with `kubectl get secret` permission can read the values. Use GCP Secret Manager (lab 11) for true secrets management with audit logging, versioning, and encryption.

Create a pod that consumes the Secret both as environment variables and as volume-mounted files:

```bash
kubectl apply -f lab07-secret-demo-pod.yaml
```

Expected output:
```
pod/lab07-secret-demo created
```

Wait for the pod to start and verify both injection methods:

```bash
kubectl wait pod lab07-secret-demo --for=condition=ready --timeout=120s

# Check environment variable injection
kubectl exec lab07-secret-demo -- env | grep DB_PASSWORD
```

Expected output:
```
DB_PASSWORD=s3cr3t-db-p@ssword
```

```bash
# Check volume-mounted files — each Secret key becomes a file
kubectl exec lab07-secret-demo -- ls /etc/secrets
```

Expected output:
```
API_KEY
DB_PASSWORD
```

```bash
kubectl exec lab07-secret-demo -- cat /etc/secrets/API_KEY
```

Expected output:
```
lab07-api-key-12345
```

> **ACE exam tip:** On the exam, "mount a Secret as a file" uses `volumes.secret` + `volumeMounts`. "Inject a Secret as an environment variable" uses `env.valueFrom.secretKeyRef` or `envFrom.secretRef`. Know both patterns. The volume mount approach is generally preferred because the application reads the file each time, which allows Secret rotation without pod restart when using auto-rotation tools.

---

### Exercise 8 — Rolling Update and Rollback

Rolling updates replace pods one-by-one with a new version, maintaining availability throughout. Kubernetes tracks the history of Deployment changes, allowing you to roll back to any previous revision if a bad version is deployed.

#### Step 8a — Perform a Rolling Update

Update the `lab07-web` Deployment to use a newer nginx version. Observe the rollout strategy: by default, Kubernetes will create one new pod (maxSurge=1) and allow zero unavailable pods (maxUnavailable=0) during the update — ensuring full capacity is always available.

Update the image:

```bash
kubectl set image deployment/lab07-web web=nginx:1.26
```

Expected output:
```
deployment.apps/lab07-web image updated
```

Watch the rollout in progress:

```bash
kubectl rollout status deployment/lab07-web
```

Expected output (as pods are replaced one by one):
```
Waiting for deployment "lab07-web" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "lab07-web" rollout to finish: 1 old replicas are pending termination...
deployment "lab07-web" successfully rolled out
```

Verify all pods are running the new image:

```bash
kubectl get pods -l app=lab07-web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

Expected output:
```
lab07-web-6b7f9d4c8-aaaaa	nginx:1.26
lab07-web-6b7f9d4c8-bbbbb	nginx:1.26
```

#### Step 8b — Inspect Rollout History

Kubernetes stores rollout history as `ReplicaSet` snapshots. View the revision history:

```bash
kubectl rollout history deployment/lab07-web
```

Expected output:
```
deployment.apps/lab07-web
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

The `CHANGE-CAUSE` column is empty because we did not annotate the rollout with a reason. In production, use `--record` (deprecated) or annotate the Deployment with `kubernetes.io/change-cause`:

```bash
# Annotate the current revision with a description
kubectl annotate deployment/lab07-web kubernetes.io/change-cause="upgraded nginx to 1.26"

kubectl rollout history deployment/lab07-web
```

Expected output:
```
REVISION  CHANGE-CAUSE
1         <none>
2         upgraded nginx to 1.26
```

Inspect a specific revision:

```bash
kubectl rollout history deployment/lab07-web --revision=1
```

Expected output:
```
deployment.apps/lab07-web with revision #1
Pod Template:
  Labels: app=lab07-web
          pod-template-hash=7d9f8b6c9
  Containers:
   web:
    Image: nginx:1.25
    ...
```

#### Step 8c — Rollback to the Previous Version

Simulate discovering a problem with `nginx:1.26` and rolling back to the previous version:

```bash
kubectl rollout undo deployment/lab07-web
```

Expected output:
```
deployment.apps/lab07-web rolled back
```

Watch the rollback complete:

```bash
kubectl rollout status deployment/lab07-web
```

Expected output:
```
deployment "lab07-web" successfully rolled out
```

Verify the pods are back on the previous image:

```bash
kubectl get pods -l app=lab07-web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

Expected output:
```
lab07-web-7d9f8b6c9-ccccc	nginx:1.25
lab07-web-7d9f8b6c9-ddddd	nginx:1.25
```

To roll back to a specific revision (not just the previous one):

```bash
# Roll back to revision 1 specifically
kubectl rollout undo deployment/lab07-web --to-revision=1
```

> **ACE exam tip:** `kubectl rollout undo` reverts to the previous revision. To go back further, use `--to-revision=N`. Kubernetes stores up to `revisionHistoryLimit` ReplicaSets (default: 10). Older revisions beyond this limit are garbage collected and cannot be rolled back to. If rollback history matters to you, increase `revisionHistoryLimit` in the Deployment spec.

---

### Exercise 9 — Workload Identity: GCS Access from a Pod Without Key Files

This exercise requires a Standard cluster because you need to annotate a node pool with the workload identity metadata. Autopilot manages this automatically, but we create a small Standard cluster to demonstrate the explicit setup steps — which is what the exam tests.

#### Step 9a — Create a Standard Cluster with Workload Identity Enabled

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
ZONE="us-central1-a"

gcloud container clusters create lab07-standard \
  --zone="${ZONE}" \
  --num-nodes=2 \
  --machine-type=e2-medium \
  --workload-pool="${PROJECT_ID}.svc.id.goog" \
  --project="${PROJECT_ID}"
```

This takes 3–5 minutes. Expected output:
```
Creating cluster lab07-standard in us-central1-a...done.
NAME            LOCATION       MASTER_VERSION  MASTER_IP       MACHINE_TYPE  NUM_NODES  STATUS
lab07-standard  us-central1-a  1.29.x-gke.xxx  34.xxx.xxx.xxx  e2-medium     2          RUNNING
```

Switch kubectl context to the new cluster:

```bash
gcloud container clusters get-credentials lab07-standard \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"
```

All `kubectl` commands from here through Step 9e target `lab07-standard`.

#### Step 9b — Create a GCP Service Account and Grant GCS Access

```bash
# Create the GCP Service Account that pods will impersonate
gcloud iam service-accounts create lab07-gcs-reader \
  --display-name="Lab 07 GCS Reader" \
  --project="${PROJECT_ID}"

# Grant it read access to Cloud Storage
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:lab07-gcs-reader@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

Expected output (for the IAM binding):
```
Updated IAM policy for project [YOUR_PROJECT].
bindings:
...
- members:
  - serviceAccount:lab07-gcs-reader@YOUR_PROJECT.iam.gserviceaccount.com
  role: roles/storage.objectViewer
```

#### Step 9c — Create a Kubernetes Service Account and Bind It to the GCP SA

```bash
# Create the Kubernetes Service Account
kubectl create serviceaccount lab07-ksa \
  --namespace=default

# Annotate the KSA with the GCP SA email — this is the link
kubectl annotate serviceaccount lab07-ksa \
  --namespace=default \
  "iam.gke.io/gcp-service-account=lab07-gcs-reader@${PROJECT_ID}.iam.gserviceaccount.com"
```

Expected output:
```
serviceaccount/lab07-ksa created
serviceaccount/lab07-ksa annotated
```

Grant the GCP SA the `workloadIdentityUser` role for the KSA. This says: "the Kubernetes identity `default/lab07-ksa` in this project's cluster is allowed to impersonate the GCP SA":

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "lab07-gcs-reader@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[default/lab07-ksa]" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated IAM policy for serviceAccount [lab07-gcs-reader@YOUR_PROJECT.iam.gserviceaccount.com].
bindings:
- members:
  - serviceAccount:YOUR_PROJECT.svc.id.goog[default/lab07-ksa]
  role: roles/iam.workloadIdentityUser
```

#### Step 9d — Create a Test GCS Bucket and Object

```bash
# Create a bucket
gcloud storage buckets create "gs://lab07-wi-test-${PROJECT_ID}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

# Upload a test file
echo "Hello from Workload Identity!" | gcloud storage cp - "gs://lab07-wi-test-${PROJECT_ID}/hello.txt"
```

Expected output:
```
Creating gs://lab07-wi-test-YOUR_PROJECT/...
Completed files 1/1 | 30.0B/30.0B
```

#### Step 9e — Run a Pod That Reads GCS Using Workload Identity

Create a pod that uses the annotated KSA. The pod will call `gcloud storage cat` to read the file — and it will work without any key file, just by running as the annotated service account:

```bash
kubectl apply -f lab07-wi-test-pod.yaml
```

Wait for the pod to start:

```bash
kubectl wait pod lab07-wi-test --for=condition=ready --timeout=180s
```

Now exec into the pod and read the GCS file. No service account key file is present — the pod authenticates via Workload Identity:

```bash
kubectl exec lab07-wi-test -- gcloud storage cat "gs://lab07-wi-test-${PROJECT_ID}/hello.txt"
```

Expected output:
```
Hello from Workload Identity!
```

Verify which identity the pod is using:

```bash
kubectl exec lab07-wi-test -- gcloud auth list
```

Expected output:
```
                              Credentialed Accounts
ACTIVE  ACCOUNT
*       lab07-gcs-reader@YOUR_PROJECT.iam.gserviceaccount.com
```

The pod is authenticated as the GCP service account without any key file — only the Workload Identity binding.

Now intentionally break it: try running the same command from a pod WITHOUT the annotated service account:

```bash
kubectl run wi-test-no-sa \
  --image=google/cloud-sdk:slim \
  --restart=Never \
  --rm \
  -it \
  --command -- gcloud storage cat "gs://lab07-wi-test-${PROJECT_ID}/hello.txt"
```

Expected output (permission denied — no identity):
```
AccessDeniedException: 403 lab07-wi-test@... does not have storage.objects.get access to the Google Cloud Storage object.
```

This confirms that Workload Identity is what granted access — not ambient credentials or open GCS permissions.

> **ACE exam tip:** Workload Identity requires three things: (1) cluster created with `--workload-pool`, (2) KSA annotated with `iam.gke.io/gcp-service-account`, (3) GSA granted `roles/iam.workloadIdentityUser` for the KSA member. Missing any one of these three steps means the pod falls back to the node's default service account, which typically has no application permissions.

---

### Exercise 10 — Deliberate Failure: What Happens When a Deployment Has No Resources

This exercise intentionally causes a scheduling failure to teach you how to diagnose it. On Autopilot, scheduling failures are the most common cause of `Pending` pods.

Create a Deployment with resource requests that cannot be satisfied — requesting 64 CPUs on a cluster with 2 e2-medium nodes (each has 2 vCPUs):

```bash
# Switch back to the Autopilot cluster context
gcloud container clusters get-credentials lab07-autopilot \
  --region="${REGION}" \
  --project="${PROJECT_ID}"

kubectl apply -f lab07-impossible-deployment.yaml
```

Expected output:
```
deployment.apps/lab07-impossible created
```

Check the pod status — it will be stuck `Pending`:

```bash
kubectl get pods -l app=lab07-impossible
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS   AGE
lab07-impossible-xxxxxxxxx-yyyyy  0/1     Pending   0          30s
```

Describe the pod to see the scheduling failure reason:

```bash
POD_NAME=$(kubectl get pod -l app=lab07-impossible -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod "${POD_NAME}"
```

Expected output (partial — look for the Events section):
```
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  30s   default-scheduler  0/3 nodes are available:
           3 Insufficient cpu, 3 Insufficient memory.
           preemption: 0/3 nodes are available:
           3 No preemption victims found for incoming pod.
```

The scheduler tells you exactly why the pod cannot be placed: no node has 64 CPU and 256Gi memory available. On Autopilot, even though nodes are provisioned on demand, there is a maximum pod size limit — Autopilot pods cannot exceed the limits of a single node (max `n2-standard-32` equivalent).

Clean up the broken Deployment:

```bash
kubectl delete deployment lab07-impossible
```

> **ACE exam tip:** `Pending` pods are almost always caused by one of three things: (1) insufficient resources — fix by reducing requests or adding node capacity; (2) node selector / taint mismatch — no node matches the pod's scheduling constraints; (3) PersistentVolumeClaim not bound — the pod is waiting for storage. Always start debugging with `kubectl describe pod` and read the `Events` section.

---

## Key Takeaways

- **Autopilot** is the recommended GKE mode for most workloads. You pay only for pod resource requests, Google manages nodes, and security defaults are enforced. Choose **Standard** only when you need custom node configurations, GPUs, or workloads that Autopilot's hardened security policy rejects.

- **VPC-native clusters** give every pod a real VPC IP address from a secondary alias IP range. This means pods are directly routable within the VPC without NAT — other services and on-premises networks can reach pods as first-class network citizens.

- **`Service type=LoadBalancer`** creates a GCP L4 Network Load Balancer per service. **`Ingress`** creates a single GCP HTTP(S) Load Balancer shared across many services with host- and path-based routing. For HTTP/HTTPS applications, prefer Ingress to avoid paying for a separate L4 NLB per service.

- **Workload Identity** is the correct way for pods to call GCP APIs. It requires: cluster `--workload-pool` flag, KSA annotated with `iam.gke.io/gcp-service-account`, and the GSA granted `roles/iam.workloadIdentityUser` for the KSA. Never mount service account JSON key files into pods.

- **ConfigMaps** and **Secrets** both support env var injection and volume mount injection. Volume-mounted data updates automatically in ~60 seconds when the underlying object changes. Environment variable injection is frozen at pod start time — changes require a pod restart.

- `kubectl rollout undo` rolls back to the previous revision. Use `--to-revision=N` to target a specific revision. Kubernetes retains rollout history as ReplicaSets, up to `revisionHistoryLimit` (default: 10).

- **HPA** scales pod replicas based on metrics (CPU, memory, custom). The **cluster autoscaler** scales node count when pods cannot be scheduled. They are complementary and work together — HPA is not a substitute for the cluster autoscaler.

- **`Pending` pods** are diagnosed with `kubectl describe pod`. The `Events` section shows the scheduling failure reason: insufficient resources, taint/toleration mismatch, or unbound PersistentVolumeClaim.

- GKE upgrade **channels** (Rapid / Regular / Stable) control how quickly the cluster master and node pools receive Kubernetes version upgrades. Regular is the default and suits most production workloads. Stable delays upgrades by 5–6 months for maximum stability.

- **Node pools** in Standard clusters allow heterogeneous hardware within one cluster. Use node labels and `nodeSelector` to direct workloads to specific pools. Use taints and tolerations to reserve pools for specific workloads (e.g. GPU pools that only accept ML inference pods).

- **Base64 is not encryption.** Kubernetes Secrets are only as secure as your RBAC policy. For true secrets management with audit logging, versioning, and encryption at rest, use **GCP Secret Manager** and access it via the Secret Manager add-on or application SDK.

---

## Cleanup

Run all commands to destroy every resource created in this lab. Work through the Kubernetes resources first, then delete the GKE clusters, then delete the GCP resources.

```bash
# Check what exists before cleanup
../status.sh 7
```

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
ZONE="us-central1-a"

echo "=== Switching to Autopilot cluster context ==="
gcloud container clusters get-credentials lab07-autopilot \
  --region="${REGION}" \
  --project="${PROJECT_ID}"

echo "=== Deleting Kubernetes resources (Autopilot cluster) ==="
kubectl delete deployment lab07-web --ignore-not-found
kubectl delete deployment lab07-configmap-demo --ignore-not-found
kubectl delete deployment lab07-impossible --ignore-not-found
kubectl delete service lab07-web-svc --ignore-not-found
kubectl delete hpa lab07-web --ignore-not-found
kubectl delete configmap lab07-app-config --ignore-not-found
kubectl delete secret lab07-db-secret --ignore-not-found
kubectl delete pod lab07-secret-demo --ignore-not-found --grace-period=0

echo "=== Switching to Standard cluster context ==="
gcloud container clusters get-credentials lab07-standard \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"

echo "=== Deleting Kubernetes resources (Standard cluster) ==="
kubectl delete pod lab07-wi-test --ignore-not-found --grace-period=0
kubectl delete serviceaccount lab07-ksa --ignore-not-found

echo "=== Deleting Standard GKE cluster ==="
gcloud container clusters delete lab07-standard \
  --zone="${ZONE}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Autopilot GKE cluster ==="
gcloud container clusters delete lab07-autopilot \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting GCS bucket ==="
gcloud storage rm --recursive "gs://lab07-wi-test-${PROJECT_ID}" 2>/dev/null || echo "Bucket already deleted or does not exist."

echo "=== Deleting GCP Service Account ==="
gcloud iam service-accounts delete \
  "lab07-gcs-reader@${PROJECT_ID}.iam.gserviceaccount.com" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Removing IAM binding ==="
gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:lab07-gcs-reader@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer" 2>/dev/null || echo "IAM binding already removed."

echo "=== Cleanup complete ==="
```

Verify no clusters remain:

```bash
gcloud container clusters list \
  --filter="name:lab07" \
  --project="${PROJECT_ID}"
```

Expected output (empty):
```
Listed 0 items.
```

Verify the GCS bucket is deleted:

```bash
../status.sh 7
```

> **Note on cluster deletion time:** GKE clusters take 3–5 minutes to delete. The `--quiet` flag skips the confirmation prompt. If you run the deletion commands sequentially (as written above), the script will wait for each deletion to complete before proceeding to the next. Cluster deletion starts billing the moment you submit the command — the meter stops when deletion finishes, not when you run the command.