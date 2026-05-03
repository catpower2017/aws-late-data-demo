# ── Main processing queue ─────────────────────────────────────────────────────
resource "aws_sqs_queue" "events" {
  name                       = "${local.prefix}-events"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = 1209600  # 14 days
  receive_wait_time_seconds  = 20       # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })
}

# ── Dead letter queue (failed / late events that exceeded retries) ────────────
resource "aws_sqs_queue" "events_dlq" {
  name                      = "${local.prefix}-events-dlq"
  message_retention_seconds = 1209600  # 14 days — keep for investigation
}

# ── Late arrival queue (events older than tolerance window) ───────────────────
resource "aws_sqs_queue" "late_arrivals" {
  name                       = "${local.prefix}-late-arrivals"
  visibility_timeout_seconds = var.sqs_visibility_timeout
  message_retention_seconds  = 1209600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 5
  })
}

# ── CloudWatch alarm on DLQ depth ────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${local.prefix}-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in DLQ — investigate late/failed events"

  dimensions = {
    QueueName = aws_sqs_queue.events_dlq.name
  }
}
