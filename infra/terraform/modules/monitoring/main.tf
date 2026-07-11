locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_cloudwatch_metric_alarm" "pipeline_execution_failed" {
  alarm_name          = "${local.name_prefix}-pipeline-execution-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when pipeline Step Functions executions fail"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.step_function_arn
  }
}

resource "aws_cloudwatch_metric_alarm" "pipeline_execution_time" {
  alarm_name          = "${local.name_prefix}-pipeline-execution-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionTime"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Maximum"
  threshold           = 3600000
  alarm_description   = "Triggers when pipeline execution time exceeds 60 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = var.step_function_arn
  }
}

resource "aws_cloudwatch_metric_alarm" "glue_ingest_failed" {
  alarm_name          = "${local.name_prefix}-glue-ingest-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedJobs"
  namespace           = "AWS/Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when Glue ingest stage has failed jobs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.ingest_job_name
  }
}

resource "aws_cloudwatch_metric_alarm" "glue_silver_failed" {
  alarm_name          = "${local.name_prefix}-glue-silver-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedJobs"
  namespace           = "AWS/Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when Glue silver stage has failed jobs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.silver_job_name
  }
}

resource "aws_cloudwatch_metric_alarm" "glue_gold_failed" {
  alarm_name          = "${local.name_prefix}-glue-gold-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedJobs"
  namespace           = "AWS/Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when Glue gold stage has failed jobs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.gold_job_name
  }
}

resource "aws_cloudwatch_metric_alarm" "glue_visualization_failed" {
  alarm_name          = "${local.name_prefix}-glue-visualization-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedJobs"
  namespace           = "AWS/Glue"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when Glue visualization stage has failed jobs"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName = var.visualization_job_name
  }
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

  dimensions = {
    Project     = var.project_name
    Environment = var.environment
  }
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

  dimensions = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_metric_alarm" "processing_rows_low" {
  alarm_name          = "${local.name_prefix}-processing-rows-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "bronze_rows_ingested"
  namespace           = "GPPA/Pipeline"
  period              = 3600
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Triggers when bronze stage ingests zero rows"
  treat_missing_data  = "breaching"

  dimensions = {
    Project     = var.project_name
    Environment = var.environment
  }
}
