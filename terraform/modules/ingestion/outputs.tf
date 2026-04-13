output "lambda_function_name" {
  description = "Name of the ingest Lambda function"
  value       = aws_lambda_function.ingest.function_name
}

output "lambda_function_arn" {
  description = "ARN of the ingest Lambda function"
  value       = aws_lambda_function.ingest.arn
}

output "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint (https://...)"
  value       = aws_opensearchserverless_collection.gallery.collection_endpoint
}

output "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.gallery.arn
}
