locals {
  name_prefix = "${var.project_name}-${var.environment}"
  dataset_permission_principals = distinct(compact(concat(
    var.quicksight_user_arn != null && var.quicksight_user_arn != "" ? [var.quicksight_user_arn] : [],
    var.quicksight_dataset_principal_arns
  )))

  dataset_specs = {
    power_generation_country_capacity = {
      view_name = "vw_power_generation_country_capacity"
      columns = [
        { name = "country", type = "STRING" },
        { name = "total_capacity_mw", type = "DECIMAL" },
        { name = "renewable_capacity_mw", type = "DECIMAL" },
        { name = "non_renewable_capacity_mw", type = "DECIMAL" }
      ]
    }
    power_generation_fuel_distribution = {
      view_name = "vw_power_generation_fuel_distribution"
      columns = [
        { name = "country", type = "STRING" },
        { name = "primary_fuel", type = "STRING" },
        { name = "total_generation_gwh", type = "DECIMAL" }
      ]
    }
    power_generation_renewable_trends = {
      view_name = "vw_power_generation_renewable_trend"
      columns = [
        { name = "year", type = "INTEGER" },
        { name = "country", type = "STRING" },
        { name = "renewable_generation_gwh", type = "DECIMAL" },
        { name = "non_renewable_generation_gwh", type = "DECIMAL" },
        { name = "renewable_generation_ratio", type = "DECIMAL" }
      ]
    }
    plant_largest_plants = {
      view_name = "vw_plant_operations_largest_plants"
      columns = [
        { name = "plant_id", type = "STRING" },
        { name = "plant_name", type = "STRING" },
        { name = "country", type = "STRING" },
        { name = "primary_fuel", type = "STRING" },
        { name = "capacity_mw", type = "DECIMAL" },
        { name = "commissioning_year", type = "INTEGER" },
        { name = "latitude", type = "DECIMAL" },
        { name = "longitude", type = "DECIMAL" }
      ]
    }
    plant_aging_plants = {
      view_name = "vw_plant_operations_aging_infrastructure"
      columns = [
        { name = "country", type = "STRING" },
        { name = "primary_fuel", type = "STRING" },
        { name = "plant_count", type = "INTEGER" },
        { name = "avg_commissioning_year", type = "DECIMAL" },
        { name = "aging_30_plus_count", type = "INTEGER" },
        { name = "aging_40_plus_count", type = "INTEGER" }
      ]
    }
    plant_utilization = {
      view_name = "vw_plant_operations_capacity_utilization"
      columns = [
        { name = "year", type = "INTEGER" },
        { name = "country", type = "STRING" },
        { name = "primary_fuel", type = "STRING" },
        { name = "total_capacity_mw", type = "DECIMAL" },
        { name = "total_generation_gwh", type = "DECIMAL" },
        { name = "theoretical_max_generation_gwh", type = "DECIMAL" },
        { name = "utilization_ratio", type = "DECIMAL" }
      ]
    }
    sustainability_heatmap = {
      view_name = "vw_sustainability_heatmap"
      columns = [
        { name = "plant_id", type = "STRING" },
        { name = "plant_name", type = "STRING" },
        { name = "country", type = "STRING" },
        { name = "latitude", type = "DECIMAL" },
        { name = "longitude", type = "DECIMAL" },
        { name = "capacity_mw", type = "DECIMAL" },
        { name = "primary_fuel", type = "STRING" }
      ]
    }
    sustainability_country_distribution = {
      view_name = "vw_sustainability_country_distribution"
      columns = [
        { name = "country", type = "STRING" },
        { name = "plant_count", type = "INTEGER" },
        { name = "total_capacity_mw", type = "DECIMAL" },
        { name = "avg_capacity_mw", type = "DECIMAL" }
      ]
    }
    sustainability_regional_density = {
      view_name = "vw_sustainability_regional_density"
      columns = [
        { name = "continent", type = "STRING" },
        { name = "sub_region", type = "STRING" },
        { name = "total_capacity_mw", type = "DECIMAL" }
      ]
    }
    sustainability_clean_energy_growth = {
      view_name = "vw_sustainability_clean_energy_growth"
      columns = [
        { name = "year", type = "INTEGER" },
        { name = "continent", type = "STRING" },
        { name = "sub_region", type = "STRING" },
        { name = "country", type = "STRING" },
        { name = "renewable_generation_gwh", type = "DECIMAL" },
        { name = "non_renewable_generation_gwh", type = "DECIMAL" }
      ]
    }
    sustainability_coal_dependency = {
      view_name = "vw_sustainability_coal_dependency"
      columns = [
        { name = "continent", type = "STRING" },
        { name = "sub_region", type = "STRING" },
        { name = "coal_capacity_mw", type = "DECIMAL" },
        { name = "total_capacity_mw", type = "DECIMAL" },
        { name = "coal_capacity_ratio", type = "DECIMAL" }
      ]
    }
    geographic_generation_density = {
      view_name = "vw_geographic_generation_density"
      columns = [
        { name = "country", type = "STRING" },
        { name = "plant_count", type = "INTEGER" },
        { name = "total_capacity_mw", type = "DECIMAL" },
        { name = "total_generation_gwh", type = "DECIMAL" },
        { name = "generation_per_plant_gwh", type = "DECIMAL" }
      ]
    }
    geographic_country_infrastructure_density = {
      view_name = "vw_geographic_country_infrastructure_density"
      columns = [
        { name = "country", type = "STRING" },
        { name = "plant_count", type = "INTEGER" },
        { name = "total_capacity_mw", type = "DECIMAL" },
        { name = "plants_per_1000_mw", type = "DECIMAL" }
      ]
    }
    monitoring_pipeline_freshness = {
      view_name = "vw_monitoring_pipeline_freshness"
      columns = [
        { name = "source_name", type = "STRING" },
        { name = "latest_ingested_at", type = "DATETIME" },
        { name = "lag_hours", type = "INTEGER" }
      ]
    }
    monitoring_failed_jobs = {
      view_name = "vw_monitoring_failed_jobs"
      columns = [
        { name = "metric_date", type = "DATETIME" },
        { name = "metric_name", type = "STRING" },
        { name = "failure_count", type = "DECIMAL" }
      ]
    }
    monitoring_data_quality = {
      view_name = "vw_monitoring_data_quality"
      columns = [
        { name = "run_timestamp", type = "DATETIME" },
        { name = "dataset", type = "STRING" },
        { name = "input_rows", type = "INTEGER" },
        { name = "valid_rows", type = "INTEGER" },
        { name = "malformed_rows", type = "INTEGER" },
        { name = "null_issues", type = "INTEGER" },
        { name = "range_issues", type = "INTEGER" },
        { name = "valid_ratio", type = "DECIMAL" }
      ]
    }
    monitoring_latency = {
      view_name = "vw_monitoring_latency"
      columns = [
        { name = "bronze_completed_at", type = "DATETIME" },
        { name = "silver_completed_at", type = "DATETIME" },
        { name = "gold_completed_at", type = "DATETIME" },
        { name = "visualizations_completed_at", type = "DATETIME" },
        { name = "bronze_to_silver_minutes", type = "INTEGER" },
        { name = "silver_to_gold_minutes", type = "INTEGER" },
        { name = "gold_to_viz_minutes", type = "INTEGER" }
      ]
    }
  }

  dashboard_dataset_keys = {
    power_generation = [
      "power_generation_country_capacity",
      "power_generation_fuel_distribution",
      "power_generation_renewable_trends"
    ]
    plant = [
      "plant_largest_plants",
      "plant_aging_plants",
      "plant_utilization"
    ]
    sustainability = [
      "sustainability_heatmap",
      "sustainability_country_distribution",
      "sustainability_regional_density",
      "sustainability_clean_energy_growth",
      "sustainability_coal_dependency"
    ]
    geographic = [
      "sustainability_heatmap",
      "geographic_country_infrastructure_density",
      "geographic_generation_density"
    ]
    monitoring = [
      "monitoring_pipeline_freshness",
      "monitoring_failed_jobs",
      "monitoring_data_quality",
      "monitoring_latency"
    ]
  }
}

