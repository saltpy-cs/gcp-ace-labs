# Lab 09 — Managed Databases: SQL, NoSQL, and Caching

> **Cost warning:** This lab creates several managed database resources.
> - Cloud SQL `db-g1-small` (PostgreSQL): ~$0.03/hr — smallest supported tier for PostgreSQL 15, fine for the lab.
> - Memorystore Redis 1 GB Basic: ~$0.049/hr.
> - Cloud Spanner 1-node: ~$0.90/hr — **use only briefly then destroy immediately**.
>
> Estimated total if completed in 2 hours and cleaned up promptly: **~$0.15**.
> If you are cost-conscious, skip Exercise 6 (Spanner) — it is covered conceptually in
> the Concepts section and on the ACE exam you need to understand it, not operate it.

---

## Objectives

After completing this lab you will be able to:

- Create a Cloud SQL PostgreSQL instance using gcloud
- Connect to Cloud SQL securely using the Cloud SQL Auth Proxy
- Create databases and tables, and run SQL queries from the command line
- Create a manual backup of a Cloud SQL instance and verify it
- Create a Cloud SQL read replica and explain when to use one vs HA
- Enable high availability on a Cloud SQL instance and understand what changes
- Create a Memorystore Redis instance and connect to it from a Compute Engine VM
- Perform SET and GET operations on Redis from a GCE instance
- Select the right GCP database product for a given workload scenario
- Explain the differences between Cloud SQL, Cloud Spanner, Firestore, Bigtable, BigQuery, and Memorystore

---

## Concepts

### The Database Decision Framework

Choosing the right database is one of the most-tested topics on the GCP ACE exam. The
exam will describe a workload and ask which database to use. The decision hinges on four
axes: **data model** (relational vs document vs wide-column), **scale** (vertical vs
horizontal), **consistency requirements**, and **use case pattern** (OLTP, OLAP, cache,
time series).

| Database | Data Model | Scale | Consistency | Typical Use Case |
|---|---|---|---|---|
| **Cloud SQL** | Relational (MySQL, PostgreSQL, SQL Server) | Vertical + read replicas | Strong (single region) | Lift-and-shift OLTP apps, CMS, ERP, existing relational workloads |
| **Cloud Spanner** | Relational (SQL) | Horizontal, unlimited | Strong (global) | Global financial transactions, global gaming leaderboards, inventory |
| **Firestore** | Document (JSON) | Horizontal | Strong | Mobile/web backends, realtime sync, user profiles, product catalogs |
| **Bigtable** | Wide-column (HBase-compatible) | Horizontal, petabytes | Eventual | Time series, IoT telemetry, ad tech, > 1 TB flat/wide data |
| **BigQuery** | Columnar / analytical | Serverless, petabytes | Eventual (analytical) | Data warehouse, ad-hoc analytics, historical reporting |
| **Memorystore** | Key-value (Redis or Valkey) | Vertical (instance size) | Strong (cache) | Session store, leaderboards, rate limiting, pub/sub fan-out |

The most important distinguishing questions:

1. **Is it relational (SQL)?** → Cloud SQL or Cloud Spanner
2. **Does it need to be globally consistent at massive scale?** → Spanner (not Cloud SQL)
3. **Is it document-shaped data for a mobile/web app?** → Firestore
4. **Is it very wide rows, time series, or > 1 TB?** → Bigtable
5. **Is it analytics / reporting on historical data?** → BigQuery
6. **Is it a cache or session store?** → Memorystore

> **ACE exam tip:** The exam frequently tries to trick you into choosing BigQuery for
> anything big. BigQuery is for analytics (OLAP), not transactions (OLTP). If the scenario
> mentions "users", "orders", "real-time", or "transactions", it is almost never BigQuery.

### Cloud SQL

Cloud SQL is Google's fully managed relational database service. It supports **MySQL**,
**PostgreSQL**, and **SQL Server**. Managed means GCP handles OS patching, database
version upgrades, backup scheduling, and failover — you just create an instance, connect,
and run queries.

The machine types are named in two families:
- `db-g1-small`, `db-g1-small` — shared-core, cheap, development/test only
- `db-n1-standard-N`, `db-n1-highmem-N` — dedicated vCPUs for production

Cloud SQL is a regional resource. You pick a primary zone, and if you enable HA, GCP also
maintains a standby in a different zone within the same region.

On AWS, the equivalent is **Amazon RDS** (with Multi-AZ deployments for HA and read
replicas for read scaling).

```bash
# List available database versions
gcloud sql tiers list --project="${PROJECT_ID}"
```

### Cloud SQL High Availability

Without HA, your Cloud SQL instance is a single VM in a single zone. If that zone goes
down, your database is unreachable until the zone recovers.

With HA enabled, Cloud SQL maintains a **standby instance** in a different zone in the
same region. The primary and standby share a single regional persistent disk and use
**synchronous replication** — every write is committed to both before acknowledging
success. This means there is zero data loss on failover (RPO = 0).

```
HA topology:
  us-central1-a: PRIMARY instance  (read + write)
  us-central1-b: STANDBY instance  (no connections, hot standby)
                       |
               Regional persistent disk
               (shared storage, synchronous write)
```

When the primary zone fails:
1. GCP detects the failure within ~60 seconds.
2. The standby is promoted to primary.
3. Your connection string (via the Cloud SQL instance IP or Auth Proxy) automatically
   routes to the new primary.
4. Downtime is typically 60–120 seconds during the automated failover.

**Important:** HA roughly doubles the cost because you are paying for two instances. The
exam will test whether you understand this trade-off.

### Cloud SQL Read Replicas

A read replica is a separate instance that replicates from the primary using **asynchronous
replication**. It accepts read-only connections. Applications can offload SELECT-heavy
workloads (reporting, analytics, search) to a replica to reduce load on the primary.

