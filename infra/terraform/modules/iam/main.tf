locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

locals {
  persona_roles = {
    data_engineer = "${local.name_prefix}-data-engineer-role"
    analyst       = "${local.name_prefix}-analyst-role"
    dashboard     = "${local.name_prefix}-dashboard-user-role"
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "${local.name_prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

data "aws_iam_policy_document" "glue_runtime" {
  statement {
    sid = "ListLakeBucket"

    actions = ["s3:ListBucket"]

    resources = [var.data_lake_bucket_arn]
  }

  statement {
    sid = "ReadWriteLakeObjects"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = ["${var.data_lake_bucket_arn}/*"]
  }

  statement {
    sid = "WriteGlueLogs"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"
    ]
  }

  statement {
    sid = "PublishPipelineMetrics"

    actions = ["cloudwatch:PutMetricData"]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["GPPA/Pipeline"]
    }
  }
}

resource "aws_iam_policy" "glue_runtime" {
  name   = "${local.name_prefix}-glue-runtime"
  policy = data.aws_iam_policy_document.glue_runtime.json
}

resource "aws_iam_role_policy_attachment" "glue_runtime" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_runtime.arn
}

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "step_functions_role" {
  name               = "${local.name_prefix}-sfn-role"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn_runtime" {
  statement {
    sid = "RunGlueJobs"

    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun"
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/${local.name_prefix}-*"
    ]
  }

  statement {
    sid = "GlueSyncRuleManagement"

    actions = [
      "events:PutTargets",
      "events:PutRule",
      "events:DescribeRule"
    ]

    resources = [
      "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/StepFunctionsGetEventsForGlueJobsRule"
    ]
  }

  statement {
    sid = "StepFunctionsCloudWatchLogs"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]

    resources = ["*"]
  }

  statement {
    sid = "StepFunctionsAthenaQueryExecution"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution"
    ]

    resources = ["*"]
  }

  statement {
    sid = "StepFunctionsSnsInsightsPublish"

    actions = [
      "sns:Publish"
    ]

    resources = [
      "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.name_prefix}-alarm-notifications"
    ]
  }
}

resource "aws_iam_policy" "sfn_runtime" {
  name   = "${local.name_prefix}-sfn-runtime"
  policy = data.aws_iam_policy_document.sfn_runtime.json
}

resource "aws_iam_role_policy_attachment" "sfn_runtime" {
  role       = aws_iam_role.step_functions_role.name
  policy_arn = aws_iam_policy.sfn_runtime.arn
}

