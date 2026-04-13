variable "aws_region" {
  description = "AWS region to deploy all resources"
  type        = string
  default     = "eu-central-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  type        = string
  default     = "photo-gallery-images"
}

variable "table_name" {
  description = "Name of the DynamoDB table for image metadata"
  type        = string
  default     = "photo-metadata"
}

variable "collection_name" {
  description = "Name of the OpenSearch Serverless collection"
  type        = string
  default     = "photo-gallery"
}