| | High Availability | Read Replica |
|---|---|---|
| Purpose | Survive zone/instance failure | Scale read throughput |
| Replication | Synchronous (zero data loss) | Asynchronous (small lag) |
| Accepts connections | No (hot standby only) | Yes (read-only) |
| Can be promoted | Yes (automatic on failover) | Yes (manual, breaks replication) |
| Cross-region | No | Yes (cross-region replicas exist) |
| Effect on primary | Minor write overhead | Minimal |

A **cross-region read replica** is placed in a different region entirely. This serves two
purposes: disaster recovery (if the entire primary region fails, promote the replica) and
lower-latency reads for users in that region.

> **ACE exam tip:** HA and read replicas are often confused. HA is for availability (uptime
> when something breaks). Read replicas are for performance (more read throughput). You can
> and often should have both. A common exam scenario: "You need to survive a zone failure
> AND handle heavy read traffic" — the answer is HA enabled PLUS read replicas.

### Cloud SQL Auth Proxy

The Cloud SQL Auth Proxy is a local binary that creates an encrypted tunnel between your
application and Cloud SQL. It uses IAM to authenticate — no passwords in connection
strings, no SSL certificates to manage, no IP allowlists.

```
Application → localhost:5432 → Cloud SQL Auth Proxy → (TLS tunnel) → Cloud SQL instance
```

Without the Auth Proxy, you would need to either:
- Add the client's public IP to the Cloud SQL instance's authorised networks (risky, hard
  to manage), or
- Configure SSL client certificates manually.

The Auth Proxy handles both: it authenticates using the service account or user credential
on the VM where it runs, and all traffic is encrypted in transit.

```bash
# Download the proxy
curl -o cloud-sql-proxy \
  https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.11.0/cloud-sql-proxy.linux.amd64
chmod +x cloud-sql-proxy

# Start the proxy (it listens on localhost:5432 and proxies to your instance)
./cloud-sql-proxy --port 5432 PROJECT_ID:REGION:INSTANCE_NAME &

# Connect with psql as if connecting to localhost
psql "host=127.0.0.1 port=5432 user=postgres dbname=postgres"
```

> **ACE exam tip:** The Auth Proxy is the recommended way to connect to Cloud SQL from
> Compute Engine, GKE, and Cloud Run. If the exam asks how to connect securely without
> managing certificates or IP allowlists, the answer is Cloud SQL Auth Proxy.

### Cloud Spanner

Cloud Spanner is Google's globally-distributed, strongly-consistent relational database.
It is the only database in the world that provides **ACID transactions at global scale**
with a **99.999% SLA** (five nines) for multi-region configurations.

How does it achieve global consistency without sacrificing performance? Through
**TrueTime** — Google's globally synchronized clock built on GPS receivers and atomic
clocks in every Google data center. TrueTime allows Spanner to assign globally ordered
timestamps to transactions, making global consistency mathematically achievable.

```
CAP theorem context:
  Cloud SQL:     CP (consistent + partition tolerant, limited availability during failover)
  Cloud Spanner: CA at global scale (Spanner famously challenged the CAP theorem)
  Bigtable:      AP (available + partition tolerant, eventual consistency)
```

Spanner is expensive: ~$0.90/hr for a single node, ~$0.65/hr for processing + storage
costs. You use it when the cost of data inconsistency is higher than the cost of Spanner
— think: financial ledgers, inventory, global gaming currency.

Spanner supports two query interfaces:
- **Spanner API (GoogleSQL dialect)** — native Spanner SQL
- **PostgreSQL interface** — for easier migration from Cloud SQL PostgreSQL

On AWS, the closest equivalent is **Amazon Aurora Global Database**, but Spanner's
consistency guarantees are stronger.

### Firestore

Firestore is Google's document database. Data is stored as **documents** (JSON-like
objects) organized into **collections**. It supports real-time listeners — client SDKs
can subscribe to a query and receive updates as data changes, without polling.

Firestore has two modes:

| Mode | Description | When to Use |
|---|---|---|
| **Native mode** | Full Firestore features: real-time listeners, offline support, newer data model | All new applications |
| **Datastore mode** | Backwards-compatible with Cloud Datastore | Migrating existing Datastore applications |

You cannot switch between modes after creation. Native mode is the default for new
projects and supports everything Datastore mode does, plus real-time sync.

On AWS, the equivalent is **Amazon DynamoDB** (for key-value/document patterns) or
**AWS AppSync** (for real-time sync). Firestore's real-time capabilities are more native
and easier to use than DynamoDB Streams.

### Bigtable

Cloud Bigtable is a wide-column NoSQL database based on Google's internal Bigtable paper
(which inspired Apache HBase and Apache Cassandra). It is designed for:
- Very high throughput (millions of reads/writes per second)
- Very large datasets (> 1 TB, often petabytes)
- Flat, wide rows with many columns
- Time-series patterns (each row is an entity, columns are time-bucketed values)

**Row key design is critical.** Bigtable distributes data across nodes based on row key
ranges (lexicographic order). If your row keys are sequential (e.g. timestamps or
sequential IDs), all writes hit the same node — a "hotspot" that bottlenecks performance.
Good row keys distribute writes evenly across nodes:

```
Bad row key:  2024-01-01T00:00:00Z#sensor_001   (all Jan 1st writes hit same node)
Good row key: sensor_001#2024-01-01T00:00:00Z   (writes spread across sensors)
Better:       HASH(sensor_001)#2024-01-01T...   (hash prefix distributes evenly)
```

Bigtable is **not** for relational data, joins, or small datasets. The minimum useful
dataset size is roughly 1 TB — below that, Cloud SQL or Firestore is more appropriate.

On AWS, the closest equivalent is **Amazon DynamoDB** (for scale) or self-managed
**HBase on EMR**.

### Memorystore

