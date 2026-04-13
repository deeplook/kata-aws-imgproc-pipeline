output "lambda_function_name" {
  description = "Name of the search Lambda function"
  value       = aws_lambda_function.search.function_name
}

output "lambda_function_arn" {
  description = "ARN of the search Lambda function"
  value       = aws_lambda_function.search.arn
}

output "api_url" {
  description = "Base URL of the API Gateway HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}
