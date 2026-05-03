"""
Test producer — sends on-time and late events to Kinesis for demo purposes.

Usage:
    pip install boto3
    python send_test_events.py --stream <kinesis-stream-name> --region ap-southeast-2
"""

import argparse
import base64
import json
import time
import uuid
import boto3
from datetime import datetime, timezone, timedelta
import random

def make_event(hours_late: float = 0) -> dict:
    event_time = datetime.now(timezone.utc) - timedelta(hours=hours_late)
    return {
        "event_id":    str(uuid.uuid4()),
        "event_type":  random.choice(["order", "click", "payment"]),
        "user_id":     f"user_{random.randint(1000, 9999)}",
        "amount":      round(random.uniform(5.0, 500.0), 2),
        "event_time":  event_time.isoformat(),
        "source":      "test-producer",
    }

def send_events(stream_name: str, region: str):
    client = boto3.client("kinesis", region_name=region)

    scenarios = [
        ("On-time event",        0),
        ("On-time event",        0),
        ("On-time event",        0),
        ("1-hour late event",    1),
        ("4-hour late event",    4),    # exceeds 3h threshold → late queue
        ("24-hour late event",   24),   # very late
        ("3-day late event",     72),   # extremely late
    ]

    for label, hours_late in scenarios:
        event = make_event(hours_late)
        client.put_record(
            StreamName    = stream_name,
            Data          = json.dumps(event).encode("utf-8"),
            PartitionKey  = event["user_id"],
        )
        print(f"  Sent [{label}] event_id={event['event_id']} event_time={event['event_time']}")
        time.sleep(0.2)

    print(f"\nSent {len(scenarios)} test events to {stream_name}")
    print("Check Lambda logs and the late_arrivals SQS queue to see routing in action.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--stream",  required=True, help="Kinesis stream name")
    parser.add_argument("--region",  default="ap-southeast-2")
    args = parser.parse_args()
    send_events(args.stream, args.region)
