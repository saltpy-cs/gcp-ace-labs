# Lab 11 — Security: KMS, Secret Manager, and Cloud Armor

> **Cost warning:** This lab creates billable security resources.
> - Cloud KMS key version: $0.06/month per active key version.
> - Secret Manager: first 6 secret versions free, then $0.06 per 10K access operations.
> - Cloud Armor security policy: **$5.00/policy/month** — create only 1 policy and destroy
>   it promptly when you finish Exercise 7.
>
> Estimated total if completed in 2 hours and cleaned up promptly: **< $0.10**.
> The Cloud Armor policy is the only meaningful cost — do not leave it running overnight.

---

## Objectives

After completing this lab you will be able to:

- Create and manage Cloud KMS key rings and symmetric encryption keys
- Encrypt and decrypt a file on disk using `gcloud kms encrypt` and `gcloud kms decrypt`
- Store, version, and retrieve secrets using Secret Manager
- Grant a service account access to a specific secret version using IAM
- Enable CMEK (customer-managed encryption keys) for a Cloud Storage bucket
- Configure CMEK for a Cloud SQL instance at creation time
- Create a Cloud Armor security policy with IP-based allow and deny rules
- Attach a Cloud Armor security policy to an HTTP(S) load balancer backend service
- Add a geo-restriction rule to a Cloud Armor policy
- Explain the difference between GMEK, CMEK, and CSEK
- Explain the difference between Secret Manager and Cloud KMS and when to use each
- Understand the conceptual purpose of VPC Service Controls, Binary Authorization, OS Login, and Security Command Center

---

## Concepts

### GCP Encryption at Rest: Four Tiers

Every byte of data stored in GCP is encrypted at rest. The question is _who controls
the encryption keys_. GCP offers four distinct models, each representing a different
trade-off between convenience and control.

```
Control hierarchy (more control → more operational burden):

  Google-Managed Encryption Keys (GMEK)   ← default, free, zero effort
          ↓
  Customer-Managed Encryption Keys (CMEK) ← you own keys in Cloud KMS
          ↓
  Customer-Supplied Encryption Keys (CSEK) ← you provide key material per-request
          ↓
  Client-Side Encryption                   ← you encrypt before data ever leaves your system
```

| Model | Who holds the key | Key storage | Use when |
|---|---|---|---|
| **GMEK** | Google | Google-internal KMS | Default — fine for most workloads |
| **CMEK** | You (in Cloud KMS) | Cloud KMS in your project | Compliance requiring key ownership; ability to revoke access by destroying key |
| **CSEK** | You (in your systems) | Not stored in GCP — you send it per-request | Strict key custody requirements; GCP never stores the key material at all |
| **Client-side** | You (in your systems) | Anywhere you choose | Data must be encrypted before it reaches Google's infrastructure |

**GMEK** is automatic. GCP creates per-resource data encryption keys (DEKs), wraps them
with a key encryption key (KEK), and rotates everything automatically. There is no
configuration required and no cost.

**CMEK** means you create a key in Cloud KMS and tell a GCP service (GCS, BigQuery,
Cloud SQL, etc.) to use that key instead of Google's. GCP still does the encryption —
but it uses _your_ key. The critical implication: if you disable or destroy your KMS key,
GCP can no longer read the encrypted data. This gives you a "nuclear option" to revoke
access instantly — useful when you need to meet data residency or regulatory requirements
that mandate you hold the key, not the cloud provider.

**CSEK** goes further: you supply the raw key material in each API request. GCP uses
it only in memory to perform the operation and does not store it. Currently supported
only by Cloud Storage and Compute Engine persistent disks. If you lose the key, your
data is permanently unrecoverable.

> **ACE exam tip:** The exam frequently tests CMEK. Know that CMEK requires the service's
> service account (e.g., the GCS service agent) to have the `cloudkms.cryptoKeyEncrypterDecrypter`
> IAM role on the KMS key. Without this role the service cannot read or write data, and
> operations will fail with a "permission denied on KMS key" error.

On AWS, CMEK maps to **SSE-KMS** (Server-Side Encryption with AWS KMS Customer-Managed
Keys). AWS also has SSE-C for customer-supplied keys, analogous to GCP's CSEK.

---

### Cloud KMS: Key Hierarchy

Cloud KMS organises keys into a three-level hierarchy:

```
Project
  └── Key Ring (regional or global)
        └── Key (purpose: ENCRYPT_DECRYPT, ASYMMETRIC_SIGN, etc.)
              └── Key Version (actual cryptographic material)
                    - Primary version: used for new encryptions
                    - Enabled versions: can still decrypt old ciphertext
                    - Disabled versions: decrypt blocked (data inaccessible)
                    - Destroyed versions: key material deleted (data permanently gone)
```

**Key rings** are containers for keys. They cannot be deleted once created — only the
keys and key versions inside them can be destroyed. Key rings are regional; you should
create a key ring in the same region as the data it will protect (to avoid cross-region
latency and to satisfy data residency requirements).

**Keys** have a _purpose_ that determines the cryptographic operations allowed:

| Purpose | Operations | Use case |
|---|---|---|
| `ENCRYPT_DECRYPT` | Symmetric encrypt / decrypt | Protecting data at rest (CMEK for GCS, SQL, etc.) |
| `ASYMMETRIC_SIGN` | Sign / verify (RSA or EC) | Code signing, JWT signing, certificate issuance |
| `ASYMMETRIC_DECRYPT` | Encrypt (public key) / decrypt (private key) | Encrypting data for a specific recipient |
| `MAC` | Create / verify HMAC | Message authentication codes |

**Key versions** hold the actual cryptographic material. Each rotation creates a new
version. The _primary_ version is used for all new encrypt operations. Older versions
remain _enabled_ so you can still decrypt data encrypted under them — until you choose
to disable or destroy them.

Key rotation can be manual (you call `gcloud kms keys versions create`) or automatic
(set `--rotation-period` on the key and GCP rotates on schedule). Rotation creates a
new primary version; old versions are not automatically destroyed.

