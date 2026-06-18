# Lab 03 — Cloud Storage (cost warning: < $0.01 for this lab, destroy promptly)

> **Cost**: Standard storage costs $0.020/GB/month. The small objects used in this lab cost less than $0.01 total. Run the cleanup section when finished.

---

## Objectives

After completing this lab, you will be able to:

- Create GCS buckets with different storage classes and location types
- Perform object operations: upload, download, copy, move, and delete using both `gsutil` and `gcloud storage`
- Enable object versioning, overwrite objects, inspect generation numbers, and restore previous versions
- Write lifecycle management rules to automate storage class transitions and object deletion
- Switch buckets between uniform bucket-level access and fine-grained ACL modes
- Make a bucket publicly readable and understand the security implications
- Generate signed URLs so external users can access private objects without a GCP account
- Sync a local directory to GCS using `rsync`
- Configure CORS on a bucket for web application access
- Explain the ACE exam tradeoffs between storage classes, location types, and access control models

---

## Concepts

### Storage Classes

GCS offers four storage classes. The right choice depends on how frequently you access data and how long you retain it. Every storage class has the same durability (99.999999999% — eleven nines) and the same API, so you can change classes at any time without moving buckets.

| Storage Class | Min Storage Duration | Retrieval Cost | Monthly Cost (per GB) | Use Case |
|---|---|---|---|---|
| Standard | None | None | $0.020 | Frequently accessed data, web assets, active workloads |
| Nearline | 30 days | $0.010/GB | $0.010 | Backups accessed < once per month |
| Coldline | 90 days | $0.020/GB | $0.004 | Disaster recovery, accessed < once per quarter |
| Archive | 365 days | $0.050/GB | $0.0012 | Long-term archival, compliance, accessed < once per year |

The minimum storage duration means: even if you delete an object after 1 day, you are billed for the minimum. For Archive, deleting a 1 GB object after 2 days still costs 365 days of storage.

**AWS equivalent**: Standard → S3 Standard, Nearline → S3 Standard-IA, Coldline → S3 Glacier Instant Retrieval, Archive → S3 Glacier Deep Archive.

> **ACE exam tip**: The exam tests whether you know *which* storage class to recommend given an access pattern. The keyword "accessed less than once a month" maps to Nearline. "Compliance archival" or "once a year" maps to Archive. Never put frequently-accessed data in Coldline or Archive — the retrieval fees will exceed what you saved on storage.

### Location Types

| Location Type | Example | Redundancy | Monthly Cost | Best For |
|---|---|---|---|---|
| Multi-region | `us`, `eu`, `asia` | Geo-redundant across regions | Highest | Global web assets, highest availability |
| Dual-region | `nam4` (Iowa + S. Carolina) | Synchronous replication, two regions | Mid | Data residency + HA within a continent |
| Region | `us-central1` | Single region, multiple zones | Lowest | Data locality, co-location with Compute Engine |

Multi-region and dual-region buckets qualify for a 99.99% availability SLA. Regional buckets are 99.9%. For data that lives in the same region as your Compute Engine VMs, use a regional bucket to avoid inter-region egress charges.

> **ACE exam tip**: Dual-region buckets support **turbo replication** (15-minute RPO SLA), which is useful for regulated industries. This is a distinct offering from standard dual-region replication.

### Bucket Naming Rules

Bucket names are globally unique across all GCP projects and all customers. Rules:
- 3–63 characters, lowercase letters, numbers, hyphens, underscores, and dots
- Must start and end with a letter or number
- Cannot look like an IP address (e.g., `192.168.0.1`)
- Cannot contain `google` or close misspellings
- DNS-compatible: if you plan to use a custom domain with CNAME to `c.storage.googleapis.com`, the bucket name must exactly match the domain

A common naming convention: `${PROJECT_ID}-${purpose}-${env}`, for example `my-project-123-assets-prod`. Including the project ID guarantees uniqueness.

### Uniform vs Fine-Grained Access

GCS has two access control models, and you must choose one per bucket:

**Uniform bucket-level access (recommended)**
- All access is controlled by Cloud IAM on the bucket and project
- Per-object ACLs are disabled and ignored
- Simpler audit trail — one place to check permissions
- Google recommends this for all new buckets
- Once enabled for 90 days, it cannot be disabled

**Fine-grained access (legacy)**
- IAM policies apply at bucket level
- Per-object ACLs can grant access to specific objects for specific users
- More complex, harder to audit
- Required only for legacy use cases or public-read-per-object scenarios

> **ACE exam tip**: The exam favors uniform bucket-level access. If a scenario says "simplify access management" or "enforce consistent permissions across all objects," uniform is the answer.

### Object Versioning

When versioning is enabled, overwriting or deleting an object creates a **noncurrent** version rather than destroying data. Each version is identified by a **generation number** — a 64-bit integer assigned at creation time.

