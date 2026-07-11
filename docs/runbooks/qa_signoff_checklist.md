# QA Environment Sign-Off Checklist

## 1. Sign-off summary

This checklist records QA deployment readiness and runtime validation status for the Global Power Plant Analytics Pipeline.

Current verdict: **TBD**

---

## 2. Execution proof

## Latest Step Functions status

- State machine: `gppa-qa-power-pipeline`
- Latest execution: `TBD`
- Status: `TBD`

## Historical context

- Record any failed runs and remediation notes before final pass.

---

## 3. Infrastructure validation

## Terraform

- QA stack applied successfully: `TBD`
- Key outputs present:
  - `athena_workgroup`
  - `data_lake_bucket`
  - `step_function_arn`
  - `glue_jobs`

## Resources verified

- S3 bucket exists and reachable: `TBD`
- Glue jobs exist: `TBD`
- Step Functions state machine exists: `TBD`
- Athena workgroup exists: `TBD`
- CloudWatch alarms exist:
  - `gppa-qa-dq-failures`
  - `gppa-qa-freshness-lag`

---

## 4. Data layer validation

S3 data outputs verified for all layers:

- `bronze/`: `TBD`
- `silver/`: `TBD`
- `gold/`: `TBD`
- `quarantine/`: `TBD`
- `audit/`: `TBD`

## Audit evidence verified

- `audit/bronze_run_report.csv`: `TBD`
- `audit/checkpoints.json`: `TBD`
- `audit/metrics.csv`: `TBD`
- `audit/silver_quality_report.csv`: `TBD`

Quality sample captured:

- `input_rows`: `TBD`
- `valid_rows`: `TBD`
- `malformed_rows`: `TBD`

---

## 5. Functional validation

## Local/CI regression checks

- `pytest`: `TBD`
- dbt run/test: `TBD`
- CI workflows green: `TBD`

## Cloud runtime checks

- End-to-end Step Functions execution reached `SUCCEEDED`: `TBD`
- Bronze -> Silver -> Gold progression validated: `TBD`

---

## 6. Analytics readiness

Artifacts and checks:

- Athena DDL executed: `TBD`
- Gold dashboard views query successfully: `TBD`
- Monitoring view query succeeds: `TBD`

Reference files:

- `analytics/sql/athena/athena_full_dataset_ddl.sql`
- `analytics/sql/gold_views/power_generation_dashboard.sql`
- `analytics/sql/gold_views/plant_operations_dashboard.sql`
- `analytics/sql/monitoring/data_quality_monitoring.sql`

---

## 7. Alerting and operations

- CloudWatch alarms configured: `TBD`
- SNS/notification actions attached: `TBD`
- Runbook validation completed: `TBD`

---

## 8. PROD promotion gate

Promote to PROD only when all are true:

- QA latest execution is `SUCCEEDED`
- QA layer outputs and audit artifacts exist
- Quality metrics are within expected thresholds
- Athena sanity checks pass
- CI checks are green
- No open critical defects

---

## 9. Command log (fill during QA validation)

- Terraform apply command and output link: `TBD`
- Glue code upload command and output link: `TBD`
- Step Functions execution command and ARN: `TBD`
- S3 validation commands and snapshots: `TBD`
- Athena sanity query outputs: `TBD`

---

## 10. Final QA approval

- QA Owner: `TBD`
- Date: `TBD`
- Decision: `TBD`
- Notes: `TBD`
