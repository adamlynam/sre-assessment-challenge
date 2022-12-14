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
  name = "${var.application_name}-${var.service_name}-codepipeline_policy"
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
        "${aws_s3_bucket.codepipeline_artifacts.arn}",
        "${aws_s3_bucket.codepipeline_artifacts.arn}/*",
        "${aws_s3_bucket.codepipeline_imagedefinitions.arn}",
        "${aws_s3_bucket.codepipeline_imagedefinitions.arn}/*"
      ]
    },
    {
      "Effect":"Allow",
      "Action": [
        "ecr:DescribeImages"
      ],
      "Resource": [
        "${var.repository_arn}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "codepipeline-role-policy-attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

### Role for CloudWatch Event

resource "aws_iam_role" "cloudwatch_event_role" {
  name               = "${var.application_name}-${var.service_name}-cloudwatch-event-role"
  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": ["events.amazonaws.com"]
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "cloudwatch_event_role_policy" {
  name = "${var.application_name}-${var.service_name}-cloudwatch-event-policy"
  role = aws_iam_role.cloudwatch_event_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
        "Effect": "Allow",
        "Action": [
            "codepipeline:StartPipelineExecution"
        ],
        "Resource": [
            "${aws_codepipeline.main.arn}"
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
    location = aws_s3_bucket.codepipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "NewImage"

    action {
      name             = "NewImage"
      category         = "Source"
      owner            = "AWS"
      provider         = "ECR"
      version          = "1"
      output_artifacts = ["image_output"]

      configuration = {
        RepositoryName = var.repository_name
        ImageTag       = "latest"
      }
    }

    action {
      name             = "ImageDefinitions"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["imagedefinitions_output"]

      configuration = {
        S3Bucket    = aws_s3_bucket.codepipeline_imagedefinitions.bucket
        S3ObjectKey = "imagedefinitions"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["imagedefinitions_output"]
      version         = "1"

      configuration = {
        ClusterName = var.cluster_name
        ServiceName = aws_ecs_service.main.name
      }
    }
  }
}

## CloudWatch Event

# due to a limitation in the CodePipeline module we need to define an event to monitor ECR ourselves

resource "aws_cloudwatch_event_rule" "image_push" {
  name     = "${var.application_name}-${var.service_name}-ecr-image-push"
  role_arn = aws_iam_role.cloudwatch_event_role.arn

  event_pattern = <<EOF
{
  "source": [
    "aws.ecr"
  ],
  "detail": {
    "action-type": [
      "PUSH"
    ],
    "image-tag": [
      "latest"
    ],
    "repository-name": [
      "${var.repository_name}"
    ],
    "result": [
      "SUCCESS"
    ]
  },
  "detail-type": [
    "ECR Image Action"
  ]
}
EOF
}

resource "aws_cloudwatch_event_target" "codepipeline" {
  rule     = aws_cloudwatch_event_rule.image_push.name
  arn      = aws_codepipeline.main.arn
  role_arn = aws_iam_role.cloudwatch_event_role.arn
}

## S3

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "${var.application_name}-${var.service_name}-codepipeline-artifacts"
}

resource "aws_s3_bucket" "codepipeline_imagedefinitions" {
  bucket = "${var.application_name}-${var.service_name}-codepipeline-imagedefinitions"
}

# an s3 bucket must be versioned to act as a codepipeline source
resource "aws_s3_bucket_versioning" "codepipeline_imagedefinitions_versioning" {
  bucket = aws_s3_bucket.codepipeline_imagedefinitions.id
  versioning_configuration {
    status = "Enabled"
  }
}

# we populate this s3 bucket with an imagedefinitions.json file for the deploy to ECS
data "archive_file" "imagedefinitions_json_zip" {
  type                    = "zip"
  source_content_filename = "imagedefinitions.json"
  source_content = templatefile("${path.module}/imagedefinitions.json", {
    image_url      = "${var.repository_url}:${var.image_tag}"
    container_name = var.service_name
  })
  output_path = "${path.module}/files/${var.service_name}/imagedefinitions.zip"
}

resource "aws_s3_object" "imagedefinitions_json" {
  bucket = aws_s3_bucket.codepipeline_imagedefinitions.bucket
  key    = "imagedefinitions"
  source = data.archive_file.imagedefinitions_json_zip.output_path
}

## CloudWatch Logs

resource "aws_cloudwatch_log_group" "app" {
  name = "${var.application_name}-ecs-group/${var.service_name}"
}
