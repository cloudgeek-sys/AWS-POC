locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "s3_lake" {
  source = "../../modules/s3_lake"

  bucket_name = "${local.name_prefix}-lake-${var.data_lake_bucket_suffix}"
}

module "iam" {
  source = "../../modules/iam"

  project_name            = var.project_name
  environment             = var.environment
  data_lake_bucket        = module.s3_lake.bucket_name
  data_lake_bucket_arn    = module.s3_lake.bucket_arn
  deployer_policy_enabled = var.deployer_policy_enabled
  deployer_role_name      = var.deployer_role_name
  deployer_user_name      = var.deployer_user_name
}

module "glue" {
  source = "../../modules/glue"

  project_name            = var.project_name
  environment             = var.environment
  data_lake_bucket        = module.s3_lake.bucket_name
  glue_role_arn           = module.iam.glue_role_arn
  job_worker_count        = var.glue_job_worker_count
  max_concurrent_job_runs = var.max_concurrent_job_runs
}

module "athena" {
  source = "../../modules/athena"

  project_name     = var.project_name
  environment      = var.environment
  data_lake_bucket = module.s3_lake.bucket_name
}

module "quicksight" {
  source = "../../modules/quicksight"

  project_name                      = var.project_name
  environment                       = var.environment
  athena_workgroup_name             = module.athena.workgroup_name
  enable_quicksight                 = var.enable_quicksight
  quicksight_user_arn               = var.quicksight_user_arn
  quicksight_dataset_principal_arns = var.quicksight_dataset_principal_arns
  athena_database_name              = var.athena_database_name
  unmanaged_dashboard_dataset_arns  = var.unmanaged_quicksight_dataset_arns

  enable_quicksight_datasets     = var.enable_quicksight_datasets
  enable_quicksight_dashboards   = var.enable_quicksight_dashboards
  quicksight_dashboard_templates = var.quicksight_dashboard_templates
}

module "step_functions" {
  source = "../../modules/step_functions"

  project_name            = var.project_name
  environment             = var.environment
  step_functions_role_arn = module.iam.step_functions_role_arn
  ingest_job_name         = module.glue.ingest_job_name
  silver_job_name         = module.glue.silver_job_name
  gold_job_name           = module.glue.gold_job_name
  visualization_job_name  = module.glue.visualization_job_name
  athena_workgroup_name   = module.athena.workgroup_name
  athena_database_name    = var.athena_database_name
  data_lake_bucket        = module.s3_lake.bucket_name
}

module "monitoring" {
  source = "../../modules/monitoring"

  project_name             = var.project_name
  environment              = var.environment
  step_function_arn        = module.step_functions.state_machine_arn
  ingest_job_name          = module.glue.ingest_job_name
  silver_job_name          = module.glue.silver_job_name
  gold_job_name            = module.glue.gold_job_name
  visualization_job_name   = module.glue.visualization_job_name
  alarm_notification_email = var.alarm_notification_email
}