> **ACE exam tip:** Disabling a key version makes data encrypted under it **temporarily
> inaccessible** — it can be re-enabled. Destroying a key version makes that data
> **permanently inaccessible**. For CMEK-protected resources this is the "break glass"
> revocation mechanism. The exam tests whether you know the difference between disabled
> (reversible) and destroyed (irreversible).

---

### Secret Manager vs Cloud KMS

These two services are frequently confused. They solve related but distinct problems.

| | Secret Manager | Cloud KMS |
|---|---|---|
| **Purpose** | Store and manage secrets (API keys, passwords, certificates, connection strings) | Manage encryption keys and perform cryptographic operations |
| **What you store** | The secret value itself (up to 64 KiB) | Key metadata — actual key material lives in HSMs |
| **Versioning** | Yes — each update creates a new version; old versions remain accessible | Yes — each rotation creates a new key version |
| **Access control** | IAM roles on individual secrets (`secretmanager.secretAccessor`) | IAM roles on keys (`cloudkms.cryptoKeyEncrypterDecrypter`) |
| **Replication** | Automatic (multi-region) or user-managed (pick specific regions) | Regional (key ring is tied to a region) |
| **Audit logging** | Every access logged in Cloud Audit Logs | Every crypto operation logged in Cloud Audit Logs |
| **Typical use** | Database password that your app reads at startup | CMEK key that GCS uses to encrypt objects |

They complement each other. A common pattern: store a database password in Secret
Manager, and configure the Secret Manager secret to be encrypted using a Cloud KMS CMEK
key. Now you get both secret management (versioning, rotation, access control) and key
ownership (CMEK).

On AWS:
- Secret Manager ≈ **AWS Secrets Manager** (almost identical concept)
- Cloud KMS ≈ **AWS KMS** (with Customer Managed Keys / CMKs)

> **ACE exam tip:** If an exam question involves an application reading a database
> password or API token, the answer is **Secret Manager**. If it involves controlling
> who can read data stored in GCS or BigQuery, the answer is **CMEK via Cloud KMS**.
> These are complementary services — you often use both.

---

### Cloud Armor

Cloud Armor is GCP's Web Application Firewall (WAF) and DDoS protection service. It
is attached to a **backend service** on a global external HTTP(S) load balancer and
evaluates a security policy against every inbound request before it reaches your backends.

```
Internet → [Forwarding Rule] → [Target HTTP(S) Proxy] → [URL Map]
         → [Backend Service + Cloud Armor Policy] → [MIG / NEG]
```

Cloud Armor is only available on the global external HTTP(S) load balancer. It does not
work with internal load balancers, passthrough Network LBs, or regional external HTTP(S)
LBs. This is an important exam constraint.

**Security policy structure:**

A security policy contains an ordered list of rules. Each rule has:
- A **priority** (lower number = evaluated first)
- A **match condition** (IP range, geographic origin, CEL expression, reCAPTCHA score, WAF signature)
- An **action** (`allow`, `deny(403)`, `deny(404)`, `deny(429)`, `throttle`, `rate_based_ban`, `redirect`)

Rules are evaluated top to bottom by priority. The first matching rule wins. There is
always a default rule at priority 2147483647 (the maximum integer) that you configure
to either `allow` or `deny` everything not matched by higher-priority rules.

**Rule types:**

| Rule type | Syntax in gcloud | Purpose |
|---|---|---|
| IP allow/deny | `--src-ip-ranges` | Block or allow specific IP CIDRs |
| Geo-restriction | `origin.region_code == 'CN'` in CEL | Block traffic from specific countries |
| WAF pre-configured | `--action=deny --expression=evaluatePreconfiguredWaf(...)` | OWASP ModSecurity Core Rule Set (SQLi, XSS, etc.) |
| Rate limiting | `--action=throttle` or `--action=rate_based_ban` | Limit requests per IP per minute |
| reCAPTCHA | `token.recaptcha_exemption.valid` | Challenge bot traffic |

**Rate limiting modes:**

- `THROTTLE`: Allow up to N requests/minute per client; excess requests get the configured
  deny response but the client is not banned.
- `RATE_BASED_BAN`: Allow up to N requests/minute per client; once a client exceeds the
  threshold they are banned for a configurable duration (e.g., 600 seconds).

> **ACE exam tip:** Cloud Armor is the answer for WAF, DDoS protection, IP allow/deny,
> geo-blocking, and rate limiting on public HTTP(S) workloads. It is NOT a network-layer
> firewall (that is VPC firewall rules). It operates at L7 (HTTP) on the LB, not at the
> network level.

On AWS, the equivalent is **AWS WAF** + **AWS Shield** (Standard/Advanced).

---

### VPC Service Controls (Conceptual)

VPC Service Controls (VPC-SC) is an organisation-level perimeter control that restricts
which services can exchange data, regardless of IAM permissions. Where IAM controls
_who_ can access a resource, VPC-SC controls _from where_ that access can occur.

```
Without VPC-SC:
  Developer laptop → gcloud → BigQuery API → data exfiltrated to attacker's GCS bucket

With VPC-SC perimeter around BigQuery and GCS:
  Developer laptop → gcloud → BigQuery API → attempt to copy to bucket OUTSIDE perimeter → BLOCKED
```

A **service perimeter** defines a boundary around a set of projects and GCP services.
API calls crossing the perimeter boundary are blocked unless explicitly allowed by an
**access policy** (based on device trust, IP ranges, or user identity via Access Context
Manager).

VPC-SC is configured at the **organisation level** and requires Organisation Admin
permissions. This lab does not configure it (organisation-level setup is outside the
scope of a project-level lab) but you need to understand it conceptually for the ACE exam.

> **ACE exam tip:** VPC Service Controls protect against **data exfiltration** scenarios.
> If an exam question describes an attacker with compromised credentials copying BigQuery
> data to an external bucket, or a malicious insider exfiltrating data across project
> boundaries, VPC-SC is the control that prevents it. IAM alone cannot stop someone with
> legitimate access from copying data to a location outside your organisation.

---

### Binary Authorization (Conceptual)

Binary Authorization is a policy-based control that ensures only trusted, cryptographically
signed container images are deployed to GKE, Cloud Run, or GKE Autopilot. It integrates
with Container Analysis (which scans images for vulnerabilities) and Artifact Registry.

