variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "ap-southeast-2"
}

variable "image_url" {
  description = "The URL to pull the source image for the task from."
}

variable "cluster_id" {
  description = "The ECS cluster id to attach the ECS service to."
}

variable "service_desired" {
  description = "Desired numbers of instances in the ecs service"
  default     = "1"
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