Memorystore is Google's managed in-memory cache. It supports **Redis** and **Valkey**
(the Redis fork). It runs inside your VPC — there is no public endpoint. Clients must be
in the same VPC (or a peered VPC) to connect.

Common use cases:
- **Session storage** — store user session data with TTL, avoid hitting the database per
  request
- **Database query caching** — cache expensive query results for seconds or minutes
- **Leaderboards** — Redis Sorted Sets are perfect for real-time ranked leaderboards
- **Rate limiting** — Redis INCR + EXPIRE implements per-user rate counters atomically
- **Pub/Sub fan-out** — Redis Pub/Sub for lightweight event distribution within a region

Memorystore is a **vertical** scale resource — you pick an instance size (1 GB to 300 GB
for Redis). It does not auto-scale. For very large caches, consider Redis Cluster mode
(available in Memorystore Standard tier).

On AWS, the equivalent is **Amazon ElastiCache for Redis**.

### Point-in-Time Recovery (PITR)

Cloud SQL supports **point-in-time recovery** — you can restore a database to any
second within the last 7 days (configurable, up to 7 days). PITR works by continuously
archiving transaction logs in addition to daily automated backups.

```
Timeline:
  Day 1 02:00 UTC: automated backup (full)
  Day 1 14:37:22 UTC: accidental DELETE with no WHERE clause
  Day 1 14:37:21 UTC: you can restore to THIS exact second

PITR restore target: 2024-01-01T14:37:21Z
```

PITR requires **binary logging** to be enabled (MySQL) or is always on (PostgreSQL). It
adds a small performance overhead (write-ahead log archiving) but is considered essential
for production databases.

---

## Setup

### APIs

**Note:** All APIs required for this lab are enabled by `./enable-apis.sh` in the course root. If you skipped that step, run it before continuing.

### Environment Variables

Set these at the start of every terminal session for this lab:

```bash
export PROJECT_ID=$(gcloud config get-value project)
export REGION="us-central1"
export ZONE="us-central1-a"
echo "Project: ${PROJECT_ID}, Region: ${REGION}, Zone: ${ZONE}"
```

### gcloud Default Region and Zone

Configure gcloud defaults so you do not need to pass `--region` and `--zone` to every
command. This carries over from labs 01–08, but set it explicitly here for clarity:

```bash
gcloud config set compute/region "${REGION}"
gcloud config set compute/zone "${ZONE}"
```

---

## Exercises

### Exercise 1 — Create a Cloud SQL PostgreSQL Instance

Cloud SQL instances take 3–5 minutes to provision. The flags below are calibrated for
minimum cost: `db-g1-small` is the smallest available tier, shared-core, and sufficient
for this lab.

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud sql instances create lab09-postgres \
  --database-version=POSTGRES_15 \
  --tier=db-g1-small \
  --region="${REGION}" \
  --storage-type=SSD \
  --storage-size=10GB \
  --no-storage-auto-increase \
  --backup-start-time=02:00 \
  --project="${PROJECT_ID}"
```

`--backup-start-time=02:00` schedules automated daily backups at 2 AM UTC.
`--region` places the instance in `us-central1`; GCP selects the zone automatically.

This command will take 3–5 minutes. The expected final output:

```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/instances/lab09-postgres].
NAME            DATABASE_VERSION  LOCATION       TIER          PRIMARY_ADDRESS  PRIVATE_ADDRESS  STATUS
lab09-postgres  POSTGRES_15       us-central1-a  db-g1-small   34.xxx.xxx.xxx   -                RUNNABLE
```

Verify the instance state:

```bash
gcloud sql instances describe lab09-postgres \
  --project="${PROJECT_ID}" \
  --format="table(name,databaseVersion,settings.tier,state,ipAddresses[0].ipAddress)"
```

Expected output:
```
NAME            DATABASE_VERSION  TIER         STATE     IP_ADDRESS
lab09-postgres  POSTGRES_15       db-g1-small  RUNNABLE  34.xxx.xxx.xxx
```

Set the `postgres` superuser password. You will need this to connect via psql:

```bash
gcloud sql users set-password postgres \
  --instance=lab09-postgres \
  --password='Lab09SecurePass!' \
  --project="${PROJECT_ID}"
```

Expected output:
```
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/instances/lab09-postgres/users/postgres].
```

> **Why `db-g1-small`?** The `db-g1-small` tier uses a shared vCPU and 1.7 GB RAM. It is
> the smallest tier supported for PostgreSQL 15 and is not suitable for production workloads,
> but is identical in behaviour to larger tiers for learning purposes. The ACE exam does not
> test tier selection deeply — it tests HA, read replicas, Auth Proxy, and database product choice.

---

### Exercise 2 — Connect via Cloud SQL Auth Proxy

You need a Compute Engine VM to act as the client. The Auth Proxy runs on the VM, opening
a local tunnel to the Cloud SQL instance. This VM simulates an application server.

#### Step 2a — Create a Client VM

```bash
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-central1-a"

gcloud compute instances create lab09-db-client \
  --machine-type=e2-micro \
  --image-family=debian-12 \
  --image-project=debian-cloud \
  --zone="${ZONE}" \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --metadata-from-file=startup-script=db-client-startup.sh \
  --project="${PROJECT_ID}"
```

The `--scopes=https://www.googleapis.com/auth/cloud-platform` flag grants the VM's
default service account access to all Cloud APIs, including the Cloud SQL Admin API that
the Auth Proxy uses. In production you would use a dedicated service account with the
`roles/cloudsql.client` role.

Expected output:
```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/zones/us-central1-a/instances/lab09-db-client].
NAME             ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
lab09-db-client  us-central1-a  e2-micro                   10.128.0.X   34.xxx.xxx.xx  RUNNING
```

#### Step 2b — Get the Cloud SQL Instance Connection Name