The workflow:
1. Your CI/CD pipeline builds an image and pushes it to Artifact Registry.
2. A trusted attestor (e.g., a security team system) signs the image with a cryptographic
   key, creating an **attestation** that says "this image passed security checks."
3. Binary Authorization's **admission controller** intercepts every deploy request and
   checks that the image has the required attestation from the trusted attestor.
4. Unsigned or insufficiently attested images are blocked from deploying.

Binary Authorization is enabled per GKE cluster or Cloud Run service and is configured
via a policy YAML. It uses Cloud KMS for key management (attestors sign using KMS keys).

> **ACE exam tip:** Binary Authorization is the answer when an exam question involves
> ensuring only approved, signed container images are deployed to GKE. It enforces
> supply chain security at deploy time, not at build time.

---

### OS Login

By default, Compute Engine SSH access is managed by SSH keys stored in project or instance
metadata. Anyone who can modify project metadata can add an SSH public key and gain access
to every VM in the project.

**OS Login** replaces metadata-based SSH key management with IAM. When OS Login is
enabled on a VM (via the `enable-oslogin=true` metadata key or an organisation policy),
SSH access is controlled by two IAM roles:

| Role | Access level |
|---|---|
| `roles/compute.osLogin` | Login as a non-root user |
| `roles/compute.osAdminLogin` | Login as a user with `sudo` (root access) |

OS Login also integrates with **2-Step Verification**: if a user's Google account requires
2FA, that 2FA is enforced for SSH as well.

The project-level `enable-oslogin` metadata key applies to all VMs in the project. You
can override it per-VM by setting `enable-oslogin=false` on a specific instance.

> **ACE exam tip:** OS Login is the recommended way to manage SSH access on GCE at scale.
> It centralises access control in IAM, removes the risk of orphaned SSH keys in metadata,
> and integrates with 2FA. The exam may describe a scenario where "a departed employee
> still has SSH access" — the fix is OS Login so access is controlled by the employee's
> Google account status (which gets disabled by the IdP when they leave).

---

### Security Command Center

Security Command Center (SCC) is GCP's centralised security management and risk platform.
It aggregates findings from multiple sources:

| Source | What it finds |
|---|---|
| Security Health Analytics | Misconfigured firewall rules (port 22 open to 0.0.0.0/0), public buckets, missing audit logs, disabled MFA |
| Event Threat Detection | Crypto mining activity, data exfiltration, brute force attempts, anomalous IAM activity |
| Container Threat Detection | Suspicious container activity on GKE |
| Web Security Scanner | XSS, mixed content, outdated libraries in App Engine and GKE web apps |
| Third-party integrations | Findings from partner security tools |

SCC has two tiers: **Standard** (free, limited findings) and **Premium** (paid, full
threat detection). For the ACE exam, know that SCC exists and what category of problems
it surfaces — you are not expected to configure it in depth.

---

### Shielded VMs

A Shielded VM is a Compute Engine VM with three hardware-level security features:

- **Secure Boot**: Only signed boot firmware and OS kernels can boot. Prevents rootkits
  and bootkits that execute before the OS loads.
- **vTPM (virtual Trusted Platform Module)**: Creates a hardware root of trust. Measures
  the boot sequence and can detect if the VM was tampered with between boots.
- **Integrity Monitoring**: Compares the current boot measurements against a known-good
  baseline. If a deviation is detected, a Cloud Monitoring alert can be triggered.

Shielded VMs are enabled when creating an instance with `--shielded-secure-boot`,
`--shielded-vtpm`, and `--shielded-integrity-monitoring` flags. All three are enabled
by default on Shielded VM images.

> **ACE exam tip:** Shielded VMs protect against firmware-level and boot-level attacks.
> If an exam scenario mentions "rootkit", "bootkit", "UEFI firmware tampering", or
> "verify VM boot integrity", Shielded VMs are the answer.

---

## Setup

### APIs

Enable the APIs required for this lab:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud services enable \
  cloudkms.googleapis.com \
  secretmanager.googleapis.com \
  compute.googleapis.com \
  sqladmin.googleapis.com \
  storage.googleapis.com \
  --project="${PROJECT_ID}"
```

Expected output:
```
Operation "operations/acf.p2-..." finished successfully.
```

Verify they are all enabled:

```bash
gcloud services list --enabled \
  --filter="name:(cloudkms OR secretmanager OR compute OR sqladmin OR storage)" \
  --format="table(name,title)" \
  --project="${PROJECT_ID}"
```

Expected output:
```
NAME                        TITLE
cloudkms.googleapis.com     Cloud Key Management Service (KMS) API
compute.googleapis.com      Compute Engine API
secretmanager.googleapis.com Secret Manager API
sqladmin.googleapis.com     Cloud SQL Admin API
storage.googleapis.com      Cloud Storage JSON API
```

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export KEYRING_NAME="lab11-keyring"
export KEY_NAME="lab11-symmetric-key"
echo "Project: ${PROJECT_ID}, Region: ${REGION}"
```

### Working Directory

Create a local working directory for the files you will encrypt and decrypt:

```bash
mkdir -p ~/lab11-workdir
cd ~/lab11-workdir
echo "Lab 11 working directory ready."
```

---

## Exercises

### Exercise 1 — Create a KMS Key Ring and Symmetric Encryption Key

A key ring must be created before any keys. Key rings are regional and permanent — once
created, a key ring cannot be deleted. Choose the region carefully; keys should be
co-located with the data they protect to avoid cross-region latency and to satisfy data
residency requirements.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
KEYRING_NAME="lab11-keyring"
KEY_NAME="lab11-symmetric-key"

# Create the key ring
gcloud kms keyrings create "${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created CryptoKey [projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring].
```

Now create a symmetric encryption key inside the key ring. The `ENCRYPT_DECRYPT` purpose
means this key can only be used for symmetric encryption operations — not signing or MAC:

```bash
gcloud kms keys create "${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --purpose=encryption \
  --rotation-period=90d \
  --next-rotation-time="$(date -u -d '+90 days' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v+90d '+%Y-%m-%dT%H:%M:%SZ')" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created CryptoKey [projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key].
