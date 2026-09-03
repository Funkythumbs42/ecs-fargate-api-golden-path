# Leftover for the live PoC stack. Not the product path.
# New apps create their own ALB in modules/ecs-api (alb_internal).
# Do not add count/for_each here: that would replace the running ALB.
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Public ALB for ${var.name}"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${var.name}-alb" })

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
  cidr_ipv4         = "0.0.0.0/0"
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "Forward to Fargate tasks"
  ip_protocol       = "-1"
  cidr_ipv4         = aws_vpc.this.cidr_block
  tags              = local.tags
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  internal           = false
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
  ip_address_type    = "ipv4"

  tags = local.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }

  tags = local.tags
}
