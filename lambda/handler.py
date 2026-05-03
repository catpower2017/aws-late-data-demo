"""
Lambda handler — Kinesis consumer with late arriving data detection.

Flow:
  Kinesis record → decode → check event_time vs arrival_time
    ├─ on-time  → write to S3 raw, trigger Glue if needed
    └─ late     → write to S3 raw + route to late_arrivals SQS queue
"""

import base64
import json
import os
import boto3
from datetime import datetime, timezone, timedelta
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3  = boto3.client("s3")
sqs = boto3.client("sqs")

RAW_BUCKET           = os.environ["RAW_BUCKET"]
PROCESSED_BUCKET     = os.environ["PROCESSED_BUCKET"]
LATE_ARRIVALS_QUEUE  = os.environ["LATE_ARRIVALS_QUEUE"]
LATE_THRESHOLD_HOURS = int(os.environ.get("LATE_THRESHOLD_HOURS", "3"))
ENVIRONMENT          = os.environ.get("ENVIRONMENT", "dev")


def lambda_handler(event, context):
    """Process a batch of Kinesis records."""
    arrival_time = datetime.now(timezone.utc)
    results = {"on_time": 0, "late": 0, "errors": 0}

    for record in event["Records"]:
        try:
            payload = decode_record(record)
            process_record(payload, arrival_time, results)
        except Exception as exc:
            logger.error("Failed to process record: %s | error: %s", record, exc)
            results["errors"] += 1

    logger.info("Batch complete: %s", results)
    return {"statusCode": 200, "body": results}


# ── Helpers ───────────────────────────────────────────────────────────────────

def decode_record(record: dict) -> dict:
    """Base64-decode and JSON-parse a Kinesis record."""
    raw = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")
    payload = json.loads(raw)

    # Stamp arrival time so we always have both timestamps in the raw record
    payload["arrival_time"] = datetime.now(timezone.utc).isoformat()

    # Ensure event_time exists — fall back to arrival_time if missing
    if "event_time" not in payload:
        logger.warning("Record missing event_time — using arrival_time as fallback")
        payload["event_time"] = payload["arrival_time"]

    return payload


def process_record(payload: dict, arrival_time: datetime, results: dict):
    """Route a record based on how late it is."""
    event_time = datetime.fromisoformat(payload["event_time"].replace("Z", "+00:00"))
    lateness   = arrival_time - event_time
    threshold  = timedelta(hours=LATE_THRESHOLD_HOURS)

    # Write raw record to S3 regardless of lateness — never lose data
    write_to_s3(payload, event_time)

    if lateness > threshold:
        logger.info(
            "Late record detected | event_time=%s | lateness=%s",
            payload["event_time"], lateness
        )
        route_to_late_queue(payload, lateness)
        results["late"] += 1
    else:
        results["on_time"] += 1


def write_to_s3(payload: dict, event_time: datetime):
    """
    Write raw record to S3 partitioned by event_date.
    Partitioning by event_time (not arrival_time) means late-arriving records
    land in the correct date partition — ready for reprocessing.
    """
    key = (
        f"events/"
        f"year={event_time.year}/"
        f"month={event_time.month:02d}/"
        f"day={event_time.day:02d}/"
        f"hour={event_time.hour:02d}/"
        f"{payload.get('event_id', context_id())}.json"
    )
    s3.put_object(
        Bucket=RAW_BUCKET,
        Key=key,
        Body=json.dumps(payload),
        ContentType="application/json",
    )
    logger.debug("Wrote to s3://%s/%s", RAW_BUCKET, key)


def route_to_late_queue(payload: dict, lateness: timedelta):
    """Send a late record to the late_arrivals SQS queue for reprocessing."""
    message = {
        "event_id":   payload.get("event_id", "unknown"),
        "event_time": payload["event_time"],
        "lateness_seconds": int(lateness.total_seconds()),
        "payload":    payload,
        "routed_at":  datetime.now(timezone.utc).isoformat(),
    }
    sqs.send_message(
        QueueUrl    = LATE_ARRIVALS_QUEUE,
        MessageBody = json.dumps(message),
        MessageAttributes={
            "lateness_seconds": {
                "StringValue": str(int(lateness.total_seconds())),
                "DataType":    "Number",
            }
        },
    )


def context_id() -> str:
    """Fallback ID when event_id is missing."""
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
