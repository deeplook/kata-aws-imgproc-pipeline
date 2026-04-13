variable "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint (https://...)"
  type        = string
}

variable "collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  type        = string
}

variable "collection_name" {
  description = "Name of the OpenSearch Serverless collection"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
