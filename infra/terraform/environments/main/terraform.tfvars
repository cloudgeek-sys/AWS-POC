aws_region              = "us-east-1"
project_name            = "gppa"
environment             = "main"
data_lake_bucket_suffix = "platform-20260710212811"
glue_job_worker_count   = 2
max_concurrent_job_runs = 2
schedule_expression     = "cron(0 4 * * ? *)"
enable_quicksight       = true
quicksight_user_arn     = "arn:aws:quicksight:us-east-1:371170753734:user/default/371170753734"
quicksight_dataset_principal_arns = [
  "arn:aws:quicksight:us-east-1:371170753734:user/default/371170753734",
  "arn:aws:quicksight:us-east-1:371170753734:user/default/IAMUserSagar"
]
deployer_user_name             = "IAMUserSagar"
athena_database_name           = "gppa_main_analytics"
enable_quicksight_datasets     = true
enable_quicksight_dashboards   = false
quicksight_dashboard_templates = {}
alarm_notification_email       = "sagarbabupullagura34@gmail.com"