```

Verify the key ring and key were created:

```bash
echo "=== Key Ring ==="
gcloud kms keyrings describe "${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

echo ""
echo "=== Symmetric Key ==="
gcloud kms keys describe "${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="yaml(name,purpose,primary.state,rotationSchedule)"
```

Expected output:
```yaml
name: projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key
primary:
  state: ENABLED
purpose: ENCRYPT_DECRYPT
rotationSchedule:
  nextRotationTime: '2026-09-XX...'
  rotationPeriod: 7776000s
```

> **Why set a rotation period?** Cryptographic best practice is to rotate keys regularly.
> Even if a key is compromised, the blast radius is limited to data encrypted under a single
> key version. Setting a 90-day rotation creates a new primary version automatically. Old
> versions remain enabled so existing ciphertext can still be decrypted — they are not
> destroyed by rotation.

List all key versions (initially just version 1):

```bash
gcloud kms keys versions list \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
NAME                                                                                                           STATE
projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key/cryptoKeyVersions/1  ENABLED
```

---

### Exercise 2 — Encrypt and Decrypt a File Using Cloud KMS

This exercise uses the KMS key you just created to encrypt a plaintext file and then
decrypt the resulting ciphertext. This demonstrates how CMEK works under the hood —
when GCS or Cloud SQL uses CMEK, it performs exactly these operations on your behalf.

Create a plaintext file to encrypt:

```bash
cd ~/lab11-workdir

cat > secret_config.txt << 'EOF'
DATABASE_PASSWORD=s3cur3P@ssw0rd!
API_KEY=abc123xyz456def789
INTERNAL_ENDPOINT=http://internal.corp.example.com/api
EOF

echo "Plaintext file created:"
cat secret_config.txt
```

Encrypt the file using your KMS key. The `--plaintext-file` flag reads from disk;
`--ciphertext-file` writes the encrypted binary output:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
KEYRING_NAME="lab11-keyring"
KEY_NAME="lab11-symmetric-key"

gcloud kms encrypt \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --plaintext-file=secret_config.txt \
  --ciphertext-file=secret_config.txt.enc \
  --project="${PROJECT_ID}"

echo "Encryption complete."
ls -lh secret_config.txt secret_config.txt.enc
```

Expected output:
```
Encryption complete.
-rw-r--r--  1 user  staff   94B  Jun 17 10:12 secret_config.txt
-rw-r--r--  1 user  staff  154B  Jun 17 10:12 secret_config.txt.enc
```

The `.enc` file is binary ciphertext — it is unreadable without the KMS key. Verify
this by attempting to read it:

```bash
# This will show binary garbage — the encryption worked
file secret_config.txt.enc
```

Expected output:
```
secret_config.txt.enc: data
```

Now decrypt the ciphertext back to plaintext. This simulates what an application would
do at startup when it needs to read encrypted configuration:

```bash
gcloud kms decrypt \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --ciphertext-file=secret_config.txt.enc \
  --plaintext-file=decrypted_config.txt \
  --project="${PROJECT_ID}"

echo "Decryption complete. Recovered content:"
cat decrypted_config.txt
```

Expected output:
```
Decryption complete. Recovered content:
DATABASE_PASSWORD=s3cur3P@ssw0rd!
API_KEY=abc123xyz456def789
INTERNAL_ENDPOINT=http://internal.corp.example.com/api
```

**Break it — simulate key revocation.** Disable the key version and attempt to decrypt:

```bash
# Disable key version 1
gcloud kms keys versions disable 1 \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

echo "Key version 1 disabled. Attempting decrypt..."
gcloud kms decrypt \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --ciphertext-file=secret_config.txt.enc \
  --plaintext-file=should_fail.txt \
  --project="${PROJECT_ID}"
```

Expected error:
```
ERROR: (gcloud.kms.decrypt) FAILED_PRECONDITION: projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key/cryptoKeyVersions/1 is not enabled.
```

This is exactly what happens when a CMEK key is disabled: GCP services lose the ability
to decrypt data, and operations on CMEK-protected resources start failing. Re-enable the
key version to restore access:

```bash
gcloud kms keys versions enable 1 \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}"

echo "Key version 1 re-enabled."
```

Expected output:
```
Key version 1 re-enabled.
```

> This is the "break glass" scenario in reverse. A real incident response might involve
> disabling (not destroying) a KMS key to immediately halt access to a compromised data
> set, investigating the incident, then re-enabling once the threat is contained. Destroying
> is permanent — only do that when you want to make data unrecoverable forever.

---

### Exercise 3 — Create a Secret Manager Secret and Add Versions

Secret Manager is the right tool for storing credentials your applications need at runtime:
database passwords, API tokens, TLS private keys, and OAuth client secrets. Unlike Cloud
KMS (which stores _keys_ and performs _operations_), Secret Manager stores the _secret
value itself_ and handles versioning and access control.

Create a secret. The secret is a container — it has metadata (name, replication policy,
labels) but no value until you add a version:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud secrets create lab11-db-password \
  --replication-policy=automatic \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created secret [projects/YOUR_PROJECT/secrets/lab11-db-password].
```

Add version 1 — the initial password value. Pipe the value via stdin to avoid it
appearing in shell history or process listings:

```bash
echo -n "InitialPassword_v1_$RANDOM" | \
  gcloud secrets versions add lab11-db-password \
  --data-file=- \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created version [1] of the secret [lab11-db-password].
```

Access the secret value (simulates what an application does at startup):

```bash
gcloud secrets versions access latest \
  --secret=lab11-db-password \
  --project="${PROJECT_ID}"
```

Expected output (your random value will differ):
```
InitialPassword_v1_17423
```

Rotate the secret by adding version 2. In a real rotation workflow this would be a new
password that you have already applied to the database:

```bash
echo -n "RotatedPassword_v2_SecureR@ndom!" | \
  gcloud secrets versions add lab11-db-password \
  --data-file=- \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created version [2] of the secret [lab11-db-password].
