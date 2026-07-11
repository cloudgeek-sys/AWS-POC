output "data_lake_bucket" {
  value = module.s3_lake.bucket_name
}

output "athena_workgroup" {
  value = module.athena.workgroup_name
}

output "step_function_arn" {
  value = module.step_functions.state_machine_arn
}

output "glue_jobs" {
  value = {
    ingest        = module.glue.ingest_job_name
    silver        = module.glue.silver_job_name
    gold          = module.glue.gold_job_name
    visualization = module.glue.visualization_job_name
  }
}

output "glue_crawlers" {
  value = module.glue.crawler_names
}

output "terraform_deployer_policy_arn" {
  value = module.iam.terraform_deployer_policy_arn
}

output "quicksight_athena_data_source_arn" {
  value = module.quicksight.athena_data_source_arn
}

output "quicksight_dashboard_dataset_arns" {
  value = module.quicksight.dashboard_dataset_arns
}

output "quicksight_dashboard_arns" {
  value = module.quicksight.dashboard_arns
}