```bash
PROJECT_ID=$(gcloud config get-value project)

CONN_NAME=$(gcloud sql instances describe lab09-postgres \
  --project="${PROJECT_ID}" \
  --format="value(connectionName)")

echo "Connection name: ${CONN_NAME}"
```

Expected output:
```
Connection name: YOUR_PROJECT:us-central1:lab09-postgres
```

This `PROJECT:REGION:INSTANCE_NAME` string is what the Auth Proxy uses to identify which
instance to connect to. It encodes the project, region, and instance name in one string.

#### Step 2c — Wait for the startup script, then verify

The startup script (`db-client-startup.sh`) runs automatically on first boot and installs
`postgresql-client` and the Cloud SQL Auth Proxy. Wait for SSH to become available, then poll inside the VM until the startup script completes:

```bash
until gcloud compute ssh lab09-db-client \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}" \
  --command="until test -f /tmp/startup-complete; do echo 'Waiting for startup script...'; sleep 5; done; echo 'Startup complete.'" \
  2>/dev/null; do
  echo "Waiting for SSH..."
  sleep 10
done
```

Then SSH in and verify:

```bash
gcloud compute ssh lab09-db-client \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"
```

Inside the VM:

```bash
cloud-sql-proxy --version
psql --version
```

Expected output:
```
cloud-sql-proxy version 2.11.0+linux.amd64
psql (PostgreSQL) 15.x (Debian 15.x-0+deb12u1)
```

#### Step 2d — Start the Auth Proxy and Connect

Replace `YOUR_PROJECT` with your actual project ID (you can get it from `gcloud config
get-value project` on the VM):

```bash
# Inside the VM:
PROJECT_ID=$(gcloud config get-value project)

# Start the Auth Proxy in the background, listening on localhost:5432
cloud-sql-proxy --port 5432 "${PROJECT_ID}:us-central1:lab09-postgres" &

# Wait until the proxy is listening on port 5432
until ss -ltn src :5432 | grep -q LISTEN; do sleep 1; done
```

Expected output:
```
2024/01/01 00:00:00 Authorizing with Application Default Credentials
2024/01/01 00:00:00 Listening on 127.0.0.1:5432
```

Now connect with psql through the proxy:

```bash
# Inside the VM:
PGPASSWORD='Lab09SecurePass!' psql "host=127.0.0.1 port=5432 user=postgres dbname=postgres"
```

Expected output:
```
psql (15.x (Debian 15.x-0+deb12u1), server 15.x)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_128_GCM_SHA256, bits: 128, compression: off)
Type "help" for help.

postgres=#
```

You are now connected to Cloud SQL PostgreSQL through the Auth Proxy. The connection
travels: `psql → localhost:5432 → Auth Proxy → TLS tunnel → Cloud SQL`.

> **Why the Auth Proxy and not direct connection?** Direct connection would require you
> to add the VM's public IP to the Cloud SQL `authorizedNetworks` list, and you would
> need to manage SSL certificates. The Auth Proxy uses the VM's service account identity —
> no IP allowlisting, no cert management. If the service account is revoked, access is
> immediately cut off.

Type `\q` to exit psql, then `exit` to return to your local shell.

---

### Exercise 3 — Create a Database, Table, and Run Queries

Exit the psql session if still connected:

```sql
\q
```

Copy the setup script to the VM, then SSH in:

```bash
PROJECT_ID=$(gcloud config get-value project)
ZONE="us-central1-a"

gcloud compute scp setup.sql lab09-db-client:~ \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"

gcloud compute ssh lab09-db-client \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"
```

Inside the VM, start the Auth Proxy if not already running, then run the setup script:

```bash
# Inside the VM:
PROJECT_ID=$(gcloud config get-value project)
ss -ltn src :5432 | grep -q LISTEN || cloud-sql-proxy --port 5432 "${PROJECT_ID}:us-central1:lab09-postgres" &
until ss -ltn src :5432 | grep -q LISTEN; do sleep 1; done
PGPASSWORD='Lab09SecurePass!' psql "host=127.0.0.1 port=5432 user=postgres dbname=postgres" -f setup.sql
```

Expected output:
```
CREATE DATABASE
You are now connected to database "lab09_store" as user "postgres".
CREATE TABLE
INSERT 0 4
```

Now connect interactively to run queries:

```bash
PGPASSWORD='Lab09SecurePass!' psql "host=127.0.0.1 port=5432 user=postgres dbname=lab09_store"
```

```sql
SELECT id, name, price, stock FROM products ORDER BY price DESC;
```

Expected output:
```
 id |         name          | price | stock
----+-----------------------+-------+-------
  2 | GCP ACE Study Guide   | 49.99 |   200
  1 | Cloud SQL Handbook    | 29.99 |   150
  3 | Spanner T-Shirt       | 19.99 |    50
  4 | Firestore Mug         | 12.99 |     0
(4 rows)
```

Run a more interesting query — find out-of-stock products:

```sql
SELECT name, price
FROM products
WHERE stock = 0;
```

Expected output:
```
     name      | price
---------------+-------
 Firestore Mug | 12.99
(1 row)
```

Check the table schema:

```sql
\d products
```

Expected output:
```
                              Table "public.products"
   Column   |            Type             | Collation | Nullable |      Default
------------+-----------------------------+-----------+----------+--------------------
 id         | integer                     |           | not null | nextval('products_id_seq'::regclass)
 name       | character varying(100)      |           | not null |
 price      | numeric(10,2)               |           | not null |
 stock      | integer                     |           | not null | 0
 created_at | timestamp without time zone |           |          | now()
```

Exit psql: `\q`, then `exit` to return to your local shell.

---

### Exercise 4 — Create a Backup and Verify It

Cloud SQL supports two types of backups:
- **Automated backups** — run daily on a schedule, retained for 7 days by default
- **On-demand backups** — triggered manually, retained until you delete them

