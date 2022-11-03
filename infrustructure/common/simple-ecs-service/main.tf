resource "aws_ecs_task_definition" "clearpoint_todo" {
  family = "clearpoint_todo_app"

  container_definitions = templatefile("${path.module}/task-definition.json", {
    image_url        = var.image_url
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
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.clearpoint_todo.arn
  desired_count   = var.service_desired

  load_balancer {
    target_group_arn = aws_alb_target_group.main.id
    container_name   = "clearpoint_todo_frontend"
    container_port   = "80"
  }

  # Fargate requires some extra configuration to be set for networking tasks
  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_groups
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

resource "aws_alb_target_group" "main" {
  name        = "clearpoint-todo-ecs"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
}

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "app" {
  name = "clearpoint-todo-ecs-group/app"
}
