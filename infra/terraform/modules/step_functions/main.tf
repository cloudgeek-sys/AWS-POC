locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "aws_sfn_state_machine" "pipeline" {
  name     = "${local.name_prefix}-power-pipeline"
  role_arn = var.step_functions_role_arn

  definition = jsonencode({
    Comment = "Global Power Plant Analytics orchestration"
    StartAt = "BronzeIngestion"
    States = {
      BronzeIngestion = {
        Type = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.ingest_job_name
        }
        Next = "SilverTransform"
      }
      SilverTransform = {
        Type = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.silver_job_name
        }
        Next = "GoldBuild"
      }
      GoldBuild = {
        Type = "Task"
        Resource = "arn:aws:states:::glue:startJobRun.sync"
        Parameters = {
          JobName = var.gold_job_name
        }
        End = true
      }
    }
  })
}