Create an on-demand backup of the instance:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud sql backups create \
  --instance=lab09-postgres \
  --description="Lab 09 manual backup before HA config" \
  --project="${PROJECT_ID}"
```

Expected output:
```
Backing up Cloud SQL instance...done.
Backed up [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/instances/lab09-postgres].
```

List all backups for the instance to confirm it was created:

```bash
gcloud sql backups list \
  --instance=lab09-postgres \
  --project="${PROJECT_ID}"
```

Expected output:
```
ID          WINDOW_START_TIME              ERROR  STATUS
1234567890  2024-01-01 00:00:00+00:00             SUCCESSFUL
```

Describe the backup to see its size and type:

```bash
BACKUP_ID=$(gcloud sql backups list \
  --instance=lab09-postgres \
  --project="${PROJECT_ID}" \
  --format="value(id)" | head -1)

echo "Backup ID: ${BACKUP_ID}"

gcloud sql backups describe "${BACKUP_ID}" \
  --instance=lab09-postgres \
  --project="${PROJECT_ID}" \
  --format="yaml(id,status,startTime,endTime,sizeBytes,type)"
```

Expected output:
```yaml
endTime: '2024-01-01T00:05:00.000Z'
id: '1234567890'
sizeBytes: '8388608'
startTime: '2024-01-01T00:00:00.000Z'
status: SUCCESSFUL
type: ON_DEMAND
```

Now verify you understand PITR. Check the backup retention settings:

```bash
gcloud sql instances describe lab09-postgres \
  --project="${PROJECT_ID}" \
  --format="yaml(settings.backupConfiguration)"
```

Expected output:
```yaml
settings:
  backupConfiguration:
    backupRetentionSettings:
      retainedBackups: 7
      retentionUnit: COUNT
    enabled: true
    pointInTimeRecoveryEnabled: true
    replicationLogArchivingEnabled: true
    startTime: 02:00
    transactionLogRetentionDays: 7
```

The `pointInTimeRecoveryEnabled: true` and `transactionLogRetentionDays: 7` confirm you
can restore to any point in the last 7 days. To restore to a specific time you would run:

```bash
# This is an example — do NOT run it during the lab (it replaces your instance)
# gcloud sql instances clone lab09-postgres lab09-postgres-restored \
#   --point-in-time="2024-01-01T14:37:21Z" \
#   --project="${PROJECT_ID}"
```

> **ACE exam tip:** PITR in Cloud SQL uses a clone operation — it creates a new instance
> at the target point in time. You cannot restore in-place on the running instance. The
> exam may ask about the RPO (recovery point objective) for Cloud SQL with PITR — it is
> seconds (the granularity of transaction log archiving).

---

### Exercise 5 — Create a Read Replica

A read replica is a separate Cloud SQL instance that replicates asynchronously from the
primary. Applications can connect to it for read-only queries, offloading SELECT load
from the primary.

Create a read replica in the same region (same-region replica for read scaling):

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud sql instances create lab09-postgres-replica \
  --master-instance-name=lab09-postgres \
  --replica-type=READ \
  --region="${REGION}" \
  --tier=db-g1-small \
  --project="${PROJECT_ID}"
```

This takes 2–3 minutes. Expected output:

```
Created [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/instances/lab09-postgres-replica].
NAME                     DATABASE_VERSION  LOCATION       TIER          PRIMARY_ADDRESS  STATUS
lab09-postgres-replica   POSTGRES_15       us-central1-b  db-g1-small   35.xxx.xxx.xxx   RUNNABLE
```

List all instances to see the primary-replica relationship:

```bash
gcloud sql instances list \
  --project="${PROJECT_ID}" \
  --format="table(name,databaseVersion,region,settings.tier,state,masterInstanceName)"
```

Expected output:
```
NAME                     DATABASE_VERSION  REGION       TIER         STATE     MASTER_INSTANCE_NAME
lab09-postgres           POSTGRES_15       us-central1  db-g1-small  RUNNABLE
lab09-postgres-replica   POSTGRES_15       us-central1  db-g1-small  RUNNABLE  YOUR_PROJECT:lab09-postgres
```

Verify the replica has the data you wrote in Exercise 3. Connect via the Auth Proxy
pointing to the replica's connection name. SSH into the client VM:

```bash
gcloud compute ssh lab09-db-client \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"
```

Inside the VM:

```bash
# Inside the VM:
PROJECT_ID=$(gcloud config get-value project)

# Start a SECOND proxy instance on a different local port (5433) for the replica
cloud-sql-proxy --port 5433 "${PROJECT_ID}:us-central1:lab09-postgres-replica" &
until ss -ltn src :5433 | grep -q LISTEN; do sleep 1; done

# Connect to the replica
PGPASSWORD='Lab09SecurePass!' psql "host=127.0.0.1 port=5433 user=postgres dbname=lab09_store"
```

Run a read query:

```sql
SELECT name, price FROM products WHERE stock > 0;
```

Expected output (same data as the primary, replicated):
```
         name          | price
-----------------------+-------
 Cloud SQL Handbook    | 29.99
 GCP ACE Study Guide   | 49.99
 Spanner T-Shirt       | 19.99
(3 rows)
```

Now try a write on the replica to confirm it is truly read-only:

```sql
-- This SHOULD fail — replicas are read-only
INSERT INTO products (name, price, stock) VALUES ('Test', 9.99, 1);
```

Expected output:
```
ERROR:  cannot execute INSERT in a read-only transaction
```

The replica correctly rejects writes. This error confirms the replica is working and
enforcing read-only mode.

Exit psql: `\q`, then `exit`.

> **ACE exam tip:** When you promote a read replica (for disaster recovery), it becomes a
> standalone primary with no further replication from the original. The promotion is
> irreversible — you cannot re-attach it as a replica afterward. This is the key
> distinction from HA failover, which is automatic and preserves the replication topology.

