terraform {
  required_version = ">= 0.12"
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

## EC2

### Network

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
}

resource "aws_subnet" "main" {
  count             = var.az_count
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  vpc_id            = aws_vpc.main.id
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "r" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  count          = var.az_count
  subnet_id      = element(aws_subnet.main[*].id, count.index)
  route_table_id = aws_route_table.r.id
}

### Security

resource "aws_security_group" "lb_sg" {
  description = "controls access to the application ELB"

  vpc_id = aws_vpc.main.id
  name   = "clearpoint-todo-ecs-lbsg"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

## ECR

resource "aws_ecr_repository" "frontend" {
  name = "clearpoint-todo-frontend"

  # this ensure that we can update existing tags once they are created, this will be key to updating the "latest" tagged image to drive deployment automation
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "backend" {
  name = "clearpoint-todo-backend"

  # this ensure that we can update existing tags once they are created, this will be key to updating the "latest" tagged image to drive deployment automation
  image_tag_mutability = "MUTABLE"
}

## ECS

resource "aws_ecs_cluster" "main" {
  name = "clearpoint_todo_ecs_cluster"
}

### ECS Services

module "frontend_ecs_service" {
  source = "./common/simple-ecs-service"

  aws_region = var.aws_region

  application_name = "clearpoint_todo"
  service_name     = "frontend"

  image_url       = "${aws_ecr_repository.frontend.repository_url}:latest"
  cluster_id      = aws_ecs_cluster.main.id
  cluster_name    = aws_ecs_cluster.main.name
  vpc_id          = aws_vpc.main.id
  subnets         = aws_subnet.main[*].id
  security_groups = [aws_security_group.lb_sg.id]
}

module "backend_ecs_service" {
  source = "./common/simple-ecs-service"

  aws_region = var.aws_region

  application_name = "clearpoint_todo"
  service_name     = "backend"

  image_url       = "${aws_ecr_repository.backend.repository_url}:latest"
  cluster_id      = aws_ecs_cluster.main.id
  cluster_name    = aws_ecs_cluster.main.name
  vpc_id          = aws_vpc.main.id
  subnets         = aws_subnet.main[*].id
  security_groups = [aws_security_group.lb_sg.id]
}


## ALB

resource "aws_alb" "main" {
  name            = "clearpoint-todo-alb-ecs"
  subnets         = aws_subnet.main[*].id
  security_groups = [aws_security_group.lb_sg.id]
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = module.frontend_ecs_service.target_group_id
    type             = "forward"
  }
}

resource "aws_alb_listener_rule" "backend" {
  listener_arn = aws_alb_listener.front_end.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = module.backend_ecs_service.target_group_id
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
