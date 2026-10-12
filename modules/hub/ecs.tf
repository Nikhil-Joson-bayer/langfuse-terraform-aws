# -----------------------------------------------------------------------------
# CloudWatch Logs for ECS
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-ecs-logs"
    }
  )
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-cluster"
    }
  )
}

# -----------------------------------------------------------------------------
# ECS Task Definition (Fargate: langfuse-web + langfuse-worker)
# -----------------------------------------------------------------------------
locals {
  # Base environment variables shared across web and worker
  common_container_env = concat(
    [
      { name = "NODE_ENV", value = "production" },
      { name = "PORT", value = tostring(var.port) },
      { name = "NEXTAUTH_URL", value = local.effective_web_url },
      { name = "LANGFUSE_ENABLE_EXPERIMENTAL_FEATURES", value = "true" },
      { name = "LANGFUSE_S3_EVENT_UPLOAD_BUCKET", value = aws_s3_bucket.events.id },
      { name = "LANGFUSE_S3_EVENT_UPLOAD_REGION", value = data.aws_region.current.name },
      { name = "TELEMETRY_ENABLED", value = "false" }
    ],
    local.clickhouse_enabled ? [
      { name = "CLICKHOUSE_URL", value = local.clickhouse_http_url },
      { name = "CLICKHOUSE_MIGRATION_URL", value = local.clickhouse_migration_url },
      { name = "CLICKHOUSE_USER", value = var.clickhouse_user },
      { name = "CLICKHOUSE_DB", value = var.clickhouse_db },
      { name = "CLICKHOUSE_CLUSTER_ENABLED", value = "false" }
    ] : []
  )

  # Secrets from AWS Secrets Manager
  common_container_secrets = concat(
    [
      {
        name      = "DATABASE_URL"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:database_url::"
      },
      {
        name      = "REDIS_URL"
        valueFrom = "${aws_secretsmanager_secret.redis_credentials.arn}:redis_url::"
      },
      {
        name      = "NEXTAUTH_SECRET"
        valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:nextauth_secret::"
      },
      {
        name      = "SALT"
        valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:salt::"
      },
      {
        name      = "ENCRYPTION_KEY"
        valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:langfuse_encryption_key::"
      },
      {
        name      = "LANGFUSE_ENCRYPTION_KEY"
        valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:langfuse_encryption_key::"
      }
    ],
    local.clickhouse_enabled ? [
      {
        name      = "CLICKHOUSE_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.clickhouse_credentials[0].arn}:password::"
      }
    ] : [],
    var.entra_client_id != null ? [
      {
        name      = "AUTH_AZURE_AD_CLIENT_ID"
        valueFrom = "${aws_secretsmanager_secret.entra_credentials[0].arn}:client_id::"
      },
      {
        name      = "AUTH_AZURE_AD_CLIENT_SECRET"
        valueFrom = "${aws_secretsmanager_secret.entra_credentials[0].arn}:client_secret::"
      },
      {
        name      = "AUTH_AZURE_AD_TENANT_ID"
        valueFrom = "${aws_secretsmanager_secret.entra_credentials[0].arn}:tenant_id::"
      }
    ] : []
  )

  # Container definition for langfuse-web
  web_container_def = {
    name         = "langfuse-web"
    image        = "${var.langfuse_image}:${var.langfuse_version}"
    essential    = true
    cpu          = var.ecs_web_cpu
    memory       = var.ecs_web_memory
    portMappings = [
      {
        containerPort = var.port
        hostPort      = var.port
        protocol      = "tcp"
      }
    ]
    environment = local.common_container_env
    secrets     = local.common_container_secrets
    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://127.0.0.1:${var.port}/api/public/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "web"
      }
    }
    dependsOn = var.enable_embedded_clickhouse ? [
      {
        containerName = "clickhouse"
        condition     = "HEALTHY"
      }
    ] : []
  }

  # Container definition for langfuse-worker
  worker_container_def = {
    name        = "langfuse-worker"
    image       = "${var.langfuse_worker_image}:${var.langfuse_version}"
    essential   = true
    cpu         = var.ecs_worker_cpu
    memory      = var.ecs_worker_memory
    environment = local.common_container_env
    secrets     = local.common_container_secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "worker"
      }
    }
    dependsOn = var.enable_embedded_clickhouse ? [
      {
        containerName = "clickhouse"
        condition     = "HEALTHY"
      }
    ] : []
  }

  # Optional embedded ClickHouse container
  embedded_clickhouse_container_def = var.enable_embedded_clickhouse ? [
    {
      name      = "clickhouse"
      image     = "clickhouse/clickhouse-server:24.3"
      essential = true
      cpu       = 512
      memory    = 1024
      portMappings = [
        {
          containerPort = local.clickhouse_http_port
          hostPort      = local.clickhouse_http_port
          protocol      = "tcp"
        },
        {
          containerPort = local.clickhouse_native_port
          hostPort      = local.clickhouse_native_port
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "CLICKHOUSE_DB", value = var.clickhouse_db },
        { name = "CLICKHOUSE_USER", value = var.clickhouse_user }
      ]
      secrets = [
        {
          name      = "CLICKHOUSE_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.clickhouse_credentials[0].arn}:password::"
        }
      ]
      healthCheck = {
        command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://127.0.0.1:${local.clickhouse_http_port}/ping || exit 1"]
        interval    = 10
        timeout     = 5
        retries     = 5
        startPeriod = 15
      }
      mountPoints = [
        {
          sourceVolume  = "clickhouse-data"
          containerPath = "/var/lib/clickhouse"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "clickhouse"
        }
      }
    }
  ] : []

  all_container_definitions = concat(
    [local.web_container_def, local.worker_container_def],
    local.embedded_clickhouse_container_def
  )

  # Sizing calculation: if embedded ClickHouse is running, scale task capacity to 4 vCPU / 8 GB (valid Fargate tier)
  effective_task_cpu    = var.enable_embedded_clickhouse ? "4096" : tostring(var.ecs_cpu)
  effective_task_memory = var.enable_embedded_clickhouse ? "8192" : tostring(var.ecs_memory)
}

resource "aws_ecs_task_definition" "langfuse" {
  family                   = "${var.name_prefix}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.effective_task_cpu
  memory                   = local.effective_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions    = jsonencode(local.all_container_definitions)

  dynamic "volume" {
    for_each = var.enable_embedded_clickhouse ? [1] : []
    content {
      name = "clickhouse-data"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.clickhouse[0].id
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = aws_efs_access_point.clickhouse[0].id
          iam             = "ENABLED"
        }
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-task"
    }
  )
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "langfuse" {
  name                   = "${var.name_prefix}-service"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.langfuse.arn
  desired_count          = var.ecs_desired_count
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "langfuse-web"
    container_port   = var.port
  }

  depends_on = [
    aws_lb_listener.web,
    aws_iam_role_policy.ecs_execution_secrets,
    aws_rds_cluster_instance.postgresql,
    aws_elasticache_replication_group.redis,
    aws_efs_mount_target.clickhouse
  ]

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-service"
    }
  )
}