```
objects/
  photo.jpg  (live, generation: 1686000000123456)
  photo.jpg  (noncurrent, generation: 1685900000000000)  ← previous version
```

Versioning costs money: every version counts toward storage billing. Combine versioning with lifecycle rules to automatically delete noncurrent versions after N days, or keep only the last N versions.

**AWS equivalent**: S3 object versioning works identically in concept.

### Lifecycle Management Rules

Lifecycle rules automate storage management. Each rule has:
- **Conditions**: what triggers the rule (object age, storage class, number of newer versions, creation date, etc.)
- **Action**: what to do (`Delete`, `SetStorageClass`, `AbortIncompleteMultipartUpload`)

Rules are written in JSON and applied at the bucket level:

```json
{
  "rule": [
    {
      "action": { "type": "SetStorageClass", "storageClass": "NEARLINE" },
      "condition": { "age": 30, "matchesStorageClass": ["STANDARD"] }
    },
    {
      "action": { "type": "Delete" },
      "condition": { "age": 90 }
    },
    {
      "action": { "type": "Delete" },
      "condition": { "numNewerVersions": 3, "isLive": false }
    }
  ]
}
```

GCS evaluates rules once per day, so changes may take up to 24 hours to take effect. Rules are evaluated in no guaranteed order — if two rules match the same object, both actions are applied.

### gsutil vs gcloud storage

GCS has two CLI tools:

| Feature | `gsutil` | `gcloud storage` |
|---|---|---|
| Status | Legacy (Python, boto) | Current (Go, recommended) |
| Performance | Single-threaded by default | Parallel by default, thread-safe |
| Syntax | `gsutil cp`, `gsutil ls` | `gcloud storage cp`, `gcloud storage ls` |
| Scripting | Widely documented | Preferred for new scripts |
| Availability | Pre-installed on Cloud Shell | gcloud SDK >= 400.0.0 |

Both tools work today. Google is not deprecating `gsutil` immediately, but new features go into `gcloud storage`. This lab shows both so you recognize either on the exam.

### Signed URLs

A signed URL is a time-limited URL that grants access to a specific GCS object without requiring a Google account. The URL encodes:
- The object path
- An expiration time
- A cryptographic signature from a service account

Use cases: sharing a download link with a customer, pre-signed upload URLs for browser-based uploads, temporary access from a non-GCP system.

Signed URLs are generated with `gcloud storage sign-url` (or `gsutil signurl`) using a service account key file or impersonation.

> **ACE exam tip**: Signed URLs are the correct answer for "grant temporary access to a private object without giving the user a GCP account." They are not the same as making a bucket public.

### Object Holds and Retention Policies

**Object holds** prevent deletion or overwrite of individual objects:
- **Temporary hold**: manually placed, manually released. Use for objects under legal review.
- **Event-based hold**: placed at upload, released when a business event occurs (e.g., contract end).

**Bucket retention policies** enforce a minimum retention period on all objects. No object can be deleted before the policy's retention period expires. Retention policies can be **locked** (making them irrevocable), which satisfies WORM (Write Once, Read Many) compliance requirements like SEC 17a-4.

**AWS equivalent**: S3 Object Lock in Compliance mode.

---

## Setup

These steps are prerequisites specific to Lab 03. Lab 01 must already be complete (gcloud SDK installed, authenticated, project configured).

```bash
cd /path/to/gcp-ace-labs/lab-03-cloud-storage

# Confirm your active project
PROJECT_ID=$(gcloud config get-value project)
echo "Working in project: $PROJECT_ID"

# Confirm billing is enabled (required for GCS)
gcloud beta billing projects describe $PROJECT_ID --format="value(billingEnabled)"
# Expected output: True

# Confirm the Storage API is enabled (it usually is by default)
gcloud services list --enabled --filter="name:storage.googleapis.com"
# Expected output: NAME: storage.googleapis.com

# If not enabled:
gcloud services enable storage.googleapis.com

# Working directory for local files (already exists in the repo, contents are gitignored)
LAB_DIR="$(pwd)/work"
```

---

## Exercises

### Exercise 1 — Create Buckets with Different Storage Classes

We will create three buckets to explore how storage class and location affect configuration. Because bucket names are globally unique, we embed `$PROJECT_ID` to avoid collisions.

```bash
PROJECT_ID=$(gcloud config get-value project)

# Standard regional bucket — the default for active workloads co-located with VMs
gcloud storage buckets create gs://${PROJECT_ID}-standard-lab \
  --location=us-central1 \
  --default-storage-class=STANDARD \
  --uniform-bucket-level-access

# Nearline multi-region bucket — cost-effective for infrequent access at global scale
gcloud storage buckets create gs://${PROJECT_ID}-nearline-lab \
  --location=us \
  --default-storage-class=NEARLINE \
  --uniform-bucket-level-access

# Coldline regional bucket — disaster recovery archive
gcloud storage buckets create gs://${PROJECT_ID}-coldline-lab \
  --location=us-central1 \
  --default-storage-class=COLDLINE \
  --uniform-bucket-level-access
```