```

List all versions and observe that both are active:

```bash
gcloud secrets versions list lab11-db-password \
  --project="${PROJECT_ID}" \
  --format="table(name,state,createTime)"
```

Expected output:
```
NAME                                                                              STATE    CREATE_TIME
projects/YOUR_PROJECT/secrets/lab11-db-password/versions/2  ENABLED  2026-06-17T10:...Z
projects/YOUR_PROJECT/secrets/lab11-db-password/versions/1  ENABLED  2026-06-17T10:...Z
```

`latest` always refers to the highest-numbered enabled version. Access a specific older
version by number:

```bash
# Access version 1 explicitly (the old password)
gcloud secrets versions access 1 \
  --secret=lab11-db-password \
  --project="${PROJECT_ID}"
```

Expected output (the old password value):
```
InitialPassword_v1_17423
```

After completing a rotation and confirming all applications are using the new password,
disable the old version to prevent any accidental access:

```bash
gcloud secrets versions disable 1 \
  --secret=lab11-db-password \
  --project="${PROJECT_ID}"

echo "Version 1 disabled."
gcloud secrets versions list lab11-db-password \
  --project="${PROJECT_ID}" \
  --format="table(name,state)"
```

Expected output:
```
NAME                                                                              STATE
projects/YOUR_PROJECT/secrets/lab11-db-password/versions/2  ENABLED
projects/YOUR_PROJECT/secrets/lab11-db-password/versions/1  DISABLED
```

> **ACE exam tip:** `latest` always resolves to the latest _enabled_ version. Disabling
> an old version does not change what `latest` points to. Destroying a version is
> irreversible — the secret value is permanently gone. For compliance purposes you may
> need to destroy versions (e.g., after a credential leak) so the old value is
> unrecoverable even to Google.

---

### Exercise 4 — Grant a Service Account Access to a Specific Secret

Applications should not run as your user account. They run as service accounts with only
the permissions they need. In this exercise you create a service account for an
application and grant it access to exactly one secret version — not the whole project.

Create a service account representing the application:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud iam service-accounts create lab11-app-sa \
  --display-name="Lab 11 Application Service Account" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created service account [lab11-app-sa].
```

Grant the service account the `secretmanager.secretAccessor` role on the specific
secret (not on the whole project). This follows the principle of least privilege —
the service account can only read `lab11-db-password`, nothing else:

```bash
gcloud secrets add-iam-policy-binding lab11-db-password \
  --member="serviceAccount:lab11-app-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated IAM policy for secret [lab11-db-password].
bindings:
- members:
  - serviceAccount:lab11-app-sa@YOUR_PROJECT.iam.gserviceaccount.com
  role: roles/secretmanager.secretAccessor
etag: ...
version: 1
```

Verify the policy on the secret:

```bash
gcloud secrets get-iam-policy lab11-db-password \
  --project="${PROJECT_ID}" \
  --format="yaml"
```

Expected output:
```yaml
bindings:
- members:
  - serviceAccount:lab11-app-sa@YOUR_PROJECT.iam.gserviceaccount.com
  role: roles/secretmanager.secretAccessor
etag: ...
version: 1
```

> Notice the role is granted on the **secret resource** (`gcloud secrets add-iam-policy-binding`)
> not on the project (`gcloud projects add-iam-policy-binding`). This is resource-level
> IAM. The service account cannot access any other secret in the project, cannot list
> secrets, and cannot modify the secret — it can only read the value of this one secret.
> This is the correct pattern for production applications.

You can also grant access to a specific version using the version's resource name.
This is useful when you want to lock an application to a particular version during a
controlled migration:

```bash
# Grant access to version 2 specifically (useful during gradual rollouts)
gcloud secrets versions add-iam-policy-binding 2 \
  --secret=lab11-db-password \
  --member="serviceAccount:lab11-app-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretVersionManager" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated IAM policy for secret version [2] of secret [lab11-db-password].
```

---

### Exercise 5 — Enable CMEK for a Cloud Storage Bucket

This exercise creates a GCS bucket and configures it to use your Cloud KMS key instead
of Google's default encryption. Every object written to this bucket will be encrypted
with your key. If you disable or destroy the key, the objects become inaccessible.

First, grant the GCS service agent (the system service account GCS uses internally)
permission to use your KMS key for encryption and decryption. Without this step, GCS
will not be able to write objects to the bucket:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
KEYRING_NAME="lab11-keyring"
KEY_NAME="lab11-symmetric-key"

# Get the GCS service agent email address for this project
GCS_SERVICE_AGENT=$(gcloud storage service-agent \
  --project="${PROJECT_ID}")

echo "GCS service agent: ${GCS_SERVICE_AGENT}"
```

Expected output:
```
GCS service agent: service-123456789@gs-project-accounts.iam.gserviceaccount.com
```

Grant the service agent the `cloudkms.cryptoKeyEncrypterDecrypter` role on your key:

```bash
gcloud kms keys add-iam-policy-binding "${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --member="serviceAccount:${GCS_SERVICE_AGENT}" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated IAM policy for key [lab11-symmetric-key].
```

Now create the bucket with CMEK enabled:

```bash
KMS_KEY_ID="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"

gcloud storage buckets create "gs://lab11-cmek-bucket-${PROJECT_ID}" \
  --location="${REGION}" \
  --default-encryption-key="${KMS_KEY_ID}" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Creating gs://lab11-cmek-bucket-YOUR_PROJECT/...
```

Verify the bucket has CMEK configured:

```bash
gcloud storage buckets describe "gs://lab11-cmek-bucket-${PROJECT_ID}" \
  --format="yaml(name,encryption)" \
  --project="${PROJECT_ID}"
```

Expected output:
```yaml
encryption:
  defaultKmsKeyName: projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key
name: lab11-cmek-bucket-YOUR_PROJECT
```

Write an object to the CMEK bucket and verify its encryption key:

```bash
echo "This object is protected by my CMEK key" | \
  gcloud storage cp - "gs://lab11-cmek-bucket-${PROJECT_ID}/test-object.txt" \
  --project="${PROJECT_ID}"

