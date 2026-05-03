"""
Late arrival reprocessor Lambda.

Triggered by: SQS late_arrivals queue
Does:
  1. Reads late event from SQS
  2. Confirms the raw record is already in S3 (written by the main handler)
  3. Triggers a targeted Glue job run for the affected event_date partition only
  4. Logs lateness metrics to CloudWatch
"""

import json
import os
import boto3
from datetime import datetime, timezone
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

glue       = boto3.client("glue")
cloudwatch = boto3.client("cloudwatch")

GLUE_JOB_NAME    = os.environ["GLUE_JOB_NAME"]
RAW_BUCKET       = os.environ["RAW_BUCKET"]
PROCESSED_BUCKET = os.environ["PROCESSED_BUCKET"]
ENVIRONMENT      = os.environ.get("ENVIRONMENT", "dev")


def lambda_handler(event, context):
    """Process a batch of late-arrival SQS messages."""
    results = {"reprocessed": 0, "errors": 0}

    for record in event["Records"]:
        try:
            message = json.loads(record["body"])
            handle_late_record(message)
            results["reprocessed"] += 1
        except Exception as exc:
            logger.error("Failed to reprocess late record: %s | error: %s", record, exc)
            results["errors"] += 1
            # Re-raise so SQS returns the message to the queue (up to maxReceiveCount)
            raise

    logger.info("Late reprocessor complete: %s", results)
    return {"statusCode": 200, "body": results}


# ── Helpers ───────────────────────────────────────────────────────────────────

def handle_late_record(message: dict):
    """Trigger a Glue reprocessing job for the affected date partition."""
    event_time_str = message["event_time"]
    lateness_secs  = message.get("lateness_seconds", 0)
    event_time     = datetime.fromisoformat(event_time_str.replace("Z", "+00:00"))

    logger.info(
        "Reprocessing late record | event_time=%s | lateness=%ss",
        event_time_str, lateness_secs
    )

    # Emit lateness metric to CloudWatch for monitoring
    emit_lateness_metric(lateness_secs)

    # Trigger Glue ETL only for the affected date partition
    affected_date = event_time.strftime("%Y-%m-%d")
    trigger_glue_reprocess(affected_date)


def trigger_glue_reprocess(affected_date: str):
    """Start a Glue job scoped to the affected event_date partition."""
    response = glue.start_job_run(
        JobName=GLUE_JOB_NAME,
        Arguments={
            "--RAW_BUCKET":       RAW_BUCKET,
            "--PROCESSED_BUCKET": PROCESSED_BUCKET,
            "--REPROCESS_DATE":   affected_date,   # Glue script uses this to scope work
            "--MODE":             "reprocess",
        }
    )
    logger.info(
        "Started Glue job run | job=%s | run_id=%s | date=%s",
        GLUE_JOB_NAME, response["JobRunId"], affected_date
    )


def emit_lateness_metric(lateness_secs: int):
    """Push a custom metric so we can alert when lateness exceeds SLA."""
    cloudwatch.put_metric_data(
        Namespace="LateDataDemo",
        MetricData=[{
            "MetricName": "LatenessSeconds",
            "Dimensions": [{"Name": "Environment", "Value": ENVIRONMENT}],
            "Value":      lateness_secs,
            "Unit":       "Seconds",
            "Timestamp":  datetime.now(timezone.utc),
        }]
    )
