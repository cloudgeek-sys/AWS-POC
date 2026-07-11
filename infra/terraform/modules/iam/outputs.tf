output "glue_role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "step_functions_role_arn" {
  value = aws_iam_role.step_functions_role.arn
}
