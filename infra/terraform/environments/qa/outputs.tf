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
    ingest = module.glue.ingest_job_name
    silver = module.glue.silver_job_name
    gold   = module.glue.gold_job_name
  }
}