---

### Exercise 6 — Enable High Availability

> **Cost note:** Enabling HA on `db-g1-small` roughly doubles the hourly cost to ~$0.06/hr.
> Since this lab uses the cheapest tier the impact is minimal. Run the cleanup at the end
> to avoid ongoing charges.

High availability adds a synchronous standby instance in a different zone. The primary
and standby share a regional persistent disk.

Enable HA on the existing instance:

```bash
PROJECT_ID=$(gcloud config get-value project)

gcloud sql instances patch lab09-postgres \
  --availability-type=REGIONAL \
  --project="${PROJECT_ID}"
```

Expected output:
```
The following message will be used for the patch API method.
...
Do you want to continue (Y/n)? Y

Patching Cloud SQL instance...done.
Updated [https://www.googleapis.com/compute/v1/projects/YOUR_PROJECT/instances/lab09-postgres].
```

This takes 3–5 minutes while GCP provisions the standby and switches the storage to
regional. Verify the HA configuration:

```bash
gcloud sql instances describe lab09-postgres \
  --project="${PROJECT_ID}" \
  --format="yaml(name,settings.availabilityType,failoverReplica)"
```

Expected output:
```yaml
failoverReplica:
  available: true
name: lab09-postgres
settings:
  availabilityType: REGIONAL
```

The `failoverReplica.available: true` confirms the standby is healthy and ready to take
over. Now examine what changed — list all instances again:

```bash
gcloud sql instances list \
  --project="${PROJECT_ID}" \
  --format="table(name,databaseVersion,region,settings.tier,state,gceZone,secondaryGceZone)"
```

Expected output:
```
NAME                     DATABASE_VERSION  REGION       TIER         STATE     GCE_ZONE       SECONDARY_GCE_ZONE
lab09-postgres           POSTGRES_15       us-central1  db-g1-small  RUNNABLE  us-central1-a  us-central1-b
lab09-postgres-replica   POSTGRES_15       us-central1  db-g1-small  RUNNABLE  us-central1-b
```

The `SECONDARY_GCE_ZONE` column on `lab09-postgres` shows `us-central1-b` — the standby
is in a different zone from the primary (`us-central1-a`). If `us-central1-a` suffers an
outage, GCP will automatically promote the standby in `us-central1-b`.

You do not need to change your application's connection string. The Cloud SQL Auth Proxy
and the instance's public IP both automatically route to whichever zone holds the current
primary.

**Intentional failure: understand what HA does NOT protect against.**

HA protects you from zone failures. It does not protect you from:
- Accidental `DROP TABLE` — the deletion replicates synchronously to the standby
- Application bugs that corrupt data — same reason
- Regional failures — for those, use cross-region read replicas

```
HA topology after enabling:
  us-central1-a: PRIMARY  (reads + writes)   ← your connection target
  us-central1-b: STANDBY  (no connections, hot standby on shared regional disk)

What HA protects:      zone hardware failure, zone network failure, instance crash
What HA does NOT:      data errors, accidental deletions, regional outages
```

> **ACE exam tip:** The ACE exam frequently presents the HA question as a cost-availability
> trade-off. The key facts: HA uses `REGIONAL` availability type (vs `ZONAL` for no-HA).
> HA standby runs in a different zone within the same region. You cannot specify which
> zone the standby goes to — GCP chooses automatically. HA roughly doubles cost.

---

### Exercise 7 — Create a Memorystore Redis Instance and Connect from GCE

Memorystore runs inside your VPC — there is no public IP. Your GCE VM (`lab09-db-client`)
is in the default VPC, so it can reach Memorystore over the internal network.

#### Step 7a — Create the Memorystore Instance

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

gcloud redis instances create lab09-redis \
  --size=1 \
  --region="${REGION}" \
  --tier=basic \
  --redis-version=redis_7_0 \
  --project="${PROJECT_ID}"
