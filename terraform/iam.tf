data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eventbridge_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

# ── Lambda role ───────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name               = "${local.prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kinesis:GetRecords", "kinesis:GetShardIterator",
          "kinesis:DescribeStream", "kinesis:ListShards",
          "kinesis:ListStreams"
        ]
        Resource = aws_kinesis_stream.events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.raw.arn, "${aws_s3_bucket.raw.arn}/*",
          aws_s3_bucket.processed.arn, "${aws_s3_bucket.processed.arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.events.arn, aws_sqs_queue.late_arrivals.arn, aws_sqs_queue.events_dlq.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["glue:StartJobRun", "glue:GetJobRun"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }
    ]
  })
}

# ── Glue role ─────────────────────────────────────────────────────────────────
resource "aws_iam_role" "glue" {
  name               = "${local.prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.raw.arn, "${aws_s3_bucket.raw.arn}/*",
        aws_s3_bucket.processed.arn, "${aws_s3_bucket.processed.arn}/*",
        aws_s3_bucket.glue_scripts.arn, "${aws_s3_bucket.glue_scripts.arn}/*"
      ]
    }]
  })
}

# ── Firehose role ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "firehose" {
  name               = "${local.prefix}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
}

resource "aws_iam_role_policy" "firehose_policy" {
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:ListShards"]
        Resource = aws_kinesis_stream.events.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${aws_s3_bucket.raw.arn}/*"
      }
    ]
  })
}

# ── EventBridge → Glue role ───────────────────────────────────────────────────
resource "aws_iam_role" "eventbridge_glue" {
  name               = "${local.prefix}-eventbridge-glue-role"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume.json
}

resource "aws_iam_role_policy" "eventbridge_glue_policy" {
  role = aws_iam_role.eventbridge_glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["glue:StartJobRun"]
      Resource = "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${aws_glue_job.etl.name}"
    }]
  })
}