**Expected output (per bucket):**
```
Creating gs://my-project-123-standard-lab/...
```

Verify all three buckets exist:

```bash
gcloud storage buckets list --filter="name~${PROJECT_ID}-.*-lab" \
  --format="table(name, location, storageClass, iamConfiguration.uniformBucketLevelAccess.enabled)"
```

**Expected output:**
```
NAME                                    LOCATION     STORAGE_CLASS  UNIFORM_BUCKET_LEVEL_ACCESS_ENABLED
my-project-123-coldline-lab             US-CENTRAL1  COLDLINE       True
my-project-123-nearline-lab             US           NEARLINE       True
my-project-123-standard-lab             US-CENTRAL1  STANDARD       True
```

Notice the multi-region `us` location vs the regional `us-central1`. The multi-region identifier is always lowercase and short (`us`, `eu`, `asia`).

> **ACE exam tip**: Storage class is a property of individual objects, not just the bucket. The bucket's *default* storage class applies to newly uploaded objects. You can upload an individual object into any storage class regardless of the bucket default by specifying `--storage-class` at upload time.

### Exercise 2 — Upload Objects, List, Download, Copy, and Delete

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET=gs://${PROJECT_ID}-standard-lab
```

Create the test files used throughout this exercise:

```bash
./create-test-files.sh
```

Upload files using `gcloud storage`:

```bash
# Upload a single file
gcloud storage cp $LAB_DIR/hello.txt $BUCKET/

# Upload multiple files
gcloud storage cp $LAB_DIR/config.json $LAB_DIR/binary-data.txt $LAB_DIR/temp.txt $BUCKET/

# Upload to a "folder" (GCS has no real directories — the slash is part of the object name)
gcloud storage cp $LAB_DIR/hello.txt $BUCKET/subfolder/hello-copy.txt
```

**Expected output:**
```
Copying file:///Users/you/gcs-lab/hello.txt to gs://my-project-123-standard-lab/hello.txt
  Completed files 1/1 | 18.0B/18.0B
```

List objects:

```bash
# List all objects in bucket
gcloud storage ls $BUCKET

# List with details (size, creation time, storage class)
gcloud storage ls -l $BUCKET

# List recursively (shows subfolder contents)
gcloud storage ls -r $BUCKET
```

**Expected output for `gcloud storage ls -l`:**
```
        18  2024-01-15T10:23:45Z  gs://my-project-123-standard-lab/binary-data.txt
       136  2024-01-15T10:23:46Z  gs://my-project-123-standard-lab/config.json
        18  2024-01-15T10:23:47Z  gs://my-project-123-standard-lab/hello.txt
        25  2024-01-15T10:23:48Z  gs://my-project-123-standard-lab/temp.txt
TOTAL: 4 objects, 197 bytes (197 B)
```

Download a file:

```bash
# Download to a local path
gcloud storage cp $BUCKET/hello.txt $LAB_DIR/hello-downloaded.txt
cat $LAB_DIR/hello-downloaded.txt
```

**Expected output:**
```
Hello from Lab 03
```

Copy between buckets and delete:

```bash
# Copy an object between buckets (server-side, no local download)
gcloud storage cp $BUCKET/config.json gs://${PROJECT_ID}-nearline-lab/config.json

# Delete a single object
gcloud storage rm $BUCKET/temp.txt

# Verify deletion
gcloud storage ls $BUCKET
# temp.txt should no longer appear
```

Compare the same operations using the legacy `gsutil` syntax — both produce identical results:

```bash
# gsutil equivalents (you will see these in older documentation and exam questions)
gsutil ls $BUCKET
gsutil cp $BUCKET/hello.txt $LAB_DIR/hello-gsutil.txt
gsutil rm $BUCKET/subfolder/hello-copy.txt
```

> **ACE exam tip**: The exam may show either `gsutil` or `gcloud storage` syntax in answers. Know both. `gcloud storage` is the current recommended tool, but `gsutil` is still valid.

### Exercise 3 — Enable Versioning, Overwrite Objects, and Restore a Previous Version

Without versioning, overwriting an object permanently destroys the previous content. Enable versioning first, then observe how generation numbers track history.

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET=gs://${PROJECT_ID}-standard-lab

# Enable versioning
gcloud storage buckets update $BUCKET --versioning

# Verify versioning is enabled
gcloud storage buckets describe $BUCKET --format="value(versioning_enabled)"
# Expected output: True
```

