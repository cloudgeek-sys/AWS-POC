locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_cloudwatch_metric_alarm" "dq_failure_alarm" {
  alarm_name          = "${local.name_prefix}-dq-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "dq_failure_count"
  namespace           = "GPPA/Pipeline"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when data quality failures are observed"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "freshness_alarm" {
  alarm_name          = "${local.name_prefix}-freshness-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "freshness_lag_hours"
  namespace           = "GPPA/Pipeline"
  period              = 3600
  statistic           = "Maximum"
  threshold           = 24
  alarm_description   = "Triggers when data ingestion lag exceeds 24 hours"
  treat_missing_data  = "missing"
}
