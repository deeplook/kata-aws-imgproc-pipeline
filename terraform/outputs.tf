output "s3_bucket_name" {
  description = "Name of the S3 image upload bucket"
  value       = module.storage.s3_bucket_name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB metadata table"
  value       = module.storage.dynamodb_table_name
}

output "ingest_lambda_name" {
  description = "Name of the ingest Lambda function"
  value       = module.ingestion.lambda_function_name
}

output "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = module.ingestion.opensearch_endpoint
}

output "search_lambda_name" {
  description = "Name of the search Lambda function"
  value       = module.search.lambda_function_name
}

output "api_url" {
  description = "Base URL of the API Gateway HTTP API"
  value       = module.search.api_url
}

# TODO Stage 8: uncomment after adding the frontend module to main.tf
# output "gallery_url" {
#   description = "Public HTTPS URL of the App Runner gallery web app"
#   value       = module.frontend.gallery_url
# }