Create an object, overwrite it twice, and inspect the version history:

```bash
# Create version 1
echo "Version 1 — original content" > $LAB_DIR/versioned.txt
gcloud storage cp $LAB_DIR/versioned.txt $BUCKET/versioned.txt

# Overwrite with version 2
echo "Version 2 — updated content" > $LAB_DIR/versioned.txt
gcloud storage cp $LAB_DIR/versioned.txt $BUCKET/versioned.txt

# Overwrite with version 3 (the current live version)
echo "Version 3 — latest content" > $LAB_DIR/versioned.txt
gcloud storage cp $LAB_DIR/versioned.txt $BUCKET/versioned.txt
```

List all versions, including noncurrent ones:

```bash
gcloud storage ls -a $BUCKET/versioned.txt
```

**Expected output:**
```
gs://my-project-123-standard-lab/versioned.txt#1686000000000001
gs://my-project-123-standard-lab/versioned.txt#1686000000000002
gs://my-project-123-standard-lab/versioned.txt#1686000000000003
```

The number after `#` is the generation number. The highest generation is the live version.

Download a specific old version to restore it:

```bash
# Capture generation numbers
VERSIONS=$(gcloud storage ls -a $BUCKET/versioned.txt)
echo "$VERSIONS"

# Get the generation number of the oldest version (first line)
GEN_V1=$(gcloud storage ls -a $BUCKET/versioned.txt | head -1 | grep -oE '#[0-9]+' | tr -d '#')
echo "Generation of version 1: $GEN_V1"

# Download version 1 to confirm its content
gcloud storage cp "${BUCKET}/versioned.txt#${GEN_V1}" $LAB_DIR/restored-v1.txt
cat $LAB_DIR/restored-v1.txt
```

**Expected output:**
```
Version 1 — original content
```

To "restore" version 1 as the new live version, copy it back without a generation specifier (this creates a new generation that is a copy of v1):

```bash
gcloud storage cp "${BUCKET}/versioned.txt#${GEN_V1}" $BUCKET/versioned.txt

# Confirm the live version now shows v1 content
gcloud storage cp $BUCKET/versioned.txt - 2>/dev/null
```

**Expected output:**
```
Version 1 — original content
```

Delete all noncurrent versions to avoid ongoing storage costs:

```bash
# This deletes noncurrent versions only — the live object is preserved
gcloud storage rm -a $BUCKET/versioned.txt

# Now recreate a clean live version
echo "Clean current version" > $LAB_DIR/versioned.txt
gcloud storage cp $LAB_DIR/versioned.txt $BUCKET/versioned.txt
```

> **ACE exam tip**: Versioning and lifecycle rules are tested together. The condition `numNewerVersions: 3` means "delete this noncurrent version when there are 3 or more newer versions of the same object." This is how you cap version history without manually deleting generations.

### Exercise 4 — Create Lifecycle Rules

Lifecycle rules automate the progression of objects through storage classes and eventually to deletion. This is how you implement a cost-efficient data tiering strategy without manual intervention.

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET=gs://${PROJECT_ID}-standard-lab

This policy implements: Standard → Nearline at 30 days → Coldline at 60 days → Delete at 90 days, and purges noncurrent versions when 3 or more newer versions exist. The policy is in `lifecycle.json` in this lab's directory.

Apply the lifecycle configuration:

```bash
gcloud storage buckets update $BUCKET \
  --lifecycle-file=lifecycle.json
```

**Expected output:**
```
Updating gs://my-project-123-standard-lab/...
```

Verify the lifecycle was applied:

```bash
gcloud storage buckets describe $BUCKET --format="json" | jq .lifecycle_config
```

**Expected output (abbreviated):**
```json
{
  "rule": [
    {
      "action": {
        "storageClass": "NEARLINE",
        "type": "SetStorageClass"
      },
      "condition": {
        "age": 30,
        "matchesStorageClass": [
          "STANDARD"
        ]
      }
    },
    ...
  ]
}
```

Intentionally break it — provide malformed JSON to see what happens:

```bash
gcloud storage buckets update $BUCKET --lifecycle-file=bad-lifecycle.json
```

**Expected output (error — exact message may vary by SDK version):**
```
ERROR: Task failed: GcsApiError('')
  Completed 0
```

An empty condition would delete all objects immediately — GCS rejects this to prevent accidents. This is a good example of a guard rail in the API.

> **ACE exam tip**: Lifecycle rules are not retroactive — they evaluate once per day going forward. The `age` condition is measured from the object's creation date, not the date you added the rule. An object created 45 days ago will match `age: 30` on the next daily evaluation after you add the rule.

### Exercise 5 — Configure Uniform Bucket-Level Access

Uniform bucket-level access is already enabled on the buckets we created (we passed `--uniform-bucket-level-access` at creation). This exercise demonstrates what happens when it is *not* enabled, and how to enforce it.