gcloud storage objects describe \
  "gs://lab11-cmek-bucket-${PROJECT_ID}/test-object.txt" \
  --format="yaml(name,kmsKey)" \
  --project="${PROJECT_ID}"
```

Expected output:
```yaml
kmsKey: projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key/cryptoKeyVersions/1
name: lab11-cmek-bucket-YOUR_PROJECT/test-object.txt
```

The object is encrypted with your key, version 1. When key rotation occurs, new objects
will use version 2; this object retains version 1 encryption until you explicitly
re-encrypt it or it is overwritten.

> **Break it** — disable the KMS key and try to read the object:
>
> ```bash
> gcloud kms keys versions disable 1 \
>   --key="${KEY_NAME}" \
>   --keyring="${KEYRING_NAME}" \
>   --location="${REGION}" \
>   --project="${PROJECT_ID}"
>
> gcloud storage cp \
>   "gs://lab11-cmek-bucket-${PROJECT_ID}/test-object.txt" /tmp/recovered.txt \
>   --project="${PROJECT_ID}"
> ```
>
> Expected error:
> ```
> ERROR: ... FAILED_PRECONDITION: The key ... is not enabled.
> ```
>
> Re-enable the key version to restore access:
> ```bash
> gcloud kms keys versions enable 1 \
>   --key="${KEY_NAME}" \
>   --keyring="${KEYRING_NAME}" \
>   --location="${REGION}" \
>   --project="${PROJECT_ID}"
> ```

---

### Exercise 6 — Configure CMEK for a Cloud SQL Instance

Cloud SQL supports CMEK, but only at instance creation time. You cannot enable or change
CMEK on an existing instance — you must create a new instance with the key configured.
This is an important constraint to know for the exam and for planning migrations.

Grant the Cloud SQL service agent permission to use your KMS key:

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
KEYRING_NAME="lab11-keyring"
KEY_NAME="lab11-symmetric-key"

# Get the project number (needed for the Cloud SQL service agent)
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" \
  --format="value(projectNumber)")

echo "Project number: ${PROJECT_NUMBER}"

# Grant the Cloud SQL service agent access to the KMS key
gcloud kms keys add-iam-policy-binding "${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloud-sql.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated IAM policy for key [lab11-symmetric-key].
```

Create the Cloud SQL instance with CMEK. Use `db-f1-micro` (cheapest tier) for this
lab — it is for demonstration only:

```bash
KMS_KEY_ID="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KEYRING_NAME}/cryptoKeys/${KEY_NAME}"

gcloud sql instances create lab11-sql-cmek \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region="${REGION}" \
  --disk-encryption-key="${KMS_KEY_ID}" \
  --no-backup \
  --project="${PROJECT_ID}"
```

Expected output (creation takes 3-5 minutes):
```
Creating Cloud SQL instance for POSTGRES_15...done.
Created [https://sqladmin.googleapis.com/sql/v1beta4/projects/YOUR_PROJECT/instances/lab11-sql-cmek].
NAME            DATABASE_VERSION  LOCATION       TIER          PRIMARY_ADDRESS  PRIVATE_ADDRESS  STATUS
lab11-sql-cmek  POSTGRES_15       us-central1-f  db-f1-micro   XX.XX.XX.XX      -                RUNNABLE
```

Verify the disk encryption key on the instance:

```bash
gcloud sql instances describe lab11-sql-cmek \
  --project="${PROJECT_ID}" \
  --format="yaml(name,diskEncryptionConfiguration,diskEncryptionStatus)"
```

Expected output:
```yaml
diskEncryptionConfiguration:
  kmsKeyName: projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key
diskEncryptionStatus:
  kmsKeyVersionName: projects/YOUR_PROJECT/locations/us-central1/keyRings/lab11-keyring/cryptoKeys/lab11-symmetric-key/cryptoKeyVersions/1
name: lab11-sql-cmek
```

> **Why does this matter?** With CMEK on Cloud SQL, you have the ability to immediately
> make an entire database inaccessible by disabling your KMS key. In regulated industries
> (finance, healthcare), this satisfies requirements for data destruction without having to
> physically delete gigabytes of database files — you simply revoke the key. The underlying
> data still exists on disk but is permanently unreadable. This is sometimes called
> "crypto-shredding."

> Note: Cloud SQL CMEK is not available for `db-f1-micro` instances in all versions and
> regions. If you get an error about CMEK not being supported on this tier, use
> `--tier=db-n1-standard-1` and clean up promptly (it costs more). The CMEK flag behaviour
> and the exam concepts are identical regardless of tier.

---

### Exercise 7 — Create a Cloud Armor Security Policy with IP Rules

Cloud Armor security policies sit in front of your HTTP(S) load balancer backends and
evaluate every inbound request. This exercise creates a policy that blocks a specific IP
range and allows all other traffic.

If you completed Lab 06, you already have a backend service (`lab06-backend-service`)
to attach the policy to. If not, follow the note at the end of this exercise to create
a minimal backend service for testing.

Create the security policy with a default `allow` action (allow all traffic not matched
by a specific rule):

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute security-policies create lab11-security-policy \
  --description="Lab 11 Cloud Armor policy" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/securityPolicies/lab11-security-policy].
```

Verify the default rule (priority 2147483647, allow all — created automatically):

```bash
gcloud compute security-policies describe lab11-security-policy \
  --project="${PROJECT_ID}" \
  --format="yaml(name,rules)"
```

Expected output:
```yaml
name: lab11-security-policy
rules:
- action: allow
  description: default rule
  match:
    config:
      srcIpRanges:
      - '*'
    versionedExpr: SRC_IPS_V1
  preview: false
  priority: 2147483647
```

Add a deny rule for a specific IP range (we use `198.51.100.0/24` — a documentation
range per RFC 5737, safe to use in labs as it is never routable on the internet):

```bash
gcloud compute security-policies rules create 1000 \
  --security-policy=lab11-security-policy \
  --description="Block RFC 5737 documentation range" \
  --src-ip-ranges="198.51.100.0/24" \
  --action="deny(403)" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/securityPolicies/lab11-security-policy/rule?priority=1000].
