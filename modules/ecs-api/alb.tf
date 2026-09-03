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

resource "aws_lb_listener_rule" "this" {
  listener_arn = var.alb_listener_arn
  priority     = local.listener_priority
  tags         = local.tags

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  dynamic "condition" {
    for_each = var.host_header != null ? [var.host_header] : []
    content {
      host_header {
        values = [condition.value]
      }
    }
  }

  dynamic "condition" {
    for_each = var.host_header == null ? [var.path_pattern] : []
    content {
      path_pattern {
        values = [condition.value]
      }
    }
  }
}