```bash
PROJECT_ID=$(gcloud config get-value project)

# Create a bucket WITHOUT uniform access (fine-grained, legacy mode)
gcloud storage buckets create gs://${PROJECT_ID}-finegrained-lab \
  --location=us-central1 \
  --default-storage-class=STANDARD
# Note: no --uniform-bucket-level-access flag
```

Verify the access mode:

```bash
gcloud storage buckets describe gs://${PROJECT_ID}-finegrained-lab \
  --format="value(iamConfiguration.uniformBucketLevelAccess.enabled)"
```

**Expected output:**
```
False
```

In fine-grained mode, you can set per-object ACLs. This is harder to audit and can lead to unintended public exposure. Upgrade it to uniform:

```bash
gcloud storage buckets update gs://${PROJECT_ID}-finegrained-lab \
  --uniform-bucket-level-access
```

**Expected output:**
```
Updating gs://my-project-123-finegrained-lab/...
```

Verify the change:

```bash
gcloud storage buckets describe gs://${PROJECT_ID}-finegrained-lab \
  --format="value(iamConfiguration.uniformBucketLevelAccess.enabled)"
```

**Expected output:**
```
True
```

Now try to reverse it — after 90 days you cannot, but even before 90 days this is a deliberate operation:

```bash
# This will succeed if within 90 days of enabling — but do not do this in production
gcloud storage buckets update gs://${PROJECT_ID}-finegrained-lab \
  --no-uniform-bucket-level-access
```

**Expected output:**
```
Updating gs://my-project-123-finegrained-lab/...
```

Re-enable it for the rest of the lab:

```bash
gcloud storage buckets update gs://${PROJECT_ID}-finegrained-lab \
  --uniform-bucket-level-access
```

> **ACE exam tip**: After uniform bucket-level access has been enabled for 90 consecutive days, it is automatically locked and cannot be disabled. The exam tests this 90-day lock behavior.

### Exercise 6 — Set Up a Public Bucket and Lock It Down

Making a bucket publicly readable is common for hosting static assets. This exercise shows how to do it correctly, and — critically — how to verify that public access is actually restricted when you want it to be.

```bash
PROJECT_ID=$(gcloud config get-value project)
PUBLIC_BUCKET=gs://${PROJECT_ID}-public-lab

# Create the bucket
gcloud storage buckets create $PUBLIC_BUCKET \
  --location=us-central1 \
  --default-storage-class=STANDARD \
  --uniform-bucket-level-access

# Upload a test file
echo "<h1>Hello from GCS public bucket</h1>" > $LAB_DIR/index.html
gcloud storage cp $LAB_DIR/index.html $PUBLIC_BUCKET/index.html
```

Grant public read access by binding `allUsers` to the `roles/storage.objectViewer` role:

```bash
gcloud storage buckets add-iam-policy-binding $PUBLIC_BUCKET \
  --member=allUsers \
  --role=roles/storage.objectViewer
```

**Expected output:**
```
Updated IAM policy for bucket [my-project-123-public-lab].
bindings:
- members:
  - allUsers
  role: roles/storage.objectViewer
...
```

Test public access via curl (no authentication required):

```bash
curl -s "https://storage.googleapis.com/${PROJECT_ID}-public-lab/index.html"
```

**Expected output:**
```
<h1>Hello from GCS public bucket</h1>
```

Now intentionally test what happens with a non-existent object to understand the error response:

```bash
curl -s "https://storage.googleapis.com/${PROJECT_ID}-public-lab/does-not-exist.html"
```

**Expected output:**
```xml
<?xml version='1.0' encoding='UTF-8'?>
<Error>
  <Code>NoSuchKey</Code>
  <Message>The specified key does not exist.</Message>
  ...
</Error>
```

This XML error confirms the bucket is reachable but the object does not exist — different from an access denied error.

Lock down the bucket — remove public access:

```bash
gcloud storage buckets remove-iam-policy-binding $PUBLIC_BUCKET \
  --member=allUsers \
  --role=roles/storage.objectViewer
```

Verify the lock down by attempting public access again:

```bash
curl -s "https://storage.googleapis.com/${PROJECT_ID}-public-lab/index.html"
```

**Expected output:**
```xml
<Error>
  <Code>AccessDenied</Code>
  <Message>Access denied.</Message>
  ...
</Error>
```

> **ACE exam tip**: Enabling `allUsers` as `objectViewer` is a common misconfiguration that exposes sensitive data. GCP's **Public Access Prevention** setting at the organization or bucket level overrides any IAM policy that would grant `allUsers` or `allAuthenticatedUsers` access. In a real environment, enable Public Access Prevention at the organization policy level (`constraints/storage.publicAccessPrevention`).

