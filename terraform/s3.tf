locals {
  prefix = "${var.project}-${var.environment}"
}

# ── Raw data lake bucket ──────────────────────────────────────────────────────
resource "aws_s3_bucket" "raw" {
  bucket = "${local.prefix}-raw-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    id     = "archive-old-raw"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# ── Processed / curated bucket ───────────────────────────────────────────────
resource "aws_s3_bucket" "processed" {
  bucket = "${local.prefix}-processed-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id
  versioning_configuration { status = "Enabled" }
}

# ── Glue scripts bucket ───────────────────────────────────────────────────────
resource "aws_s3_bucket" "glue_scripts" {
  bucket = "${local.prefix}-glue-scripts-${data.aws_caller_identity.current.account_id}"
}

# Upload the Glue ETL script automatically
resource "aws_s3_object" "glue_etl_script" {
  bucket = aws_s3_bucket.glue_scripts.id
  key    = "scripts/etl_late_data.py"
  source = "${path.module}/../glue/etl_late_data.py"
  etag   = filemd5("${path.module}/../glue/etl_late_data.py")
}

# Block all public access on every bucket
resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}
