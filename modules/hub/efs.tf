# -----------------------------------------------------------------------------
# Amazon EFS Persistent Storage for Embedded ClickHouse on ECS Fargate
# Created only when enable_embedded_clickhouse = true
# -----------------------------------------------------------------------------

# Security Group for EFS Mount Targets
resource "aws_security_group" "efs" {
  count       = var.enable_embedded_clickhouse ? 1 : 0
  name        = "${var.name_prefix}-efs-sg"
  description = "Security group for ClickHouse EFS storage"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow NFS port 2049 from Langfuse ECS tasks"
    from_port       = 2049
    to_port         = 2049
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
      "Name" = "${var.name_prefix}-efs-sg"
    }
  )
}

# KMS-encrypted EFS File System
resource "aws_efs_file_system" "clickhouse" {
  count          = var.enable_embedded_clickhouse ? 1 : 0
  creation_token = "${var.name_prefix}-clickhouse-efs"
  encrypted      = true
  kms_key_id     = local.kms_key_arn

  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-clickhouse-efs"
    }
  )
}

# Mount target in each private subnet for multi-AZ availability
resource "aws_efs_mount_target" "clickhouse" {
  count           = var.enable_embedded_clickhouse ? length(var.private_subnet_ids) : 0
  file_system_id  = aws_efs_file_system.clickhouse[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs[0].id]
}

# EFS Access Point with POSIX permissions for ClickHouse user (UID/GID 101)
resource "aws_efs_access_point" "clickhouse" {
  count          = var.enable_embedded_clickhouse ? 1 : 0
  file_system_id = aws_efs_file_system.clickhouse[0].id

  posix_user {
    gid = 101
    uid = 101
  }

  root_directory {
    path = "/clickhouse"
    creation_info {
      owner_gid   = 101
      owner_uid   = 101
      permissions = "755"
    }
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-clickhouse-ap"
    }
  )
}
