## ECS

resource "aws_ecs_task_definition" "main" {
  family = var.application_name

  container_definitions = templatefile("${path.module}/task-definition.json", {
    image_url        = "${var.repository_url}:${var.image_tag}"
    container_name   = var.service_name
    log_group_region = var.aws_region
    log_group_name   = aws_cloudwatch_log_group.app.name
    log_group_prefix = var.service_name
  })

  # Fargate requires some extra configuration to be set to manage running tasks
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
}

resource "aws_ecs_service" "main" {
  name            = var.service_name
  launch_type     = "FARGATE"
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.service_desired_normal

  load_balancer {
    target_group_arn = aws_alb_target_group.main.id
    container_name   = var.service_name
    container_port   = "80"
  }

  # Fargate requires some extra configuration to be set for networking tasks
  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_groups
    assign_public_ip = true
  }

  # with auto scaling configured, we need to let Terraform know that the desired count should only be set on creation
  lifecycle {
    ignore_changes = [desired_count]
  }
}

### Autoscaling for ECS

resource "aws_appautoscaling_target" "main" {
  max_capacity       = var.service_desired_max
  min_capacity       = var.service_desired_normal
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu_scaling" {
  name               = "${var.application_name}-${var.service_name}-80%-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main.resource_id
  scalable_dimension = aws_appautoscaling_target.main.scalable_dimension
  service_namespace  = aws_appautoscaling_target.main.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = 80 # this value should be informed by load testing, it is currently arbi
  }
}

## IAM

### Role for task exectuion

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.application_name}-${var.service_name}-ecsTaskExecutionRole"

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

### Role for CodePipeline

resource "aws_iam_role" "codepipeline_role" {
  name = "${var.application_name}-${var.service_name}-codePipelineRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning",
        "s3:PutObjectAcl",
        "s3:PutObject"
      ],
      "Resource": [
        "${aws_s3_bucket.codepipeline_bucket.arn}",
        "${aws_s3_bucket.codepipeline_bucket.arn}/*"
      ]
    }
  ]
}
EOF
}

## ALB

resource "aws_alb_target_group" "main" {
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
}

## CodePipeline

resource "aws_codepipeline" "main" {
  name     = "${var.application_name}-${var.service_name}-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Image Pushed"

    action {
      name             = "Image Pushed"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = var.repository_url
        ImageTag       = "latest"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name     = "Restart Service"
      category = "Deploy"
      owner    = "AWS"
      provider = "ECS"
      version  = "1"

      configuration = {
        ClusterName = var.cluster_name
        ServiceName = aws_ecs_service.main.name
      }
    }
  }
}

## S3

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "${var.application_name}-${var.service_name}-codepipeline-artifacts"
}

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "app" {
  name = "${var.application_name}-ecs-group/${var.service_name}"
}
