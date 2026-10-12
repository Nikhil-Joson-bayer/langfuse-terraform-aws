# Data source for the Central Observability VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# -----------------------------------------------------------------------------
# Security Group: ECS Tasks
# -----------------------------------------------------------------------------
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-ecs-tasks-sg"
  description = "Security group for Langfuse ECS Fargate tasks"
  vpc_id      = var.vpc_id

  # Ingress on Langfuse web port from private RFC1918 CIDR ranges
  # Covers the central hub VPC and all spoke VPCs connecting via PrivateLink
  ingress {
    description = "Allow inbound Langfuse web traffic from 10.0.0.0/8"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "Allow inbound Langfuse web traffic from 172.16.0.0/12"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/12"]
  }

  ingress {
    description = "Allow inbound Langfuse web traffic from 192.168.0.0/16"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = ["192.168.0.0/16"]
  }

  # Ingress from VPC CIDR explicitly
  ingress {
    description = "Allow inbound Langfuse web traffic from VPC CIDR"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  # All outbound allowed (pull images, call AWS APIs, Secrets Manager, Bedrock/LLMs)
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-ecs-tasks-sg"
    }
  )
}

# -----------------------------------------------------------------------------
# Network Load Balancer (Internal)
# -----------------------------------------------------------------------------
# PrivateLink requires an NLB (ALB is not supported as an endpoint service target).
resource "aws_lb" "nlb" {
  name                             = trimsuffix(substr("${var.name_prefix}-nlb", 0, 32), "-")
  internal                         = true
  load_balancer_type               = "network"
  subnets                          = var.private_subnet_ids
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-nlb"
    }
  )
}

# -----------------------------------------------------------------------------
# NLB Target Group (IP-based targets for Fargate awsvpc)
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "web" {
  name                 = trimsuffix(substr("${var.name_prefix}-tg", 0, 32), "-")
  port                 = var.port
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  target_type          = "ip" # Required for ECS Fargate awsvpc network mode
  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = var.port
    path                = "/api/public/health"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-tg"
    }
  )
}

# -----------------------------------------------------------------------------
# NLB Listener (TCP port 3000)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = var.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-listener"
    }
  )
}

# -----------------------------------------------------------------------------
# VPC Endpoint Service (AWS PrivateLink)
# -----------------------------------------------------------------------------
# Enables spoke VPCs (e.g. CH MAIA, Top Loss, future agents) to establish
# private connectivity to Langfuse without internet routing or VPC peering.
resource "aws_vpc_endpoint_service" "langfuse" {
  acceptance_required        = false
  network_load_balancer_arns = [aws_lb.nlb.arn]

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.name_prefix}-vpce-svc"
    }
  )
}

locals {
  # Dynamically permit the current AWS account root by default, plus any explicitly configured cross-account principals
  effective_allowed_principals = distinct(concat(
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"],
    var.allowed_principals
  ))
}

# -----------------------------------------------------------------------------
# Allowed Principals for PrivateLink Service
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint_service_allowed_principal" "langfuse" {
  for_each                = toset(local.effective_allowed_principals)
  vpc_endpoint_service_id = aws_vpc_endpoint_service.langfuse.id
  principal_arn           = each.value
}
