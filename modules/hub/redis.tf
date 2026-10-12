# -----------------------------------------------------------------------------
# Security Group: Redis (ElastiCache)
# -----------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis-sg"
  description = "Security group for Langfuse ElastiCache Redis cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow inbound Redis from Langfuse ECS tasks"
    from_port       = local.redis_port
    to_port         = local.redis_port
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-redis-sg"
    }
  )
}

# -----------------------------------------------------------------------------
# ElastiCache Subnet & Parameter Groups
# -----------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "redis" {
  name        = "${var.name_prefix}-redis-subnet-group"
  description = "Subnet group for Langfuse ElastiCache Redis"
  subnet_ids  = var.private_subnet_ids

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-redis-subnet-group"
    }
  )
}

resource "aws_elasticache_parameter_group" "redis" {
  family      = "redis7"
  name        = "${var.name_prefix}-redis-params"
  description = "Parameter group for Langfuse Redis 7.x"

  # BullMQ queues require noeviction to prevent losing background jobs
  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-redis-params"
    }
  )
}

resource "aws_cloudwatch_log_group" "redis" {
  name              = "/aws/elasticache/${var.name_prefix}-redis"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-redis-logs"
    }
  )
}

# -----------------------------------------------------------------------------
# Redis Auth Token & Replication Group
# -----------------------------------------------------------------------------
resource "random_password" "redis_auth_token" {
  length  = 64
  special = false
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = trimsuffix(substr("${var.name_prefix}-redis", 0, 40), "-")
  description                = "ElastiCache Redis replication group for Langfuse queues and caching"
  node_type                  = var.redis_node_type
  port                       = local.redis_port
  parameter_group_name       = aws_elasticache_parameter_group.redis.name
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  engine                     = "redis"
  engine_version             = "7.1"
  num_cache_clusters         = var.redis_num_nodes
  automatic_failover_enabled = var.redis_num_nodes > 1 ? true : false
  multi_az_enabled           = var.redis_num_nodes > 1 ? true : false
  auth_token                 = random_password.redis_auth_token.result
  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  kms_key_id                 = local.kms_key_arn

  log_delivery_configuration {
    destination      = aws_cloudwatch_log_group.redis.name
    destination_type = "cloudwatch-logs"
    log_format       = "json"
    log_type         = "slow-log"
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-redis"
    }
  )
}

# -----------------------------------------------------------------------------
# Secrets Manager: Redis URL
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "redis_credentials" {
  name                    = "${var.name_prefix}/redis-credentials"
  description             = "Redis connection URL for Langfuse"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-redis-credentials"
    }
  )
}

resource "aws_secretsmanager_secret_version" "redis_credentials" {
  secret_id = aws_secretsmanager_secret.redis_credentials.id
  secret_string = jsonencode({
    host      = aws_elasticache_replication_group.redis.primary_endpoint_address
    port      = local.redis_port
    auth_token = random_password.redis_auth_token.result
    # rediss:// for in-transit TLS enabled connection
    redis_url = "rediss://:${random_password.redis_auth_token.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:${local.redis_port}"
  })
}
