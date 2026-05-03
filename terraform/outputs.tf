output "kinesis_stream_name" {
  value       = aws_kinesis_stream.events.name
  description = "Kinesis stream name — use this to send test events"
}

output "kinesis_stream_arn" {
  value = aws_kinesis_stream.events.arn
}

output "raw_bucket" {
  value       = aws_s3_bucket.raw.bucket
  description = "S3 raw data lake bucket"
}

output "processed_bucket" {
  value       = aws_s3_bucket.processed.bucket
  description = "S3 processed/curated bucket"
}

output "events_queue_url" {
  value       = aws_sqs_queue.events.url
  description = "Main SQS queue URL"
}

output "late_arrivals_queue_url" {
  value       = aws_sqs_queue.late_arrivals.url
  description = "Late arrivals SQS queue URL"
}

output "dlq_url" {
  value       = aws_sqs_queue.events_dlq.url
  description = "Dead letter queue URL — monitor this for failures"
}

output "lambda_processor_name" {
  value = aws_lambda_function.processor.function_name
}

output "glue_job_name" {
  value       = aws_glue_job.etl.name
  description = "Glue ETL job name — trigger manually for testing"
}

output "glue_database" {
  value = aws_glue_catalog_database.main.name
}
