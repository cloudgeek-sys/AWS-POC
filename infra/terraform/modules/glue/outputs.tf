output "ingest_job_name" { value = aws_glue_job.ingest.name }
output "silver_job_name" { value = aws_glue_job.silver.name }
output "gold_job_name" { value = aws_glue_job.gold.name }
