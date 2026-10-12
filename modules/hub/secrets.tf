data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Dedicated KMS Customer Managed Key (CMK)
# Created if var.kms_key_arn is not provided
# -----------------------------------------------------------------------------
resource "aws_kms_key" "langfuse" {
  count                   = var.kms_key_arn == null || var.kms_key_arn == "" ? 1 : 0
  description             = "KMS CMK for Langfuse Centralized Observability (${var.name_prefix})"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs to use KMS Key"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-kms-key"
    }
  )
}

resource "aws_kms_alias" "langfuse" {
  count         = var.kms_key_arn == null || var.kms_key_arn == "" ? 1 : 0
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.langfuse[0].key_id
}

# -----------------------------------------------------------------------------
# Secret Generators
# -----------------------------------------------------------------------------
# Database master password: use alphanumeric to prevent RFC 3986 connection string URI parsing issues
resource "random_password" "db_password" {
  length  = 64
  special = false
}

# NextAuth secret (32 bytes hex)
resource "random_id" "nextauth_secret" {
  byte_length = 32
}

# Langfuse 256-bit encryption key (32 bytes = 64 hex characters)
resource "random_id" "langfuse_encryption_key" {
  byte_length = 32
}

# Salt for password hashing
resource "random_password" "salt" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# ClickHouse password (if generated)
resource "random_password" "clickhouse_password" {
  count            = var.clickhouse_password == null ? 1 : 0
  length           = 32
  special          = false
}

# -----------------------------------------------------------------------------
# Secrets Manager: Database Credentials
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.name_prefix}/db-credentials"
  description             = "PostgreSQL credentials and connection string for Langfuse"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 0 # Immediate deletion on destroy for dev flexibility

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-db-credentials"
    }
  )
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username     = var.db_username
    password     = random_password.db_password.result
    engine       = "postgres"
    host         = aws_rds_cluster.postgresql.endpoint
    port         = local.db_port
    dbname       = var.db_name
    database_url = "postgresql://${var.db_username}:${random_password.db_password.result}@${aws_rds_cluster.postgresql.endpoint}:${local.db_port}/${var.db_name}"
  })
}

# -----------------------------------------------------------------------------
# Secrets Manager: Application Secrets
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.name_prefix}/app-secrets"
  description             = "Langfuse application secrets (NEXTAUTH_SECRET, encryption key, salt)"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-app-secrets"
    }
  )
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    nextauth_secret         = random_id.nextauth_secret.hex
    langfuse_encryption_key = random_id.langfuse_encryption_key.hex
    salt                    = random_password.salt.result
  })
}

# -----------------------------------------------------------------------------
# Secrets Manager: ClickHouse Credentials
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "clickhouse_credentials" {
  count                   = local.clickhouse_enabled ? 1 : 0
  name                    = "${var.name_prefix}/clickhouse-credentials"
  description             = "ClickHouse credentials and endpoints for Langfuse"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-clickhouse-credentials"
    }
  )
}

resource "aws_secretsmanager_secret_version" "clickhouse_credentials" {
  count     = local.clickhouse_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.clickhouse_credentials[0].id
  secret_string = jsonencode({
    user           = var.clickhouse_user
    password       = var.clickhouse_password != null ? var.clickhouse_password : random_password.clickhouse_password[0].result
    url            = local.clickhouse_http_url
    migration_url  = local.clickhouse_migration_url
    database       = var.clickhouse_db
  })
}

# -----------------------------------------------------------------------------
# Secrets Manager: Entra ID SSO Credentials (Optional)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "entra_credentials" {
  count                   = var.entra_client_id != null ? 1 : 0
  name                    = "${var.name_prefix}/entra-sso-credentials"
  description             = "Microsoft Entra ID SSO credentials for Langfuse UI"
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = 0

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-entra-credentials"
    }
  )
}

resource "aws_secretsmanager_secret_version" "entra_credentials" {
  count     = var.entra_client_id != null ? 1 : 0
  secret_id = aws_secretsmanager_secret.entra_credentials[0].id
  secret_string = jsonencode({
    client_id     = var.entra_client_id
    client_secret = var.entra_client_secret
    tenant_id     = var.entra_tenant_id
  })
}
