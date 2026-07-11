variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "data_lake_bucket" {
  type = string
}

variable "data_lake_bucket_arn" {
  type = string
}

variable "deployer_policy_enabled" {
  description = "Whether to create the least-privilege Terraform deployer policy for this environment"
  type        = bool
  default     = true
}

variable "deployer_role_name" {
  description = "Optional existing IAM role name to attach the Terraform deployer policy to"
  type        = string
  default     = null
}

variable "deployer_user_name" {
  description = "Optional existing IAM user name to attach the Terraform deployer policy to"
  type        = string
  default     = null
}