data "aws_caller_identity" "current" {}

resource "aws_quicksight_data_source" "athena" {
  count = var.enable_quicksight ? 1 : 0

  aws_account_id = data.aws_caller_identity.current.account_id
  data_source_id = "${replace(local.name_prefix, "-", "_")}_athena"
  name           = "${local.name_prefix}-athena"
  type           = "ATHENA"

  parameters {
    athena {
      work_group = var.athena_workgroup_name
    }
  }

  dynamic "permission" {
    for_each = local.dataset_permission_principals

    content {
      principal = permission.value
      actions = [
        "quicksight:DescribeDataSource",
        "quicksight:DescribeDataSourcePermissions",
        "quicksight:PassDataSource",
        "quicksight:UpdateDataSource",
        "quicksight:DeleteDataSource",
        "quicksight:UpdateDataSourcePermissions"
      ]
    }
  }
}

resource "aws_quicksight_data_set" "dashboard" {
  for_each = var.enable_quicksight && var.enable_quicksight_datasets ? local.dataset_specs : {}

  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "${replace(local.name_prefix, "-", "_")}_${each.key}_ds"
  name           = "${local.name_prefix}-${each.key}-dataset"
  import_mode    = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = replace(each.key, "_", "-")

    relational_table {
      data_source_arn = aws_quicksight_data_source.athena[0].arn
      catalog         = "AwsDataCatalog"
      schema          = var.athena_database_name
      name            = each.value.view_name

      dynamic "input_columns" {
        for_each = each.value.columns

        content {
          name = input_columns.value.name
          type = input_columns.value.type
        }
      }
    }
  }

  dynamic "permissions" {
    for_each = local.dataset_permission_principals

    content {
      principal = permissions.value
      actions = [
        "quicksight:DescribeDataSet",
        "quicksight:DescribeDataSetPermissions",
        "quicksight:PassDataSet",
        "quicksight:DescribeIngestion",
        "quicksight:ListIngestions",
        "quicksight:UpdateDataSet",
        "quicksight:DeleteDataSet",
        "quicksight:CreateIngestion",
        "quicksight:CancelIngestion",
        "quicksight:UpdateDataSetPermissions"
      ]
    }
  }
}

resource "aws_quicksight_dashboard" "dashboard" {
  for_each = var.enable_quicksight && var.enable_quicksight_dashboards ? {
    for k, v in var.quicksight_dashboard_templates : k => v if contains(keys(local.dashboard_dataset_keys), k)
  } : {}

  aws_account_id      = data.aws_caller_identity.current.account_id
  dashboard_id        = "${replace(local.name_prefix, "-", "_")}_${each.key}_dashboard"
  name                = "${local.name_prefix}-${replace(each.key, "_", "-")}-dashboard"
  version_description = "Managed by Terraform"

  source_entity {
    source_template {
      arn = each.value.template_arn

      dynamic "data_set_references" {
        for_each = each.value.data_set_placeholders

        content {
          data_set_arn         = aws_quicksight_data_set.dashboard[data_set_references.key].arn
          data_set_placeholder = data_set_references.value
        }
      }
    }
  }
}
