terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

## ECS

resource "aws_ecs_cluster" "main" {
  name = "sre_assessment"
}
