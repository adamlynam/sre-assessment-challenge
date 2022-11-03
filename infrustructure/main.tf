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
  name   = "tf-ecs-lbsg"

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
  name = "terraform_example_ecs_cluster"
}

resource "aws_ecs_task_definition" "clearpoint_todo" {
  family = "clearpoint_todo_app"

  container_definitions = templatefile("${path.module}/task-definition.json", {
    image_url        = "${aws_ecr_repository.frontend.repository_url}:latest"
    container_name   = "clearpoint_todo_frontend"
    log_group_region = var.aws_region
    log_group_name   = aws_cloudwatch_log_group.app.name
    log_group_prefix = "clearpoint_todo_frontend"
  })

  # Fargate requires some extra configuration to be set to manage running tasks
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
}

resource "aws_ecs_service" "clearpoint-todo" {
  name            = "clearpoint-todo-ecs"
  launch_type     = "FARGATE"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.clearpoint_todo.arn
  desired_count   = var.service_desired

  load_balancer {
    target_group_arn = aws_alb_target_group.test.id
    container_name   = "clearpoint_todo_frontend"
    container_port   = "80"
  }

  depends_on = [
    aws_alb_listener.front_end,
  ]

  # Fargate requires some extra configuration to be set for networking tasks
  network_configuration {
    subnets          = aws_subnet.main[*].id
    security_groups  = [aws_security_group.lb_sg.id]
    assign_public_ip = true
  }
}

## IAM

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

## ALB

resource "aws_alb_target_group" "test" {
  name        = "clearpoint-todo-ecs"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
}

resource "aws_alb" "main" {
  name            = "tf-example-alb-ecs"
  subnets         = aws_subnet.main[*].id
  security_groups = [aws_security_group.lb_sg.id]
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.test.id
    type             = "forward"
  }
}

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "ecs" {
  name = "tf-ecs-group/ecs-agent"
}

resource "aws_cloudwatch_log_group" "app" {
  name = "tf-ecs-group/app-clearpoint-todo"
}