```

The `--tier=basic` flag creates a single-node instance with no replication (cheaper, no
HA). `--size=1` is 1 GB of memory.

This takes 3–5 minutes. Expected output:

```
Create request issued for: [lab09-redis]
Waiting for operation [projects/YOUR_PROJECT/locations/us-central1/operations/operation-xxx] to complete...done.
Created instance [lab09-redis].
```

Get the Redis instance's private IP address — this is how your application connects to it:

```bash
REDIS_HOST=$(gcloud redis instances describe lab09-redis \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(host)")

REDIS_PORT=$(gcloud redis instances describe lab09-redis \
  --region="${REGION}" \
  --project="${PROJECT_ID}" \
  --format="value(port)")

echo "Redis host: ${REDIS_HOST}:${REDIS_PORT}"
```

Expected output:
```
Redis host: 10.xxx.xxx.xxx:6379
```

The IP is in the `10.x.x.x` range — a private VPC IP, not reachable from the public
internet. This is intentional: Memorystore has no public endpoint.

#### Step 7b — Connect from the GCE VM and Run Redis Commands

Copy the Redis demo script to the VM, then SSH in:

```bash
gcloud compute scp redis-demo.txt lab09-db-client:~ \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"

gcloud compute ssh lab09-db-client \
  --zone="${ZONE}" \
  --project="${PROJECT_ID}"
```

The startup script already installed `redis-tools`. Inside the VM, connect to Redis (replace with the actual IP from above):

```bash
# Inside the VM:
# Get the Redis IP from the instance metadata instead of hardcoding
REDIS_HOST=$(gcloud redis instances describe lab09-redis \
  --region=us-central1 \
  --format="value(host)")

redis-cli -h "${REDIS_HOST}" -p 6379 ping
```

Expected output:
```
PONG
```

A `PONG` response confirms connectivity. Now set and get some keys:

```bash
# Inside the VM:
redis-cli -h "${REDIS_HOST}" -p 6379 < ~/redis-demo.txt
```

Expected output:

```
OK
"{'user_id': 1001, 'name': 'Jane', 'role': 'admin'}"
OK
(integer) 3599
OK
(integer) 1
(integer) 2
(integer) 3
"3"
1) "player:bob"
2) "22500"
3) "player:carol"
4) "18000"
5) "player:alice"
6) "15000"
```

Walk through what you just did:

- `SET` / `GET` — the fundamental key-value operation. Here storing serialized session JSON.
- `EX 3600` — the key expires automatically in 3600 seconds. Sessions that expire on
  their own are a key Redis pattern — no background cleanup job needed.
- `INCR` — atomically increments a counter. Atomic means it is safe to call from multiple
  application instances simultaneously without a race condition. This is the basis for
  per-user rate limiting.
- `ZADD` / `ZREVRANGE` — a Sorted Set stores members with numeric scores. `ZREVRANGE`
  returns them highest-score-first. This is the standard real-time leaderboard pattern.

Exit the VM: `exit`

> **ACE exam tip:** Memorystore has no public endpoint — you cannot connect to it from
> your laptop or from outside GCP. Clients must be in the same VPC (or a VPC peered to
> the Memorystore VPC). If the exam describes an application that cannot reach Memorystore,
> the most likely cause is the client being in a different VPC or a missing VPC peering.

---

### Exercise 8 — Database Selection: Five Scenarios

This exercise tests your database decision-making. For each scenario below, read the
requirements, then check your answer against the explanation. This is the type of
question that appears 3–5 times on the ACE exam.

Work through each scenario yourself before reading the explanation.

---

**Scenario A — Global Financial Ledger**

> Your company is building a global payment platform. Transactions must be ACID-compliant.
> The platform serves users in North America, Europe, and Asia simultaneously. Consistency
> is paramount — an account balance must never show stale data regardless of which region
> serves the read.

```bash
# Display the answer
echo "Answer for Scenario A:"
echo ""
echo "Database: Cloud Spanner"
echo ""
echo "Reasoning:"
echo "  - ACID transactions: Cloud SQL or Spanner (both qualify)"
echo "  - GLOBAL scale + STRONG consistency: eliminates Cloud SQL"
echo "  - Cloud SQL is single-region; cross-region replicas are async (eventual)"
echo "  - Spanner uses TrueTime for globally consistent transactions"
echo "  - 99.999% SLA multi-region config matches 'financial platform' requirements"
echo ""
echo "Wrong answers:"
echo "  - Cloud SQL: strong consistency but single-region only"
echo "  - Bigtable: no ACID transactions, eventual consistency"
echo "  - BigQuery: analytical, not transactional"
```

---

**Scenario B — Mobile App User Profiles**

> A mobile app stores user profiles, settings, and social graph data. The data is
> document-shaped (nested JSON). The mobile client needs to receive real-time updates when
> a friend updates their profile, without polling. Expected scale: 10M users at launch.

```bash
echo "Answer for Scenario B:"
echo ""
echo "Database: Firestore (Native mode)"
echo ""
echo "Reasoning:"
echo "  - Document-shaped (nested JSON): matches Firestore's data model"
echo "  - Real-time updates to mobile clients: Firestore's real-time listeners"
echo "  - 10M users: Firestore scales horizontally without configuration"
echo "  - Native mode (not Datastore mode): real-time listeners only in Native mode"
echo ""
echo "Wrong answers:"
echo "  - Cloud SQL: relational model, no real-time push, vertical scaling"
echo "  - Bigtable: no real-time SDK, not document model"
echo "  - Memorystore: cache, not durable storage"
```

---

**Scenario C — IoT Sensor Time Series**

> A manufacturing plant has 50,000 sensors each writing a reading every second. You need
> to store 3 years of sensor history (estimated 15 TB) and run time-windowed aggregations
> (e.g. "average temperature over the last 30 minutes for sensor group A"). Writes must
> be extremely fast. Reads are less frequent but scan large time ranges.

```bash
echo "Answer for Scenario C:"
echo ""
echo "Database: Cloud Bigtable"
echo ""
echo "Reasoning:"
echo "  - 50k sensors × 1 write/sec = 50,000 writes/sec: Bigtable handles millions/sec"
echo "  - 15 TB: above the ~1 TB threshold where Bigtable shines"
echo "  - Time series: Bigtable row key = sensor_id#timestamp is the canonical pattern"
echo "  - Time-windowed aggregations: Bigtable row scans over key ranges are efficient"
echo ""
echo "Row key design:"
echo "  sensor_group_A#sensor_001#2024-01-01T00:00:01Z"
echo "  → scan all rows with prefix 'sensor_group_A#' for group aggregations"
echo ""
echo "Wrong answers:"
echo "  - Cloud SQL: cannot handle 50k writes/sec, 15 TB on a single instance"
echo "  - BigQuery: good for historical analytics but not real-time writes at this rate"
echo "  - Firestore: document model is wrong; not optimised for time series at this scale"
```

---

**Scenario D — E-commerce Product Catalog with Cache**

> An e-commerce site runs a MySQL database on Cloud SQL. Product detail pages are slow
> because the same queries run on every page load. The product catalogue rarely changes
> (updates a few times per day). You want sub-millisecond response for catalogue queries.

```bash
echo "Answer for Scenario D:"
echo ""
echo "Database: Keep Cloud SQL (MySQL) AND add Memorystore Redis as a cache"
echo ""
echo "Reasoning:"
echo "  - Existing MySQL: no reason to migrate; Cloud SQL handles OLTP fine"
echo "  - Sub-millisecond + rarely-changing data: perfect cache candidate"
echo "  - Memorystore Redis: cache product JSON with TTL of e.g. 1 hour"
echo "  - Application: check Redis first; on miss, query Cloud SQL and populate cache"
echo ""
echo "Cache-aside pattern:"
echo "  1. App checks Redis: GET product:12345"
echo "  2. Cache HIT: return instantly (~0.5ms)"
echo "  3. Cache MISS: query Cloud SQL, SET product:12345 [result] EX 3600, return"
echo ""
echo "Wrong answers:"
echo "  - Bigtable: over-engineered for a product catalogue; no SQL, no joins"
echo "  - Spanner: expensive; strong consistency not needed for a product catalogue"
echo "  - BigQuery: analytical; wrong for OLTP page loads"
```

---

**Scenario E — Sales Analytics Dashboard**

> The finance team needs a dashboard that shows sales trends, revenue by region, and
> top-selling products over the last 3 years. The source data is 500 GB of order records.
> Queries run complex aggregations across all records and take minutes. The team runs
> about 10 ad-hoc queries per day. There is no requirement for real-time data.

```bash
echo "Answer for Scenario E:"
echo ""
echo "Database: BigQuery"
echo ""
echo "Reasoning:"
echo "  - OLAP (analytical) workload, not OLTP: BigQuery's sweet spot"
echo "  - 500 GB with complex aggregations: BigQuery is columnar, reads only needed columns"
echo "  - Queries take minutes: acceptable for analytics; BigQuery optimises for throughput"
echo "  - 10 queries/day: serverless pricing means you pay per query, not per hour"
echo "  - No real-time: data can be loaded in batches (e.g. daily ETL from Cloud SQL)"
echo ""
echo "Wrong answers:"
echo "  - Cloud SQL: OLTP engine; aggregation queries on 500 GB would be very slow"
echo "  - Bigtable: not a query engine; no GROUP BY, no complex aggregations"
echo "  - Spanner: transactional; expensive; wrong for analytics"
```

---

## Key Takeaways

- **Cloud SQL** is for relational OLTP workloads. It supports MySQL, PostgreSQL, and SQL
  Server. Scale is vertical (bigger machine) plus read replicas for read throughput.

- **Cloud Spanner** is the only globally distributed, strongly consistent relational
  database. Use it when Cloud SQL's single-region consistency is not enough. It is
  expensive — ~$0.90/hr for one node.

- **Cloud SQL High Availability** (`--availability-type=REGIONAL`) adds a synchronous
  standby in a different zone within the same region. Failover is automatic (~60–120s
  downtime). HA roughly doubles cost. It does not protect against data corruption or
  accidental deletions.

- **Read replicas** use asynchronous replication and accept read-only connections. They
  scale read throughput. Cross-region read replicas also serve as a DR option. Promoting
  a read replica is manual and irreversible.

- **The Cloud SQL Auth Proxy** is the recommended connection method from GCE, GKE, and
  Cloud Run. It authenticates via IAM service accounts, requires no SSL cert management,
  and no IP allowlisting. The service account needs `roles/cloudsql.client`.

- **Point-in-time recovery** (PITR) requires `pointInTimeRecoveryEnabled: true` and
  archives transaction logs. Restore creates a new clone instance at the target timestamp.
  The default retention window is 7 days.

- **Firestore Native mode** is for document data with real-time client sync (mobile/web
  backends). Firestore Datastore mode is for legacy Cloud Datastore migrations. You
  cannot switch between modes after instance creation.

- **Bigtable** is for wide-column, high-throughput, > 1 TB datasets (IoT, time series,
  ad tech). Row key design determines performance — avoid sequential keys (timestamps,
  auto-increment IDs) as the first component to prevent hotspots.

- **BigQuery** is for OLAP analytics and data warehousing, not OLTP transactions. It is
  serverless — you pay per query (TB scanned), not per hour. It is not appropriate for
  real-time reads or transactional workloads.

- **Memorystore** has no public endpoint. Clients must be in the same VPC. Use it for
  caching, session storage, rate limiting (INCR), and leaderboards (Sorted Sets).

- The exam frequently conflates HA with read replicas. Remember: HA = availability on
  failure (synchronous, same region, automatic). Read replicas = read scaling (async,
  can be cross-region, manual promotion).

---

## Cleanup

Run all commands in this section to destroy every resource created in this lab. Run the
cleanup promptly — Cloud Spanner (if you created it) and Memorystore accrue costs even
when idle.

```bash
# Check what exists before cleanup
../status.sh 9
```

```bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
ZONE="us-central1-a"

