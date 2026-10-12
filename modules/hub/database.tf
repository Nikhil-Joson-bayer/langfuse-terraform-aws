# -----------------------------------------------------------------------------
# Security Group: PostgreSQL (Aurora Serverless v2)
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Security group for Langfuse Aurora PostgreSQL cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow inbound PostgreSQL from Langfuse ECS tasks"
    from_port       = local.db_port
    to_port         = local.db_port
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
      "Name" = "${var.name_prefix}-db-sg"
    }
  )
}

# -----------------------------------------------------------------------------
# DB Subnet Group
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "postgresql" {
  name        = "${var.name_prefix}-db-subnet-group"
  description = "Subnet group for Langfuse Aurora PostgreSQL cluster"
  subnet_ids  = var.private_subnet_ids

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-db-subnet-group"
    }
  )
}

# -----------------------------------------------------------------------------
# Aurora Serverless v2 PostgreSQL Cluster
# -----------------------------------------------------------------------------
resource "aws_rds_cluster" "postgresql" {
  cluster_identifier           = "${var.name_prefix}-db"
  engine                       = "aurora-postgresql"
  engine_mode                  = "provisioned"
  engine_version               = "15.7"
  database_name                = var.db_name
  master_username              = var.db_username
  master_password              = random_password.db_password.result
  db_subnet_group_name         = aws_db_subnet_group.postgresql.name
  vpc_security_group_ids       = [aws_security_group.db.id]
  storage_encrypted            = true
  kms_key_id                   = local.kms_key_arn
  skip_final_snapshot          = true
  deletion_protection          = false
  backup_retention_period      = 7
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "mon:04:00-mon:05:00"

  serverlessv2_scaling_configuration {
    min_capacity = var.db_min_capacity
    max_capacity = var.db_max_capacity
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-db"
    }
  )
}

# -----------------------------------------------------------------------------
# Aurora Cluster Instance (Serverless v2)
# -----------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "postgresql" {
  identifier          = "${var.name_prefix}-db-instance-1"
  cluster_identifier  = aws_rds_cluster.postgresql.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.postgresql.engine
  engine_version      = aws_rds_cluster.postgresql.engine_version
  publicly_accessible = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.kms_key_arn
  performance_insights_retention_period = 7

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-db-instance-1"
    }
  )
}
