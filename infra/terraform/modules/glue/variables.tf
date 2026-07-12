variable "project_name" { type = string }
variable "environment" { type = string }
variable "data_lake_bucket" { type = string }
variable "glue_role_arn" { type = string }
variable "job_worker_count" { type = number }

variable "max_concurrent_job_runs" {
	description = "Maximum concurrent runs per Glue job"
	type        = number
	default     = 2
}
