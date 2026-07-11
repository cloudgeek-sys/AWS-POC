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
  default     = "dev"
}

variable "data_lake_bucket_suffix" {
  description = "Globally unique suffix for S3 bucket naming"
  type        = string
}

variable "glue_job_worker_count" {
  description = "Glue worker count in dev"
  type        = number
  default     = 2
}

variable "schedule_expression" {
  description = "EventBridge schedule expression"
  type        = string
  default     = "cron(0 4 * * ? *)"
}
