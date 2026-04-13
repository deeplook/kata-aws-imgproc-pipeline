variable "bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  type        = string
}

variable "table_name" {
  description = "Name of the DynamoDB table for image metadata"
  type        = string
}
