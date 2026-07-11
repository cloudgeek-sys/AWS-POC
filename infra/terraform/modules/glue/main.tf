locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_cloudwatch_log_group" "glue_jobs" {
  name              = "/aws-glue/jobs/${local.name_prefix}"
  retention_in_days = 30
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

resource "aws_glue_crawler" "bronze" {
  name          = "${local.name_prefix}-bronze-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.bronze.name

  s3_target {
    path = "s3://${var.data_lake_bucket}/bronze/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "silver" {
  name          = "${local.name_prefix}-silver-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.silver.name

  s3_target {
    path = "s3://${var.data_lake_bucket}/silver/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_crawler" "gold" {
  name          = "${local.name_prefix}-gold-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.gold.name

  s3_target {
    path = "s3://${var.data_lake_bucket}/gold/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_glue_job" "ingest" {
  name     = "${local.name_prefix}-bronze-ingest-power-plants"
  role_arn = var.glue_role_arn

  command {
    script_location = "s3://${var.data_lake_bucket}/code/pipelines/bronze/ingest_power_plants.py"
    python_version  = "3"
  }

  default_arguments = {
    "--extra-py-files"            = "s3://${var.data_lake_bucket}/code/pipelines_bundle.zip"
    "--additional-python-modules" = "kagglehub[pandas-datasets]==0.3.8"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"   = aws_cloudwatch_log_group.glue_jobs.name
    "--enable-metrics"            = "true"
    "--customer-driver-env-vars"  = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--customer-executor-env-vars" = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--config"                    = "s3://${var.data_lake_bucket}/code/pipelines/configs/sources.yaml"
    "--source-base"               = "s3://${var.data_lake_bucket}"
    "--data-root"                 = "s3://${var.data_lake_bucket}"
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
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup" = aws_cloudwatch_log_group.glue_jobs.name
    "--enable-metrics" = "true"
    "--customer-driver-env-vars" = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--customer-executor-env-vars" = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
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
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup" = aws_cloudwatch_log_group.glue_jobs.name
    "--enable-metrics" = "true"
    "--customer-driver-env-vars" = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--customer-executor-env-vars" = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--data-root"      = "s3://${var.data_lake_bucket}"
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.job_worker_count
  max_retries       = 1
  timeout           = 30
}

resource "aws_glue_job" "visualizations" {
  name     = "${local.name_prefix}-visualizations-build"
  role_arn = var.glue_role_arn

  command {
    script_location = "s3://${var.data_lake_bucket}/code/pipelines/gold/build_visualizations.py"
    python_version  = "3"
  }

  default_arguments = {
    "--additional-python-modules" = "matplotlib==3.8.4"
    "--extra-py-files"            = "s3://${var.data_lake_bucket}/code/pipelines_bundle.zip"
    "--enable-continuous-cloudwatch-log" = "true"
    "--continuous-log-logGroup"   = aws_cloudwatch_log_group.glue_jobs.name
    "--enable-metrics"            = "true"
    "--customer-driver-env-vars"  = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--customer-executor-env-vars" = "GPPA_PROJECT_NAME=${var.project_name},GPPA_ENVIRONMENT=${var.environment}"
    "--data-root"                 = "s3://${var.data_lake_bucket}"
  }

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.job_worker_count
  max_retries       = 1
  timeout           = 30
}
