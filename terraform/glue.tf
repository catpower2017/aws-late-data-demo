
# ── Glue Data Catalog database ───────────────────────────────────────────────

resource "aws_glue_catalog_database" "main" {

  name        = replace("${local.prefix}_db", "-", "_")

  description = "Late arriving data demo — raw and processed tables"

}

# ── Glue Crawler: raw S3 data ─────────────────────────────────────────────────

resource "aws_glue_crawler" "raw" {

  name          = "${local.prefix}-raw-crawler"

  role          = aws_iam_role.glue.arn

  database_name = aws_glue_catalog_database.main.name

  s3_target {

    path = "s3://${aws_s3_bucket.raw.bucket}/events/"

  }

  # Fix 1: CRAWL_NEW_FOLDERS_ONLY requires LOG for both behaviors

  schema_change_policy {

    update_behavior = "LOG"

    delete_behavior = "LOG"

  }

  recrawl_policy {

    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"

  }

  schedule = "cron(0 * * * ? *)"

}

# ── Glue Crawler: processed S3 data ──────────────────────────────────────────

resource "aws_glue_crawler" "processed" {

  name          = "${local.prefix}-processed-crawler"

  role          = aws_iam_role.glue.arn

  database_name = aws_glue_catalog_database.main.name

  s3_target {

    path = "s3://${aws_s3_bucket.processed.bucket}/events/"

  }

  schema_change_policy {

    update_behavior = "LOG"

    delete_behavior = "LOG"

  }

  recrawl_policy {

    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"

  }

  schedule = "cron(0 * * * ? *)"

}

# ── Glue ETL Job ──────────────────────────────────────────────────────────────

resource "aws_glue_job" "etl" {

  name              = "${local.prefix}-etl"

  role_arn          = aws_iam_role.glue.arn

  glue_version      = "4.0"

  worker_type       = var.glue_worker_type

  number_of_workers = var.glue_num_workers

  command {

    name            = "glueetl"

    script_location = "s3://${aws_s3_bucket.glue_scripts.bucket}/scripts/etl_late_data.py"

    python_version  = "3"

  }

  default_arguments = {

    "--job-language"                     = "python"

    "--enable-continuous-cloudwatch-log" = "true"

    "--enable-metrics"                   = "true"

    "--enable-spark-ui"                  = "true"

    "--TempDir"                          = "s3://${aws_s3_bucket.glue_scripts.bucket}/tmp/"

    "--RAW_BUCKET"                       = aws_s3_bucket.raw.bucket

    "--PROCESSED_BUCKET"                 = aws_s3_bucket.processed.bucket

    "--DATABASE_NAME"                    = aws_glue_catalog_database.main.name

    "--ENVIRONMENT"                      = var.environment

  }

  execution_property {

    max_concurrent_runs = 3

  }

}