### Exercise 7 — Generate a Signed URL for Temporary Access

Signed URLs allow sharing a specific private object with an external user for a limited time, without giving them a GCP account or permanent permissions.

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET=gs://${PROJECT_ID}-standard-lab

# Upload a private file to the standard bucket
echo "This is a confidential report — Lab 03" > $LAB_DIR/report.txt
gcloud storage cp $LAB_DIR/report.txt $BUCKET/private/report.txt

# Confirm it's NOT publicly accessible
curl -s "https://storage.googleapis.com/${PROJECT_ID}-standard-lab/private/report.txt" | head -5
```

**Expected output:**
```xml
<Error><Code>AccessDenied</Code>...
```

Generate a signed URL valid for 1 hour using the authenticated user's credentials (requires `iam.serviceAccounts.signBlob` permission on your own identity — works in Cloud Shell):

```bash
# Generate a signed URL that expires in 1 hour (3600 seconds)
gcloud storage sign-url $BUCKET/private/report.txt \
  --duration=1h \
  --private-key-file="" \
  --region=us-central1
```

If you receive a permission error in Cloud Shell, use impersonation via a service account (the service account needs `roles/storage.objectViewer` on the bucket):

```bash
# Alternative: sign URL using a service account (replace with your service account)
SA_EMAIL="$(gcloud iam service-accounts list --format='value(email)' --limit=1)"
echo "Using service account: $SA_EMAIL"

gcloud storage sign-url $BUCKET/private/report.txt \
  --duration=1h \
  --impersonate-service-account=$SA_EMAIL \
  --region=us-central1
```

**Expected output (URL format):**
```
https://storage.googleapis.com/my-project-123-standard-lab/private/report.txt?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Credential=...&X-Goog-Date=...&X-Goog-Expires=3600&X-Goog-SignedHeaders=host&X-Goog-Signature=...
```

Test access using the signed URL:

```bash
SIGNED_URL=$(gcloud storage sign-url $BUCKET/private/report.txt \
  --duration=1h \
  --impersonate-service-account=$SA_EMAIL \
  --region=us-central1 \
  --format="value(signedUrl)" 2>/dev/null)

curl -s "$SIGNED_URL"
```

**Expected output:**
```
This is a confidential report — Lab 03
```

Now test what happens after expiration — sign a URL that expires in 5 seconds:

```bash
SHORT_URL=$(gcloud storage sign-url $BUCKET/private/report.txt \
  --duration=5s \
  --impersonate-service-account=$SA_EMAIL \
  --region=us-central1 \
  --format="value(signedUrl)" 2>/dev/null)

# Wait 10 seconds, then try
sleep 10
curl -s "$SHORT_URL" | grep -o '<Code>.*</Code>'
```

**Expected output:**
```
<Code>ExpiredToken</Code>
```

> **ACE exam tip**: Signed URLs are generated client-side — they do not require a GCS API call to create, and revoking them before expiration requires rotating the service account key used to sign them (not a real-time revoke). Plan expiration windows carefully.

### Exercise 8 — Sync a Local Directory to GCS

`rsync` is efficient for keeping a local directory and a GCS bucket in sync. Unlike repeated `cp` commands, `rsync` only transfers files that have changed (by comparing checksums or modification times). This is essential for build artifact pipelines, static site deployments, and backup jobs.

```bash
PROJECT_ID=$(gcloud config get-value project)
BUCKET=gs://${PROJECT_ID}-standard-lab

# Create a local directory structure to sync
mkdir -p $LAB_DIR/website/{css,js,images}
echo "<html><body>Home</body></html>" > $LAB_DIR/website/index.html
echo "<html><body>About</body></html>" > $LAB_DIR/website/about.html
echo "body { font-family: sans-serif; }" > $LAB_DIR/website/css/style.css
echo "console.log('hello');" > $LAB_DIR/website/js/app.js
echo "placeholder image data" > $LAB_DIR/website/images/logo.txt
```

Initial sync using `gcloud storage rsync`:

```bash
gcloud storage rsync $LAB_DIR/website $BUCKET/website/ --recursive
```

**Expected output:**
```
Building synchronization state...
Starting synchronization...
Copying file:///Users/you/gcs-lab/website/about.html to gs://my-project-123-standard-lab/website/about.html
Copying file:///Users/you/gcs-lab/website/css/style.css to gs://my-project-123-standard-lab/website/css/style.css
Copying file:///Users/you/gcs-lab/website/images/logo.txt to gs://my-project-123-standard-lab/website/images/logo.txt
Copying file:///Users/you/gcs-lab/website/index.html to gs://my-project-123-standard-lab/website/index.html
Copying file:///Users/you/gcs-lab/website/js/app.js to gs://my-project-123-standard-lab/website/js/app.js
```

Now modify one file and add a new file, then sync again — only changed files are uploaded:

```bash
echo "<html><body>Home v2</body></html>" > $LAB_DIR/website/index.html
echo "<html><body>Contact</body></html>" > $LAB_DIR/website/contact.html

