variable "aws_region" {
  description = "The AWS region to create things in."
}

variable "application_name" {
  description = "The name of the shared application this service is part of."
}

variable "service_name" {
  description = "The name of the component this service represents."
}

variable "repository_arn" {
  description = "The ARN of the repository to pull the source image for the task from."
}

variable "repository_url" {
  description = "The URL of the repository to pull the source image for the task from."
}

variable "repository_name" {
  description = "The name of the repository to pull the source image for the task from."
}

variable "image_tag" {
  description = "The image tag to pull the source image for the task from."
}

variable "cluster_id" {
  description = "The ECS cluster id to attach the ECS service to."
}

variable "cluster_name" {
  description = "The ECS cluster name to attach the ECS service to."
}

variable "service_desired_normal" {
  description = "Desired numbers of instances in the ecs service at idle load"
  default     = "2" # we default to two tasks to ensure the service is resilient to individual task failures
}

variable "service_desired_max" {
  description = "Desired numbers of instances in the ecs service at high load"
  default     = "10"
}

variable "vpc_id" {
  description = "The VPC id to attach the services target group to."
}

variable "subnets" {
  description = "The subnets to allocate IP addresses to tasks from."
}

variable "security_groups" {
  description = "The security groups to apply to tasks in the service."
}
