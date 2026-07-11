variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project identifier"
  type        = string
  default     = "gppa"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "main"
}

variable "data_lake_bucket_suffix" {
  description = "Globally unique suffix for S3 bucket naming"
  type        = string
}

variable "glue_job_worker_count" {
  description = "Glue worker count in main"
  type        = number
  default     = 2
}

variable "schedule_expression" {
  description = "EventBridge schedule expression"
  type        = string
  default     = "cron(0 4 * * ? *)"
}

variable "deployer_policy_enabled" {
  description = "Create least-privilege Terraform deployer policy"
  type        = bool
  default     = true
}

variable "deployer_role_name" {
  description = "Optional existing IAM role name to attach deployer policy"
  type        = string
  default     = null
}

variable "deployer_user_name" {
  description = "Optional existing IAM user name to attach deployer policy"
  type        = string
  default     = null
}

variable "enable_quicksight" {
  description = "Enable provisioning of QuickSight data source resources"
  type        = bool
  default     = false
}

variable "quicksight_user_arn" {
  description = "QuickSight user or group ARN for data source permissions"
  type        = string
  default     = null
}

variable "quicksight_dataset_principal_arns" {
  description = "QuickSight principal ARNs to grant dataset permissions"
  type        = list(string)
  default     = []
}

variable "athena_database_name" {
  description = "Athena database name for QuickSight datasets"
  type        = string
  default     = "gppa_main_analytics"
}

variable "enable_quicksight_datasets" {
  description = "Enable provisioning of QuickSight datasets over Athena views"
  type        = bool
  default     = true
}

variable "enable_quicksight_dashboards" {
  description = "Enable provisioning of QuickSight dashboards from templates"
  type        = bool
  default     = false
}

variable "quicksight_dashboard_templates" {
  description = "Map of QuickSight dashboard templates keyed by dashboard key"
  type = map(object({
    template_arn          = string
    data_set_placeholders = map(string)
  }))
  default = {}
}

variable "unmanaged_quicksight_dataset_arns" {
  description = "Dataset ARN map to expose in outputs when QuickSight datasets are unmanaged"
  type        = map(string)
  default     = {}
}