```

Add an allow rule at lower priority number (higher precedence) for a trusted office IP
range. In a real deployment this would be your corporate egress IP. We use `203.0.113.0/24`
(another RFC 5737 documentation range):

```bash
gcloud compute security-policies rules create 500 \
  --security-policy=lab11-security-policy \
  --description="Allow trusted office network" \
  --src-ip-ranges="203.0.113.0/24" \
  --action="allow" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/securityPolicies/lab11-security-policy/rule?priority=500].
```

Verify all rules are in place:

```bash
gcloud compute security-policies rules list lab11-security-policy \
  --project="${PROJECT_ID}" \
  --format="table(priority,description,action,match.config.srcIpRanges)"
```

Expected output:
```
PRIORITY  DESCRIPTION                            ACTION      SRC_IP_RANGES
500       Allow trusted office network           allow       203.0.113.0/24
1000      Block RFC 5737 documentation range     deny(403)   198.51.100.0/24
2147483647 default rule                          allow       *
```

Rules are evaluated in ascending priority order: 500 first, then 1000, then the default.
A request from `203.0.113.5` matches rule 500 (allow) and never reaches rule 1000.
A request from `198.51.100.50` does not match rule 500, matches rule 1000 (deny 403),
and gets blocked. All other traffic falls through to the default allow.

> **ACE exam tip:** In Cloud Armor, **lower priority number = evaluated first**. This is
> the opposite of VPC firewall rules, where lower priority numbers are also evaluated
> first (consistent), but it can be confused with the word "lower priority" meaning
> "less important" in everyday English. Memorise: priority 1 wins over priority 1000.

---

### Exercise 8 — Attach the Cloud Armor Policy to a Backend Service

A Cloud Armor security policy only takes effect when attached to a backend service on a
global external HTTP(S) load balancer. Creating the policy does nothing by itself.

If you completed Lab 06 and still have the backend service running:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute backend-services update lab06-backend-service \
  --security-policy=lab11-security-policy \
  --global \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/backendServices/lab06-backend-service].
```

Verify the policy is attached:

```bash
gcloud compute backend-services describe lab06-backend-service \
  --global \
  --project="${PROJECT_ID}" \
  --format="yaml(name,securityPolicy)"
```

Expected output:
```yaml
name: lab06-backend-service
securityPolicy: https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/securityPolicies/lab11-security-policy
```

If you do not have the Lab 06 backend service, create a minimal one for demonstration:

```bash
# Create a minimal backend service (no backends — just to demonstrate attachment)
gcloud compute backend-services create lab11-demo-backend \
  --protocol=HTTP \
  --global \
  --project="${PROJECT_ID}"

gcloud compute backend-services update lab11-demo-backend \
  --security-policy=lab11-security-policy \
  --global \
  --project="${PROJECT_ID}"

echo "Policy attached to lab11-demo-backend"
```

> Cloud Armor policies are billed per policy per month ($5), not per backend service
> attachment. You can attach one policy to multiple backend services with no additional
> policy cost (though you pay per million requests evaluated).

> **ACE exam tip:** Cloud Armor can only be attached to **global external HTTP(S) load
> balancer** backend services. It cannot protect internal load balancers, Network LBs,
> or direct-to-VM traffic (use VPC firewall rules for those). The exam tests this
> constraint frequently.

---

### Exercise 9 — Add a Geo-Restriction Rule to Cloud Armor

Geo-restriction lets you block (or exclusively allow) traffic from specific countries.
Cloud Armor uses the `origin.region_code` attribute in CEL (Common Expression Language)
expressions to match the geographic origin of a request.

Region codes follow the ISO 3166-1 alpha-2 standard (two-letter country codes:
`US`, `GB`, `DE`, `CN`, `RU`, etc.).

Add a rule to deny all traffic originating from country code `ZZ` (an unassigned code
used here for demonstration — in production you would use a real ISO country code):

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud compute security-policies rules create 2000 \
  --security-policy=lab11-security-policy \
  --description="Geo-restriction: block ZZ" \
  --expression="origin.region_code == 'ZZ'" \
  --action="deny(403)" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/global/securityPolicies/lab11-security-policy/rule?priority=2000].
```

To restrict access to _only_ traffic from a specific country (an allowlist approach),
the pattern is: allow the target country at a low priority number, then deny everything
else at a higher priority number (before the default):

```bash
# Allow only US traffic (priority 1500)
gcloud compute security-policies rules create 1500 \
  --security-policy=lab11-security-policy \
  --description="Allow only US traffic" \
  --expression="origin.region_code == 'US'" \
  --action="allow" \
  --project="${PROJECT_ID}"

# Change the default rule to deny (priority 2147483647)
# NOTE: You cannot delete the default rule, but you can update it
gcloud compute security-policies rules update 2147483647 \
  --security-policy=lab11-security-policy \
  --description="Default deny — non-US traffic" \
  --action="deny(403)" \
  --src-ip-ranges="*" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/.../securityPolicies/lab11-security-policy/rule?priority=2147483647].
```

Verify the complete policy rule set:

```bash
gcloud compute security-policies rules list lab11-security-policy \
  --project="${PROJECT_ID}" \
  --format="table(priority,description,action)"
```

Expected output:
```
PRIORITY    DESCRIPTION                            ACTION
500         Allow trusted office network           allow
1000        Block RFC 5737 documentation range     deny(403)
1500        Allow only US traffic                  allow
2000        Geo-restriction: block ZZ              deny(403)
2147483647  Default deny — non-US traffic          deny(403)
```

Restore the default rule to `allow` before finishing this exercise to avoid accidentally
blocking traffic if you test the LB:

```bash
gcloud compute security-policies rules update 2147483647 \
  --security-policy=lab11-security-policy \
  --description="default rule" \
  --action="allow" \
  --src-ip-ranges="*" \
  --project="${PROJECT_ID}"