gcloud storage rsync $LAB_DIR/website $BUCKET/website/ --recursive
```

**Expected output:**
```
Building synchronization state...
Starting synchronization...
Copying file:///Users/you/gcs-lab/website/contact.html to gs://my-project-123-standard-lab/website/contact.html
Copying file:///Users/you/gcs-lab/website/index.html to gs://my-project-123-standard-lab/website/index.html
```

Only the 2 changed/new files were uploaded — not all 5.

Use the `--delete-unmatched-destination-objects` flag to make GCS exactly mirror the local directory (files deleted locally are also deleted in GCS):

```bash
rm $LAB_DIR/website/about.html

gcloud storage rsync $LAB_DIR/website $BUCKET/website/ \
  --recursive \
  --delete-unmatched-destination-objects
```

**Expected output:**
```
Building synchronization state...
Starting synchronization...
Removing gs://my-project-123-standard-lab/website/about.html...
```

Use `--dry-run` to preview what rsync would do without making changes — useful before running a destructive sync:

```bash
echo "test" > $LAB_DIR/website/new-file.html
gcloud storage rsync $LAB_DIR/website $BUCKET/website/ \
  --recursive \
  --delete-unmatched-destination-objects \
  --dry-run
```

**Expected output:**
```
[DRY RUN] Would copy file:///Users/you/gcs-lab/website/new-file.html to gs://...
```

The equivalent `gsutil` command is `gsutil rsync -r -d source destination`. The `-d` flag in `gsutil` corresponds to `--delete-unmatched-destination-objects` in `gcloud storage`.

> **ACE exam tip**: `--delete-unmatched-destination-objects` (or `gsutil rsync -d`) is a destructive flag. Reversing source and destination accidentally (`gsutil rsync -d gs://bucket local/`) will delete bucket contents that do not exist locally. Always use `--dry-run` first in production.

### Exercise 9 — Configure CORS for Web Application Access

Cross-Origin Resource Sharing (CORS) is a browser security feature. When a web app at `https://example.com` tries to fetch a resource from `https://storage.googleapis.com`, the browser first sends a preflight OPTIONS request to GCS to check if the cross-origin request is allowed. Without a CORS configuration on the bucket, the browser blocks the request even if the object is publicly readable.

```bash
PROJECT_ID=$(gcloud config get-value project)
PUBLIC_BUCKET=gs://${PROJECT_ID}-public-lab

# Re-enable public access on the public bucket for this exercise
gcloud storage buckets add-iam-policy-binding $PUBLIC_BUCKET \
  --member=allUsers \
  --role=roles/storage.objectViewer

# Verify current CORS config (should be empty)
gcloud storage buckets describe $PUBLIC_BUCKET --format="json(cors)"
```

**Expected output:**
```json
{}
```

Create a CORS configuration. This example allows GET and HEAD requests from any origin (wildcard), which is appropriate for public CDN-style assets:

```bash
cat > $LAB_DIR/cors.json << 'EOF'
[
  {
    "origin": ["https://example.com", "https://app.example.com"],
    "method": ["GET", "HEAD", "OPTIONS"],
    "responseHeader": ["Content-Type", "Access-Control-Allow-Origin"],
    "maxAgeSeconds": 3600
  }
]
EOF
```

Apply the CORS configuration:

```bash
gcloud storage buckets update $PUBLIC_BUCKET \
  --cors-file=$LAB_DIR/cors.json
```

**Expected output:**
```
Updating gs://my-project-123-public-lab/...
```

Verify the CORS configuration was applied:

```bash
gcloud storage buckets describe $PUBLIC_BUCKET --format="json(cors)"
```

**Expected output:**
```json
{
  "cors": [
    {
      "maxAgeSeconds": 3600,
      "method": [
        "GET",
        "HEAD",
        "OPTIONS"
      ],
      "origin": [
        "https://example.com",
        "https://app.example.com"
      ],
      "responseHeader": [
        "Content-Type",
        "Access-Control-Allow-Origin"
      ]
    }
  ]
}
```

Simulate what a browser preflight request looks like and inspect the CORS response headers:

```bash
curl -s -I \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: GET" \
  -X OPTIONS \
  "https://storage.googleapis.com/${PROJECT_ID}-public-lab/index.html"
```

**Expected output (relevant headers):**
```
HTTP/2 200
access-control-allow-origin: https://example.com
access-control-allow-methods: GET,HEAD,OPTIONS
access-control-max-age: 3600
```

Test a request from a disallowed origin:

