data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../lambda/function.zip"
}

# ── Lambda: Kinesis consumer ──────────────────────────────────────────────────
resource "aws_lambda_function" "processor" {
  function_name    = "${local.prefix}-processor"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory
  role             = aws_iam_role.lambda.arn

  environment {
    variables = {
      RAW_BUCKET         = aws_s3_bucket.raw.bucket
      PROCESSED_BUCKET   = aws_s3_bucket.processed.bucket
      LATE_ARRIVALS_QUEUE = aws_sqs_queue.late_arrivals.url
      DLQ_URL            = aws_sqs_queue.events_dlq.url
      LATE_THRESHOLD_HOURS = "3"
      ENVIRONMENT        = var.environment
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.events_dlq.arn
  }

  tracing_config {
    mode = "Active"  # X-Ray tracing
  }
}

# ── Lambda: Late arrival reprocessor (triggered by late_arrivals SQS) ────────
resource "aws_lambda_function" "late_reprocessor" {
  function_name    = "${local.prefix}-late-reprocessor"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "late_reprocessor.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  role             = aws_iam_role.lambda.arn

  environment {
    variables = {
      RAW_BUCKET       = aws_s3_bucket.raw.bucket
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
      GLUE_JOB_NAME    = aws_glue_job.etl.name
      ENVIRONMENT      = var.environment
    }
  }

  tracing_config {
    mode = "Active"
  }
}

# ── Kinesis → Lambda event source mapping ────────────────────────────────────
resource "aws_lambda_event_source_mapping" "kinesis" {
  event_source_arn              = aws_kinesis_stream.events.arn
  function_name                 = aws_lambda_function.processor.arn
  starting_position             = "LATEST"
  batch_size                    = 100
  maximum_batching_window_in_seconds = 10
  parallelization_factor        = 2

  # On failure → route to SQS DLQ for investigation
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.events_dlq.arn
    }
  }

  filter_criteria {
    filter {
      pattern = jsonencode({ data = { type = ["order", "click", "payment"] } })
    }
  }
}

# ── SQS late_arrivals → late_reprocessor Lambda ───────────────────────────────
resource "aws_lambda_event_source_mapping" "late_arrivals" {
  event_source_arn = aws_sqs_queue.late_arrivals.arn
  function_name    = aws_lambda_function.late_reprocessor.arn
  batch_size       = 10
}