echo "=== Deleting Cloud SQL read replica ==="
gcloud sql instances delete lab09-postgres-replica \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Cloud SQL primary instance (HA + backups deleted with it) ==="
gcloud sql instances delete lab09-postgres \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting Memorystore Redis instance ==="
gcloud redis instances delete lab09-redis \
  --region="${REGION}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Deleting GCE client VM ==="
gcloud compute instances delete lab09-db-client \
  --zone="${ZONE}" \
  --quiet \
  --project="${PROJECT_ID}"

echo "=== Cleanup complete ==="
```

Verify nothing remains:

```bash
echo "--- Cloud SQL instances ---"
gcloud sql instances list \
  --filter="name:lab09" \
  --project="${PROJECT_ID}"

echo "--- Memorystore instances ---"
gcloud redis instances list \
  --region="${REGION}" \
  --filter="name:lab09" \
  --project="${PROJECT_ID}"

../status.sh 9
```

All sections should be empty. If any resources remain, delete them individually
using the resource type and name shown.

> **Reminder:** If you created a Cloud Spanner instance outside of this lab (by following
> the conceptual example), delete it immediately:
> ```bash
> gcloud spanner instances delete lab09-spanner \
>   --quiet \
>   --project="${PROJECT_ID}"
> ```
> Spanner charges ~$0.90/hr and will continue billing until deleted.
