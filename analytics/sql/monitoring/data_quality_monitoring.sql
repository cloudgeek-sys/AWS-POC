CREATE OR REPLACE VIEW vw_data_quality_monitoring AS
SELECT
  run_timestamp,
  dataset,
  input_rows,
  valid_rows,
  malformed_rows,
  null_issues,
  range_issues
FROM silver_quality_report;
