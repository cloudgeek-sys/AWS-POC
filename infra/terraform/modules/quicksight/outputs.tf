output "athena_data_source_arn" {
  value = try(aws_quicksight_data_source.athena[0].arn, null)
}

output "athena_data_source_name" {
  value = try(aws_quicksight_data_source.athena[0].name, null)
}

output "dashboard_dataset_arns" {
  value = length(aws_quicksight_data_set.dashboard) > 0 ? {
    for k, v in aws_quicksight_data_set.dashboard : k => v.arn
  } : var.unmanaged_dashboard_dataset_arns
}

output "dashboard_arns" {
  value = {
    for k, v in aws_quicksight_dashboard.dashboard : k => v.arn
  }
}
