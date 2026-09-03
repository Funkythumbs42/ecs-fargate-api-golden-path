# Each app owns its ALB. Platform does not share a listener.
# Internet-facing: public subnets. Internal: private subnets.
# Default listener forwards /* to this service (no Host header required).

data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.service_name}-alb-"
  description = var.alb_internal ? "Internal ALB for ${var.service_name}" : "Internet-facing ALB for ${var.service_name}"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${local.alb_name}-alb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP. TLS/ACM is out of scope for this stub."
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = var.alb_internal ? data.aws_vpc.this.cidr_block : "0.0.0.0/0"
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to Fargate tasks"
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.service.id
  tags                         = local.tags
}

resource "aws_lb" "this" {
  name               = local.alb_name
  load_balancer_type = "application"
  internal           = var.alb_internal
  subnets            = local.alb_subnets
  security_groups    = [aws_security_group.alb.id]
  ip_address_type    = "ipv4"

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.alb_internal || length(var.public_subnet_ids) >= 2
      error_message = "Internet-facing ALB requires at least two public subnet IDs from the platform stack."
    }
    precondition {
      condition     = length(local.alb_subnets) >= 2
      error_message = "ALB requires at least two subnet IDs."
    }
  }
}

resource "aws_lb_target_group" "this" {
  name_prefix = substr(replace(var.service_name, "/[^a-z0-9]/", ""), 0, 6)
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.tags
}
