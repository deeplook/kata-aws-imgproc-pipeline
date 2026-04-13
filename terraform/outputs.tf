output "s3_bucket_name" {
  value = module.storage.s3_bucket_name
}

output "dynamodb_table_name" {
  value = module.storage.dynamodb_table_name
}

output "ingest_lambda_name" {
  value = module.ingestion.lambda_function_name
}

output "opensearch_endpoint" {
  value = module.ingestion.opensearch_endpoint
}

output "search_lambda_name" {
  value = module.search.lambda_function_name
}

output "api_url" {
  value = module.search.api_url
}

output "gallery_url" {
  description = "Public HTTPS URL of the App Runner gallery web app"
  value       = module.frontend.gallery_url
}
