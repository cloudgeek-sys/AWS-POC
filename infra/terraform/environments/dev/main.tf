locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "s3_lake" {
  source = "../../modules/s3_lake"

  bucket_name = "${local.name_prefix}-lake-${var.data_lake_bucket_suffix}"
}

module "iam" {
  source = "../../modules/iam"

  project_name       = var.project_name
  environment        = var.environment
  data_lake_bucket   = module.s3_lake.bucket_name
  data_lake_bucket_arn = module.s3_lake.bucket_arn
}

module "glue" {
  source = "../../modules/glue"

  project_name          = var.project_name
  environment           = var.environment
  data_lake_bucket      = module.s3_lake.bucket_name
  glue_role_arn         = module.iam.glue_role_arn
  job_worker_count      = var.glue_job_worker_count
}

module "athena" {
  source = "../../modules/athena"

  project_name     = var.project_name
  environment      = var.environment
  data_lake_bucket = module.s3_lake.bucket_name
}

module "step_functions" {
  source = "../../modules/step_functions"

  project_name              = var.project_name
  environment               = var.environment
  step_functions_role_arn   = module.iam.step_functions_role_arn
  ingest_job_name           = module.glue.ingest_job_name
  silver_job_name           = module.glue.silver_job_name
  gold_job_name             = module.glue.gold_job_name
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name = var.project_name
  environment  = var.environment
}
