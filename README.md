# AWS Late Arriving Data Pipeline — Demo

A production-ready AWS pipeline that handles late arriving data using:
**Kinesis → Lambda → S3 → Glue**, with **SQS** for decoupling and failure handling.

---

## Architecture

```
Producers
    │
    ▼
Kinesis Data Stream  ──────────────────────────────► Firehose → S3 raw (backup)
    │
    ▼
Lambda (processor)
    ├─ On-time events  ──► S3 raw (partitioned by event_date)
    └─ Late events     ──► S3 raw + SQS late_arrivals queue
                                        │
                                        ▼
                               Lambda (late_reprocessor)
                                        │
                                        ▼
                               Glue ETL job (scoped to affected partition)
                                        │
                                        ▼
                               S3 processed (MERGE / overwrite partition)
                                        │
                                        ▼
                               Glue Catalog (Athena / Redshift / Snowflake)

SQS DLQ ◄── failed events from any stage (Lambda, Firehose)
CloudWatch ◄── lateness metrics, DLQ depth alarm
```

### Key design decisions

| Decision | Why |
|---|---|
| Partition raw data by `event_time`, not `arrival_time` | Late records land in the correct date partition for reprocessing |
| Never delete raw data | Always reprocess from source of truth |
| SQS for late arrivals | Decouples detection from reprocessing; retries on failure |
| Glue `partitionOverwriteMode=dynamic` | Only rewrites affected partitions — cheap and idempotent |
| Both timestamps stored | `event_time` for business logic, `arrival_time` for SLA monitoring |

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5
- Python 3.12
- An S3 bucket for Terraform state (update `terraform/main.tf` backend config)

---

## Quick start

### 1. Clone and configure

```bash
git clone <this-repo>
cd aws-late-data-demo
```

Edit `terraform/main.tf` — update the S3 backend bucket name to match your account:
```hcl
backend "s3" {
  bucket = "YOUR-terraform-state-bucket"
  ...
}
```

### 2. Deploy with Terraform

```bash
cd terraform
terraform init
terraform plan -var="environment=dev"
terraform apply -var="environment=dev"
```

Note the outputs — you'll need the Kinesis stream name for testing:
```
kinesis_stream_name = "late-data-demo-dev-events"
raw_bucket          = "late-data-demo-dev-raw-123456789"
```

### 3. Send test events

```bash
pip install boto3
python docs/send_test_events.py \
  --stream late-data-demo-dev-events \
  --region ap-southeast-2
```

This sends a mix of on-time and late events (1h, 4h, 24h, 72h late).

### 4. Observe the pipeline

**Lambda logs** — check CloudWatch Logs for `/aws/lambda/late-data-demo-dev-processor`:
```
[INFO] Batch complete: {'on_time': 3, 'late': 4, 'errors': 0}
[INFO] Late record detected | event_time=... | lateness=0:04:00
```

**SQS late arrivals queue** — check message count in the AWS console:
```
Queue: late-data-demo-dev-late-arrivals
Messages visible: 4
```

**S3 raw bucket** — confirm records are partitioned by event_date (not arrival date):
```
events/year=2024/month=03/day=01/hour=09/  ← correct partition for a 3-day-late event
```

**Glue job** — trigger manually or wait for the hourly EventBridge schedule:
```bash
aws glue start-job-run \
  --job-name late-data-demo-dev-etl \
  --arguments '{"--MODE":"reprocess","--REPROCESS_DATE":"2024-03-01"}'
```

**Athena** — query processed data after Glue runs:
```sql
SELECT
    event_date,
    COUNT(*)              AS total_events,
    SUM(CASE WHEN is_late THEN 1 ELSE 0 END) AS late_events,
    AVG(lateness_seconds) AS avg_lateness_secs
FROM late_data_demo_dev_db.events_processed
GROUP BY event_date
ORDER BY event_date DESC;
```

---

## CI/CD pipeline (GitHub Actions)

1. Add these secrets to your GitHub repo:
   - `AWS_ROLE_ARN` — IAM role ARN with OIDC trust for GitHub Actions

2. On every PR to `main`: Terraform plan runs and posts output as a PR comment.

3. On merge to `main`: Terraform apply runs after manual approval (configure in GitHub Environments).

---

## Project structure

```
aws-late-data-demo/
├── terraform/
│   ├── main.tf          # Provider + backend
│   ├── variables.tf     # All configurable inputs
│   ├── s3.tf            # Raw, processed, glue-scripts buckets
│   ├── kinesis.tf       # Kinesis stream + Firehose backup
│   ├── sqs.tf           # Events queue, late_arrivals queue, DLQ
│   ├── lambda.tf        # processor + late_reprocessor functions
│   ├── glue.tf          # Crawler, ETL job, EventBridge schedule
│   ├── iam.tf           # All IAM roles and policies
│   └── outputs.tf       # Key resource names/ARNs
├── lambda/
│   ├── handler.py           # Kinesis consumer — detects late events
│   └── late_reprocessor.py  # SQS consumer — triggers Glue reprocess
├── glue/
│   └── etl_late_data.py     # Spark ETL — merge + deduplicate
├── .github/workflows/
│   └── terraform.yml        # CI/CD pipeline
└── docs/
    └── send_test_events.py  # Test producer script
```

---

## Cleanup

```bash
cd terraform
terraform destroy -var="environment=dev"
```