data "aws_iam_policy_document" "terraform_deployer" {
  statement {
    sid = "S3LakeProvisioning"

    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:Get*",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:DeleteBucketLifecycle",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      var.data_lake_bucket_arn,
      "${var.data_lake_bucket_arn}/*"
    ]
  }

  statement {
    sid = "TerraformStateBucketAccess"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::tf-state-371170753734-us-east-1-an"
    ]
  }

  statement {
    sid = "TerraformStateObjectAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::tf-state-371170753734-us-east-1-an/*"
    ]
  }

  statement {
    sid = "S3GlobalRead"

    actions = ["s3:ListAllMyBuckets"]

    resources = ["*"]
  }

  statement {
    sid = "GlueResourceManagement"

    actions = [
      "glue:CreateJob",
      "glue:UpdateJob",
      "glue:DeleteJob",
      "glue:GetJob",
      "glue:GetJobs",
      "glue:CreateCrawler",
      "glue:UpdateCrawler",
      "glue:DeleteCrawler",
      "glue:GetCrawler",
      "glue:GetCrawlers",
      "glue:CreateDatabase",
      "glue:UpdateDatabase",
      "glue:DeleteDatabase",
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:TagResource",
      "glue:UntagResource",
      "glue:GetTags"
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/${local.name_prefix}-*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/${local.name_prefix}-*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${replace(local.name_prefix, "-", "_")}_*",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog"
    ]
  }

  statement {
    sid = "GlueCatalogAccessForAthenaDDL"

    actions = [
      "glue:GetTable",
      "glue:GetTables",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]

    resources = ["*"]
  }

  statement {
    sid = "StepFunctionsCreateAndValidate"

    actions = [
      "states:ValidateStateMachineDefinition",
      "states:CreateStateMachine"
    ]

    resources = ["*"]
  }

  statement {
    sid = "StepFunctionsManagement"

    actions = [
      "states:UpdateStateMachine",
      "states:ListStateMachineVersions",
      "states:DeleteStateMachine",
      "states:DescribeStateMachine",
      "states:TagResource",
      "states:UntagResource",
      "states:ListTagsForResource"
    ]

    resources = [
      "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.name_prefix}-*"
    ]
  }

  statement {
    sid = "CloudWatchAlarmManagement"

    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:EnableAlarmActions",
      "cloudwatch:DisableAlarmActions",
      "cloudwatch:SetAlarmState",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource"
    ]

    resources = [
      "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:${local.name_prefix}-*"
    ]
  }

  statement {
    sid = "AthenaWorkgroupManagement"

    actions = [
      "athena:CreateWorkGroup",
      "athena:UpdateWorkGroup",
      "athena:DeleteWorkGroup",
      "athena:GetWorkGroup",
      "athena:ListWorkGroups",
      "athena:TagResource",
      "athena:UntagResource",
      "athena:ListTagsForResource"
    ]

    resources = [
      "arn:aws:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/${local.name_prefix}-*"
    ]
  }

  statement {
    sid = "AthenaQueryExecution"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution"
    ]

    resources = ["*"]
  }

  statement {
    sid = "QuickSightAccountRead"

    actions = [
      "quicksight:CreateAccountSubscription",
      "quicksight:Subscribe",
      "quicksight:DescribeAccountSubscription",
      "quicksight:RegisterUser",
      "quicksight:DescribeUser",
      "quicksight:ListUsers",
      "quicksight:ListNamespaces"
    ]

    resources = ["*"]
  }

  statement {
    sid = "QuickSightDataSourceManagement"

    actions = [
      "quicksight:CreateDataSource",
      "quicksight:UpdateDataSource",
      "quicksight:DeleteDataSource",
      "quicksight:DescribeDataSource",
      "quicksight:DescribeDataSourcePermissions",
      "quicksight:UpdateDataSourcePermissions",
      "quicksight:ListDataSources",
      "quicksight:TagResource",
      "quicksight:UntagResource",
      "quicksight:ListTagsForResource",
      "quicksight:PassDataSource"
    ]

    resources = ["*"]
  }

  statement {
    sid = "QuickSightDataSetManagement"

    actions = [
      "quicksight:CreateDataSet",
      "quicksight:UpdateDataSet",
      "quicksight:DeleteDataSet",
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDataSetPermissions",
      "quicksight:DescribeDataSetRefreshProperties",
      "quicksight:UpdateDataSetPermissions",
      "quicksight:ListDataSets",
      "quicksight:TagResource",
      "quicksight:UntagResource",
      "quicksight:ListTagsForResource"
    ]

    resources = ["*"]
  }

  statement {
    sid = "QuickSightDashboardAndTemplateManagement"

    actions = [
      "quicksight:CreateDashboard",
      "quicksight:UpdateDashboard",
      "quicksight:DeleteDashboard",
      "quicksight:DescribeDashboard",
      "quicksight:DescribeDashboardPermissions",
      "quicksight:UpdateDashboardPermissions",
      "quicksight:ListDashboards",
      "quicksight:UpdateDashboardPublishedVersion",
      "quicksight:DescribeAnalysis",
      "quicksight:ListAnalyses",
      "quicksight:DescribeTemplate",
      "quicksight:ListTemplates"
    ]

    resources = ["*"]
  }

  statement {
    sid = "IamRoleAndPolicyManagementForProject"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:TagPolicy",
      "iam:UntagPolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:AttachUserPolicy",
      "iam:DetachUserPolicy",
      "iam:ListUserPolicies",
      "iam:GetUserPolicy",
      "iam:DeleteUserPolicy"
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${local.name_prefix}-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/*"
    ]
  }

  statement {
    sid = "PassOnlyProjectRolesToServices"

    actions = ["iam:PassRole"]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-*"
    ]

    condition {
      test     = "StringLike"
      variable = "iam:PassedToService"
      values = [
        "glue.amazonaws.com",
        "states.amazonaws.com"
      ]
    }
  }

  statement {
    sid = "IamListForTerraformRead"

    actions = [
      "iam:ListRoles",
      "iam:ListPolicies",
      "iam:ListAttachedUserPolicies"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_deployer" {
  count = var.deployer_policy_enabled ? 1 : 0

  name   = "${local.name_prefix}-terraform-deployer"
  policy = data.aws_iam_policy_document.terraform_deployer.json
}

resource "aws_iam_role_policy_attachment" "terraform_deployer_role_attachment" {
  count = var.deployer_policy_enabled && var.deployer_role_name != null ? 1 : 0

  role       = var.deployer_role_name
  policy_arn = aws_iam_policy.terraform_deployer[0].arn
}

resource "aws_iam_user_policy_attachment" "terraform_deployer_user_attachment" {
  count = var.deployer_policy_enabled && var.deployer_user_name != null ? 1 : 0

  user       = var.deployer_user_name
  policy_arn = aws_iam_policy.terraform_deployer[0].arn
}

data "aws_iam_policy_document" "terraform_logs_deployer" {
  statement {
    sid = "CloudWatchLogGroupDescribe"

    actions = [
      "logs:DescribeLogGroups"
    ]

    resources = ["*"]
  }

  statement {
    sid = "CloudWatchLogGroupManagement"

    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsForResource"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/jobs/${local.name_prefix}*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/vendedlogs/states/${local.name_prefix}*"
    ]
  }
}

resource "aws_iam_policy" "terraform_logs_deployer" {
  count = var.deployer_policy_enabled ? 1 : 0

  name   = "${local.name_prefix}-terraform-logs-deployer"
  policy = data.aws_iam_policy_document.terraform_logs_deployer.json
}

resource "aws_iam_role_policy_attachment" "terraform_logs_deployer_role_attachment" {
  count = var.deployer_policy_enabled && var.deployer_role_name != null ? 1 : 0

  role       = var.deployer_role_name
  policy_arn = aws_iam_policy.terraform_logs_deployer[0].arn
}

resource "aws_iam_user_policy_attachment" "terraform_logs_deployer_user_attachment" {
  count = var.deployer_policy_enabled && var.deployer_user_name != null ? 1 : 0

  user       = var.deployer_user_name
  policy_arn = aws_iam_policy.terraform_logs_deployer[0].arn
}

data "aws_iam_policy_document" "terraform_sns_deployer" {
  statement {
    sid = "SNSAlarmNotificationsManagement"

    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetSubscriptionAttributes",
      "sns:GetTopicAttributes",
      "sns:ListTagsForResource",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:ListSubscriptionsByTopic"
    ]

    resources = [
      "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.name_prefix}-*"
    ]
  }

  statement {
    sid = "SNSListTopics"

    actions = ["sns:ListTopics"]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_sns_deployer" {
  count = var.deployer_policy_enabled ? 1 : 0

  name   = "${local.name_prefix}-terraform-sns-deployer"
  policy = data.aws_iam_policy_document.terraform_sns_deployer.json
}

resource "aws_iam_role_policy_attachment" "terraform_sns_deployer_role_attachment" {
  count = var.deployer_policy_enabled && var.deployer_role_name != null ? 1 : 0

  role       = var.deployer_role_name
  policy_arn = aws_iam_policy.terraform_sns_deployer[0].arn
}

resource "aws_iam_user_policy_attachment" "terraform_sns_deployer_user_attachment" {
  count = var.deployer_policy_enabled && var.deployer_user_name != null ? 1 : 0

  user       = var.deployer_user_name
  policy_arn = aws_iam_policy.terraform_sns_deployer[0].arn
}

data "aws_iam_policy_document" "persona_assume_user" {
  count = var.deployer_user_name != null ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.deployer_user_name}"
      ]
    }
  }
}

resource "aws_iam_role" "persona" {
  for_each = var.deployer_user_name != null ? local.persona_roles : {}

  name               = each.value
  assume_role_policy = data.aws_iam_policy_document.persona_assume_user[0].json
}

data "aws_iam_policy_document" "persona_data_engineer" {
  statement {
    sid = "DataLakeReadWrite"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      var.data_lake_bucket_arn,
      "${var.data_lake_bucket_arn}/*"
    ]
  }

  statement {
    sid = "TerraformStateBucketAccess"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketLocation"
    ]

    resources = [
      "arn:aws:s3:::tf-state-371170753734-us-east-1-an"
    ]
  }

  statement {
    sid = "TerraformStateObjectAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "arn:aws:s3:::tf-state-371170753734-us-east-1-an/*"
    ]
  }

  statement {
    sid = "GluePipelineOps"

    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:GetJob",
      "glue:GetJobs"
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/${local.name_prefix}-*"
    ]
  }

  statement {
    sid = "OrchestrationOps"

    actions = [
      "states:StartExecution",
      "states:DescribeExecution",
      "states:ListExecutions",
      "states:DescribeStateMachine"
    ]

    resources = [
      "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${local.name_prefix}-*",
      "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:execution:${local.name_prefix}-*:*"
    ]
  }

  statement {
    sid = "AthenaQueryOps"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:ListQueryExecutions",
      "athena:GetWorkGroup"
    ]

    resources = ["*"]
  }

  statement {
    sid = "GlueCatalogReadForAthena"

    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions"
    ]

    resources = ["*"]
  }

  statement {
    sid = "GlueCatalogWriteForAthena"

    actions = [
      "glue:CreateDatabase",
      "glue:UpdateDatabase",
      "glue:DeleteDatabase",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:CreatePartition",
      "glue:UpdatePartition",
      "glue:DeletePartition"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "persona_analyst" {
  statement {
    sid = "AthenaReadQuery"

    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:ListQueryExecutions",
      "athena:GetWorkGroup"
    ]

    resources = ["*"]
  }

  statement {
    sid = "CatalogRead"

    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables"
    ]

    resources = ["*"]
  }

  statement {
    sid = "DataLakeReadOnly"

    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]

    resources = [
      var.data_lake_bucket_arn,
      "${var.data_lake_bucket_arn}/*"
    ]
  }

  statement {
    sid = "QuickSightAuthorRead"

    actions = [
      "quicksight:DescribeDataSet",
      "quicksight:DescribeDashboard",
      "quicksight:DescribeAnalysis",
      "quicksight:ListDataSets",
      "quicksight:ListDashboards",
      "quicksight:ListAnalyses"
    ]

    resources = ["*"]
  }
}

data "aws_iam_policy_document" "persona_dashboard_user" {
  statement {
    sid = "QuickSightDashboardAuthor"

    actions = [
      "quicksight:DescribeDashboard",
      "quicksight:ListDashboards",
      "quicksight:QueryDashboard",
      "quicksight:GenerateEmbedUrlForRegisteredUser",
      "quicksight:DescribeAnalysis",
      "quicksight:DescribeAnalysisDefinition",
      "quicksight:UpdateAnalysis",
      "quicksight:ListAnalyses",
      "quicksight:DescribeDataSet",
      "quicksight:PassDataSet",
      "quicksight:ListDataSets"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "persona_data_engineer" {
  count = var.deployer_user_name != null ? 1 : 0

  name   = "${local.name_prefix}-data-engineer-policy"
  policy = data.aws_iam_policy_document.persona_data_engineer.json
}

resource "aws_iam_policy" "persona_analyst" {
  count = var.deployer_user_name != null ? 1 : 0

  name   = "${local.name_prefix}-analyst-policy"
  policy = data.aws_iam_policy_document.persona_analyst.json
}

resource "aws_iam_policy" "persona_dashboard_user" {
  count = var.deployer_user_name != null ? 1 : 0

  name   = "${local.name_prefix}-dashboard-user-policy"
  policy = data.aws_iam_policy_document.persona_dashboard_user.json
}

resource "aws_iam_role_policy_attachment" "persona_data_engineer" {
  count = var.deployer_user_name != null ? 1 : 0

  role       = aws_iam_role.persona["data_engineer"].name
  policy_arn = aws_iam_policy.persona_data_engineer[0].arn
}

resource "aws_iam_role_policy_attachment" "persona_data_engineer_terraform_deployer" {
  count = var.deployer_user_name != null && var.deployer_policy_enabled ? 1 : 0

  role       = aws_iam_role.persona["data_engineer"].name
  policy_arn = aws_iam_policy.terraform_deployer[0].arn
}

resource "aws_iam_role_policy_attachment" "persona_data_engineer_terraform_logs_deployer" {
  count = var.deployer_user_name != null && var.deployer_policy_enabled ? 1 : 0

  role       = aws_iam_role.persona["data_engineer"].name
  policy_arn = aws_iam_policy.terraform_logs_deployer[0].arn
}

resource "aws_iam_role_policy_attachment" "persona_data_engineer_terraform_sns_deployer" {
  count = var.deployer_user_name != null && var.deployer_policy_enabled ? 1 : 0

  role       = aws_iam_role.persona["data_engineer"].name
  policy_arn = aws_iam_policy.terraform_sns_deployer[0].arn
}

resource "aws_iam_role_policy_attachment" "persona_analyst" {
  count = var.deployer_user_name != null ? 1 : 0

  role       = aws_iam_role.persona["analyst"].name
  policy_arn = aws_iam_policy.persona_analyst[0].arn
}

resource "aws_iam_role_policy_attachment" "persona_dashboard_user" {
  count = var.deployer_user_name != null ? 1 : 0

  role       = aws_iam_role.persona["dashboard"].name
  policy_arn = aws_iam_policy.persona_dashboard_user[0].arn
}

data "aws_iam_policy_document" "persona_assume_roles" {
  count = var.deployer_user_name != null ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    resources = [
      aws_iam_role.persona["data_engineer"].arn,
      aws_iam_role.persona["analyst"].arn,
      aws_iam_role.persona["dashboard"].arn
    ]
  }
}

resource "aws_iam_policy" "persona_assume_roles" {
  count = var.deployer_user_name != null ? 1 : 0

  name   = "${local.name_prefix}-persona-assume-roles"
  policy = data.aws_iam_policy_document.persona_assume_roles[0].json
}

resource "aws_iam_user_policy_attachment" "persona_assume_roles" {
  count = var.deployer_user_name != null ? 1 : 0

  user       = var.deployer_user_name
  policy_arn = aws_iam_policy.persona_assume_roles[0].arn
}
