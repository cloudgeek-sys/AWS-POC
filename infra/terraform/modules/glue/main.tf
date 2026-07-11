locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_glue_catalog_database" "bronze" {
  name = "${replace(local.name_prefix, "-", "_")}_bronze"
}

resource "aws_glue_catalog_database" "silver" {
  name = "${replace(local.name_prefix, "-", "_")}_silver"
}

resource "aws_glue_catalog_database" "gold" {
  name = "${replace(local.name_prefix, "-", "_")}_gold"
}

resource "aws_glue_job" "ingest" {
  name     = "${local.name_prefix}-bronze-ingest-power-plants"
  role_arn = var.glue_role_arn

  command {
    script_location = "s3://${var.data_lake_bucket}/code/pipelines/bronze/ingest_power_plants.py"
    python_version  = "3"
  }

  default_arguments = {
    "--extra-py-files" = "s3://${var.data_lake_bucket}/code/pipelines_bundle.zip"
    "--config"         = "s3://${var.data_lake_bucket}/code/pipelines/configs/sources.yaml"
    "--source-base"    = "s3://${var.data_lake_bucket}"
    "--data-root"      = "s3://${var.data_lake_bucket}"
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.job_worker_count
  max_retries       = 1
  timeout           = 30
}

resource "aws_glue_job" "silver" {
  name     = "${local.name_prefix}-silver-transform-power-plants"
  role_arn = var.glue_role_arn

  command {
    script_location = "s3://${var.data_lake_bucket}/code/pipelines/silver/transform_power_plants.py"
    python_version  = "3"
  }

  default_arguments = {
    "--extra-py-files" = "s3://${var.data_lake_bucket}/code/pipelines_bundle.zip"
    "--schema"         = "s3://${var.data_lake_bucket}/code/pipelines/schemas/power_plants_schema.json"
    "--data-root"      = "s3://${var.data_lake_bucket}"
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.job_worker_count
  max_retries       = 1
  timeout           = 30
}

resource "aws_glue_job" "gold" {
  name     = "${local.name_prefix}-gold-build-power-analytics"
  role_arn = var.glue_role_arn

  command {
    script_location = "s3://${var.data_lake_bucket}/code/pipelines/gold/build_gold_tables.py"
    python_version  = "3"
  }

  default_arguments = {
    "--extra-py-files" = "s3://${var.data_lake_bucket}/code/pipelines_bundle.zip"
    "--data-root"      = "s3://${var.data_lake_bucket}"
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.job_worker_count
  max_retries       = 1
  timeout           = 30
}