```

> **ACE exam tip:** To implement a geo-allowlist (allow only specific countries, block
> everything else) you need two rules: one that explicitly allows the target country at
> a lower priority number, and a default deny for everything else. Changing the default
> rule to deny is the key step — without it, traffic from non-allowed countries falls
> through to the default allow.

---

## Key Takeaways

- GCP encrypts all data at rest by default using **GMEK** (Google-Managed Encryption
  Keys). This is free and requires no configuration. CMEK and CSEK are additional
  options that shift key custody to the customer.

- **CMEK** (Customer-Managed Encryption Keys) means you create and own the key in Cloud
  KMS. GCP services use your key but you can revoke access by disabling or destroying
  the key version — this is the "crypto-shredding" or "break glass" pattern.

- To use CMEK with a GCP service, you must grant the service's **service agent** the
  `roles/cloudkms.cryptoKeyEncrypterDecrypter` IAM role on the KMS key. Forgetting
  this step is the most common CMEK misconfiguration.

- **Disabling a KMS key version** is reversible — data becomes temporarily inaccessible.
  **Destroying a key version** is irreversible — data encrypted under it is permanently
  unrecoverable. Never destroy a key version unless you intend permanent data loss.

- **Secret Manager** stores secret _values_ (passwords, API keys) with versioning and
  access control. **Cloud KMS** stores encryption _keys_ and performs cryptographic
  operations. They are complementary: Secret Manager secrets are often encrypted by
  a CMEK key.

- CMEK for Cloud SQL must be configured **at instance creation time**. You cannot enable
  or migrate CMEK on an existing Cloud SQL instance.

- **Cloud Armor** is a WAF attached to global external HTTP(S) LB backend services.
  It cannot protect internal LBs, Network LBs, or direct VM traffic. Rules are evaluated
  in ascending priority order (lower number = higher precedence).

- Cloud Armor supports four match types: **IP ranges**, **geo-restriction** (via CEL
  `origin.region_code`), **WAF pre-configured rules** (OWASP ModSecurity CRS), and
  **rate limiting** (THROTTLE or RATE_BASED_BAN).

- **VPC Service Controls** prevent data exfiltration by restricting which GCP APIs can
  exchange data across project and perimeter boundaries, regardless of IAM permissions.
  It is the control for insider-threat and compromised-credential data exfiltration scenarios.

- **OS Login** replaces metadata-based SSH key management with IAM role-based access.
  Enable it with `enable-oslogin=true` metadata to ensure SSH access is controlled
  by Google account status and revoked automatically when accounts are disabled.

- **Binary Authorization** enforces that only signed, attested container images can be
  deployed to GKE or Cloud Run. It is the supply-chain security control for container
  workloads.

- **Shielded VMs** protect against firmware-level and boot-level attacks using Secure
  Boot, vTPM, and Integrity Monitoring. Use them when compliance requires hardware-level
  trust anchoring or protection against rootkits/bootkits.

---

## Cleanup

Run all of these commands to destroy every resource created in this lab. Cloud Armor
policies are billed at $5/month — destroy the policy first.

```bash
# Check what exists before cleanup
../status.sh 11
```

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
KEYRING_NAME="lab11-keyring"
KEY_NAME="lab11-symmetric-key"

echo "=== Detaching Cloud Armor policy from backend services ==="
# Detach from lab06 backend service if it exists
gcloud compute backend-services update lab06-backend-service \
  --no-security-policy \
  --global \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null || echo "lab06-backend-service not found — skipping."

# Detach from lab11 demo backend if it exists
gcloud compute backend-services update lab11-demo-backend \
  --no-security-policy \
  --global \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null || echo "lab11-demo-backend not found — skipping."

echo "=== Deleting Cloud Armor security policy ==="
gcloud compute security-policies delete lab11-security-policy \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting lab11 demo backend service (if created) ==="
gcloud compute backend-services delete lab11-demo-backend \
  --global \
  --quiet \
  --project="${PROJECT_ID}" 2>/dev/null || echo "lab11-demo-backend not found — skipping."

echo "=== Deleting Cloud SQL instance ==="
gcloud sql instances delete lab11-sql-cmek \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud Storage CMEK bucket ==="
gcloud storage rm -r "gs://lab11-cmek-bucket-${PROJECT_ID}" \
  --project="${PROJECT_ID}"

echo "=== Destroying KMS key versions ==="
# Disable then schedule destroy on key versions
gcloud kms keys versions destroy 1 \
  --key="${KEY_NAME}" \
  --keyring="${KEYRING_NAME}" \
  --location="${REGION}" \
  --project="${PROJECT_ID}" 2>/dev/null || echo "Key version 1 may already be destroyed."

echo "=== Deleting Secret Manager secrets ==="
gcloud secrets delete lab11-db-password \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting service account ==="
gcloud iam service-accounts delete \
  "lab11-app-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Cleanup complete ==="
```

> **Note on KMS key rings:** Key rings cannot be deleted in GCP. The key ring
> `lab11-keyring` will remain in your project permanently (it incurs no ongoing cost
> once all key versions are destroyed). The key itself remains as a shell but its
> cryptographic material is destroyed. This is by design — Cloud Audit Logs reference
> key ring paths, and GCP preserves the name to prevent log confusion if a key ring
> is recreated with the same name.

> **Note on KMS key versions:** `gcloud kms keys versions destroy` schedules the
> version for destruction (it moves to `DESTROY_SCHEDULED` state for 24 hours before
> being permanently destroyed). You cannot immediately destroy a key version. This grace
> period protects against accidental key destruction.

Verify all significant resources are gone:

```bash
echo "--- Cloud Armor policies ---"
gcloud compute security-policies list \
  --filter="name:lab11" \
  --project="${PROJECT_ID}"

echo "--- Cloud SQL instances ---"
gcloud sql instances list \
  --filter="name:lab11" \
  --project="${PROJECT_ID}"

echo "--- Secret Manager secrets ---"
gcloud secrets list \
  --filter="name:lab11" \
  --project="${PROJECT_ID}"

echo "--- GCS buckets ---"
gcloud storage buckets list \
  --filter="name:lab11" \
  --project="${PROJECT_ID}"

echo "--- Service accounts ---"
gcloud iam service-accounts list \
  --filter="email:lab11" \
  --project="${PROJECT_ID}"

../status.sh 11
```

All sections should be empty. KMS key versions enter `DESTROY_SCHEDULED` state and
disappear after the 24-hour grace period — this is normal.
