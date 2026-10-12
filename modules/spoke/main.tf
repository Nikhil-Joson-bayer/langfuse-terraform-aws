# Fetch spoke VPC details
data "aws_vpc" "spoke" {
  id = var.vpc_id
}

# -----------------------------------------------------------------------------
# Security Group: Spoke VPC Endpoint
# -----------------------------------------------------------------------------
resource "aws_security_group" "endpoint" {
  name        = "${var.name_prefix}-endpoint-sg"
  description = "Security group for Langfuse Interface VPC Endpoint in spoke VPC"
  vpc_id      = var.vpc_id

  # Dynamic ingress based on provided agent SGs or CIDRs
  dynamic "ingress" {
    for_each = length(var.agent_security_group_ids) > 0 ? [1] : []
    content {
      description     = "Allow inbound traffic from agent security groups"
      from_port       = var.port
      to_port         = var.port
      protocol        = "tcp"
      security_groups = var.agent_security_group_ids
    }
  }

  dynamic "ingress" {
    for_each = length(var.agent_security_group_ids) == 0 ? [1] : []
    content {
      description = "Allow inbound traffic from spoke VPC or allowed CIDRs"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = length(var.allowed_cidr_blocks) > 0 ? var.allowed_cidr_blocks : [data.aws_vpc.spoke.cidr_block]
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name_prefix}-endpoint-sg"
    }
  )
}

# -----------------------------------------------------------------------------
# VPC Interface Endpoint (Connecting to Central Hub via PrivateLink)
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "langfuse" {
  vpc_id              = var.vpc_id
  service_name        = var.endpoint_service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = false

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name_prefix}-endpoint"
    }
  )
}
