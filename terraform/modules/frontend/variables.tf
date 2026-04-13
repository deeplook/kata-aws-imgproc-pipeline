variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "collection_name" {
  description = "Collection name used as a prefix for resource names"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 image upload bucket"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 image upload bucket"
  type        = string
}

variable "search_api_url" {
  description = "Base URL of the API Gateway search endpoint"
  type        = string
}
