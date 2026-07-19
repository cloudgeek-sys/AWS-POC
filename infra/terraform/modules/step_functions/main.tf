locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_cloudwatch_log_group" "pipeline" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}-power-pipeline"
  retention_in_days = 30
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name_prefix}-power-pipeline"
  role_arn = var.step_functions_role_arn

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"

    log_destination = "${aws_cloudwatch_log_group.pipeline.arn}:*"
  }

  definition = jsonencode({
    Comment = "Global Power Plant Analytics orchestration"
    StartAt = "BronzeIngestion"
    States = {
      BronzeIngestion = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.ingest_job_name
        }
        Retry = [
          {
            ErrorEquals     = ["Glue.ConcurrentRunsExceededException"]
            IntervalSeconds = 60
            MaxAttempts     = 10
            BackoffRate     = 1.5
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Next = "SilverTransform"
      }
      SilverTransform = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.silver_job_name
        }
        Retry = [
          {
            ErrorEquals     = ["Glue.ConcurrentRunsExceededException"]
            IntervalSeconds = 60
            MaxAttempts     = 10
            BackoffRate     = 1.5
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Next = "GoldBuild"
      }
      GoldBuild = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.gold_job_name
        }
        Retry = [
          {
            ErrorEquals     = ["Glue.ConcurrentRunsExceededException"]
            IntervalSeconds = 60
            MaxAttempts     = 10
            BackoffRate     = 1.5
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Next = "RunKpiQuery"
      }
      RunKpiQuery = {
        Type     = "Task"
        Resource = "arn:aws:states:::athena:startQueryExecution.sync"
        Parameters = {
          QueryString = "SELECT total_generation_capacity_mw, renewable_energy_ratio, average_plant_capacity_mw FROM vw_power_generation_kpi_summary"
          WorkGroup   = var.athena_workgroup_name
          QueryExecutionContext = {
            Database = var.athena_database_name
          }
          ResultConfiguration = {
            OutputLocation = "s3://${var.data_lake_bucket}/athena/results/"
          }
        }
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 3
            BackoffRate     = 2.0
          }
        ]
        Next = "BuildVisualizations"
      }
      BuildVisualizations = {
        Type     = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.visualization_job_name
        }
        Retry = [
          {
            ErrorEquals     = ["Glue.ConcurrentRunsExceededException"]
            IntervalSeconds = 60
            MaxAttempts     = 10
            BackoffRate     = 1.5
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        Next = "PublishInsightsAlert"
      }
      PublishInsightsAlert = {
        Type     = "Task"
        Resource = "arn:aws:states:::sns:publish"
        Parameters = {
          TopicArn = "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.name_prefix}-alarm-notifications"
          Subject  = "${local.name_prefix} pipeline insights"
          Message  = "Pipeline completed: Bronze->Silver (DQ), Silver->Gold, Athena KPI query, and dashboard/report generation finished successfully."
        }
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }
        ]
        End = true
      }
    }
  })
}
