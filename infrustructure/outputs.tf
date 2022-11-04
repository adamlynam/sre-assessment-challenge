output "elb_hostname" {
  value = aws_alb.main.dns_name
}

output "frontend_registry_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "backend_registry_url" {
  value = aws_ecr_repository.backend.repository_url
}
