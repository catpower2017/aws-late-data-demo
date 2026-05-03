"""
AWS Glue ETL job — transform raw events and merge late-arriving data.

Reads from:  s3://<RAW_BUCKET>/events/year=*/month=*/day=*/hour=*/
Writes to:   s3://<PROCESSED_BUCKET>/events/ (partitioned by event_date)

Supports two modes:
  full       — process all recent data (scheduled hourly)
  reprocess  — process only a specific date partition (triggered by late arrivals)
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import TimestampType
import boto3
from datetime import datetime, timedelta

# ── Job args ──────────────────────────────────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "RAW_BUCKET",
    "PROCESSED_BUCKET",
    "DATABASE_NAME",
    "ENVIRONMENT",
])
MODE            = args.get("MODE", "full")
REPROCESS_DATE  = args.get("REPROCESS_DATE", None)   # "YYYY-MM-DD" when MODE=reprocess

sc          = SparkContext()
glueContext = GlueContext(sc)
spark       = glueContext.spark_session
job         = Job(glueContext)
job.init(args["JOB_NAME"], args)

RAW_BUCKET       = args["RAW_BUCKET"]
PROCESSED_BUCKET = args["PROCESSED_BUCKET"]


# ── 1. Read raw data ──────────────────────────────────────────────────────────

def get_raw_path() -> str:
    if MODE == "reprocess" and REPROCESS_DATE:
        # Scope to a single date partition — fast and cheap
        dt   = datetime.strptime(REPROCESS_DATE, "%Y-%m-%d")
        return (
            f"s3://{RAW_BUCKET}/events/"
            f"year={dt.year}/month={dt.month:02d}/day={dt.day:02d}/"
        )
    else:
        # Full mode: last 25 hours to catch any events just past the hour boundary
        cutoff = (datetime.utcnow() - timedelta(hours=25)).strftime("%Y-%m-%d")
        return f"s3://{RAW_BUCKET}/events/"

raw_path = get_raw_path()
print(f"[etl] Mode={MODE} | Reading from: {raw_path}")

raw_df = spark.read.json(raw_path)

if raw_df.rdd.isEmpty():
    print("[etl] No data found — exiting cleanly")
    job.commit()
    sys.exit(0)


# ── 2. Clean and enrich ───────────────────────────────────────────────────────

cleaned = (
    raw_df
    # Cast timestamps
    .withColumn("event_time",   F.col("event_time").cast(TimestampType()))
    .withColumn("arrival_time", F.col("arrival_time").cast(TimestampType()))

    # Derive lateness in seconds
    .withColumn(
        "lateness_seconds",
        F.col("arrival_time").cast("long") - F.col("event_time").cast("long")
    )

    # Flag late records (> 3 hours)
    .withColumn("is_late", F.col("lateness_seconds") > 10800)

    # Partition key — always use event_time, not arrival_time
    .withColumn("event_date", F.to_date("event_time"))

    # Drop nulls on key fields
    .dropna(subset=["event_id", "event_time"])

    # Deduplicate — keep the most recently arrived version of each event
    .orderBy(F.col("arrival_time").desc())
    .dropDuplicates(["event_id"])
)

print(f"[etl] Records after cleaning: {cleaned.count()}")
late_count = cleaned.filter(F.col("is_late")).count()
print(f"[etl] Late records in this run: {late_count}")


# ── 3. MERGE into processed layer ────────────────────────────────────────────
# We use insertInto with overwrite per partition so re-running is idempotent.
# Each run for a given event_date fully replaces that partition with the
# deduplicated, corrected dataset — including any late arrivals.

processed_path = f"s3://{PROCESSED_BUCKET}/events/"

(
    cleaned
    .write
    .format("parquet")
    .mode("overwrite")
    .partitionBy("event_date")
    .option("partitionOverwriteMode", "dynamic")   # Only overwrite affected partitions
    .save(processed_path)
)

print(f"[etl] Wrote processed data to {processed_path}")


# ── 4. Update Glue catalog partitions ────────────────────────────────────────
glue_client = boto3.client("glue")
database    = args["DATABASE_NAME"]
table       = "events_processed"

try:
    glue_client.get_table(DatabaseName=database, Name=table)
    # Table exists — update partitions
    spark.sql(f"MSCK REPAIR TABLE {database}.{table}")
    print(f"[etl] Repaired partitions for {database}.{table}")
except glue_client.exceptions.EntityNotFoundException:
    print(f"[etl] Table {table} not yet cataloged — crawler will pick it up")


job.commit()
print("[etl] Job complete")
