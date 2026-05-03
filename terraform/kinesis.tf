# ── Kinesis Data Stream ───────────────────────────────────────────────────────
resource "aws_kinesis_stream" "events" {
  name             = "${local.prefix}-events"
  shard_count      = var.kinesis_shard_count
  retention_period = var.kinesis_retention_hours

  # Enhanced fan-out + shard-level metrics
  shard_level_metrics = [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
    "IteratorAgeMilliseconds",
  ]

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }
}

# ── Kinesis Firehose → S3 raw (backup / replay path) ─────────────────────────
resource "aws_kinesis_firehose_delivery_stream" "raw_backup" {
  name        = "${local.prefix}-raw-backup"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.events.arn
    role_arn           = aws_iam_role.firehose.arn
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = aws_s3_bucket.raw.arn
    # Partition raw data by event date for efficient late-data reprocessing
    prefix              = "events/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    buffering_size      = 64
    buffering_interval  = 60
    compression_format  = "GZIP"
  }
}