```bash
curl -s -I \
  -H "Origin: https://attacker.com" \
  -H "Access-Control-Request-Method: GET" \
  -X OPTIONS \
  "https://storage.googleapis.com/${PROJECT_ID}-public-lab/index.html"
```

**Expected output:**
```
HTTP/2 200
# Note: no access-control-allow-origin header returned
# The browser would block the actual request
```

GCS returns 200 for the OPTIONS preflight regardless, but omits the `access-control-allow-origin` header for disallowed origins. The browser interprets the missing header as a CORS rejection and blocks the follow-up GET.

Remove CORS configuration (to reset to default — no cross-origin access):

```bash
gcloud storage buckets update $PUBLIC_BUCKET --clear-cors
gcloud storage buckets describe $PUBLIC_BUCKET --format="json(cors)"
# Expected output: {}
```

> **ACE exam tip**: CORS is a browser enforcement mechanism only — `curl` and server-to-server requests ignore CORS headers entirely. CORS does not add security to server-side access. It only controls whether browsers permit cross-origin JavaScript requests.

---

## Key Takeaways

- **Storage class selection is a cost tradeoff**: Standard for frequent access (no retrieval fee), Nearline/Coldline/Archive for infrequent access (lower storage cost, retrieval fee, minimum storage duration). Choosing the wrong class for the access pattern can cost more, not less.

- **Multi-region costs more but provides higher availability** (99.99% SLA vs 99.9% for regional). Use regional buckets for data co-located with Compute Engine to avoid egress charges.

- **Bucket names are globally unique** and DNS-compatible. Embedding `$PROJECT_ID` in the name is a reliable strategy for avoiding collisions.

- **Uniform bucket-level access is the recommended access model**. It disables per-object ACLs and centralizes all access control in Cloud IAM. After 90 days it locks and cannot be reversed — which is intentional for compliance.

- **Object versioning creates noncurrent versions on overwrite or delete**. Each version has a unique generation number. Versions are billed like regular storage — always pair versioning with lifecycle rules to cap version history.

- **Lifecycle rules use JSON conditions** (`age`, `storageClass`, `numNewerVersions`, `isLive`) and run once per day. They automate cost optimization by transitioning objects through storage classes and eventually deleting them.

- **`gcloud storage` is the current recommended CLI**. `gsutil` is legacy but still valid. The exam uses both — know the equivalent commands: `gsutil cp` = `gcloud storage cp`, `gsutil rsync` = `gcloud storage rsync`, etc.

- **Signed URLs provide time-limited, unauthenticated access** to specific private objects. They are signed by a service account and expire automatically. Revoking early requires rotating the signing key.

- **`rsync --delete-unmatched-destination-objects` is destructive** — it deletes GCS objects not present locally. Always use `--dry-run` before running against production buckets.

- **CORS is browser-only enforcement**. It controls whether browsers permit JavaScript on one origin to fetch resources from GCS. It has no effect on server-to-server or `curl` access.

- **Retention policies and object holds** support WORM compliance. A *locked* retention policy is irrevocable and satisfies regulations like SEC 17a-4. Event-based holds are released by business events; temporary holds are released manually.

- **Public Access Prevention** at the organization policy level (`constraints/storage.publicAccessPrevention`) overrides any IAM binding that would grant `allUsers` or `allAuthenticatedUsers` — a critical defense against accidental data exposure.

---

## Cleanup

Run these commands to delete all resources created in this lab. GCS charges by the day, so destroy resources promptly.

```bash
PROJECT_ID=$(gcloud config get-value project)

# Remove public access before deleting (avoids any residual exposure)
gcloud storage buckets remove-iam-policy-binding gs://${PROJECT_ID}-public-lab \
  --member=allUsers \
  --role=roles/storage.objectViewer 2>/dev/null || true

# Delete all objects and buckets
# The -r flag deletes all objects recursively before removing the bucket
gcloud storage rm -r gs://${PROJECT_ID}-standard-lab
gcloud storage rm -r gs://${PROJECT_ID}-nearline-lab
gcloud storage rm -r gs://${PROJECT_ID}-coldline-lab
gcloud storage rm -r gs://${PROJECT_ID}-public-lab
gcloud storage rm -r gs://${PROJECT_ID}-finegrained-lab

# Verify all lab buckets are gone
gcloud storage buckets list --filter="name~${PROJECT_ID}-.*-lab"
# Expected output: (empty — no buckets listed)

# Clean up local files
rm -f $LAB_DIR/*
```

**Expected output per bucket deletion:**
```
Removing objects:
  Removing gs://my-project-123-standard-lab/...
Removing bucket gs://my-project-123-standard-lab/...
```

If a bucket has a locked retention policy preventing deletion, you must wait for the retention period to expire — there is no override, by design. For this lab, no retention policies were locked, so all buckets delete immediately.