# -----------------------------------------------------------------------------
# ECS Task Execution Role (Used by ECS agent to pull images & fetch secrets)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.name_prefix}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-ecs-execution-role"
    }
  )
}

# Attach standard AmazonECSTaskExecutionRolePolicy
resource "aws_iam_role_policy_attachment" "ecs_execution_standard" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Inline policy: Secrets Manager & KMS decryption for ECS Agent
resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.name_prefix}-execution-secrets-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = compact([
          aws_secretsmanager_secret.db_credentials.arn,
          aws_secretsmanager_secret.app_secrets.arn,
          aws_secretsmanager_secret.redis_credentials.arn,
          local.clickhouse_enabled ? aws_secretsmanager_secret.clickhouse_credentials[0].arn : null,
          var.entra_client_id != null ? aws_secretsmanager_secret.entra_credentials[0].arn : null
        ])
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [local.kms_key_arn]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECS Task Role (Used by the running application containers)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.name_prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-ecs-task-role"
    }
  )
}

# Task Role Policy: S3 bucket access, KMS decryption, and ECS Exec
resource "aws_iam_role_policy" "ecs_task_app_policy" {
  name = "${var.name_prefix}-task-app-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.events.arn,
          "${aws_s3_bucket.events.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [local.kms_key_arn]
      },
      # EFS client mount and write permissions for persistent ClickHouse storage
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:DescribeMountTargets"
        ]
        Resource = "*"
      },
      # ECS Exec permissions for debugging containers
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}
