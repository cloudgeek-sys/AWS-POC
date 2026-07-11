variable "project_name" {
  description = "Project identifier"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "athena_workgroup_name" {
  description = "Athena workgroup used by QuickSight data source"
  type        = string
}

variable "enable_quicksight" {
  description = "Whether to provision QuickSight resources"
  type        = bool
  default     = false
}

variable "quicksight_user_arn" {
  description = "QuickSight user or group ARN to grant data source permissions"
  type        = string
  default     = null
}

variable "quicksight_dataset_principal_arns" {
  description = "QuickSight principal ARNs (users/groups) to grant dataset permissions"
  type        = list(string)
  default     = []
}

variable "athena_database_name" {
  description = "Athena database name containing dashboard views"
  type        = string
  default     = "gppa_main_analytics"
}

variable "enable_quicksight_datasets" {
  description = "Whether to provision QuickSight datasets over Athena views"
  type        = bool
  default     = true
}

variable "enable_quicksight_dashboards" {
  description = "Whether to provision QuickSight dashboards from templates"
  type        = bool
  default     = false
}

variable "quicksight_dashboard_templates" {
  description = "Dashboard template definitions keyed by dashboard key (power_generation, plant, sustainability, monitoring)"
  type = map(object({
    template_arn          = string
    data_set_placeholders = map(string)
  }))
  default = {}
}

variable "unmanaged_dashboard_dataset_arns" {
  description = "Fallback dataset ARN map when dataset resources are intentionally unmanaged by Terraform"
  type        = map(string)
  default     = {}
}
