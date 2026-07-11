output "dq_alarm_name" {
  value = aws_cloudwatch_metric_alarm.dq_failure_alarm.alarm_name
}

output "freshness_alarm_name" {
  value = aws_cloudwatch_metric_alarm.freshness_alarm.alarm_name
}
