output "ingest_job_name" { value = aws_glue_job.ingest.name }
output "silver_job_name" { value = aws_glue_job.silver.name }
output "gold_job_name" { value = aws_glue_job.gold.name }
output "visualization_job_name" { value = aws_glue_job.visualizations.name }

output "crawler_names" {
	value = {
		bronze = aws_glue_crawler.bronze.name
		silver = aws_glue_crawler.silver.name
		gold   = aws_glue_crawler.gold.name
	}
}
