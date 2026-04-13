output "gallery_url" {
  description = "Public HTTPS URL of the App Runner gallery service"
  value       = "https://${aws_apprunner_service.gallery.service_url}"
}

output "ecr_repository_url" {
  description = "ECR repository URL for the gallery Docker image"
  value       = aws_ecr_repository.gallery.repository_url
}
