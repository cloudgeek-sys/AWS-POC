output "glue_role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "step_functions_role_arn" {
  value = aws_iam_role.step_functions_role.arn
}

output "terraform_deployer_policy_arn" {
  value = var.deployer_policy_enabled ? aws_iam_policy.terraform_deployer[0].arn : null
}

output "terraform_deployer_policy_json" {
  value = data.aws_iam_policy_document.terraform_deployer.json
}
