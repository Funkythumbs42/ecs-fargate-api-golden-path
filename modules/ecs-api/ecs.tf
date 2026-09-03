resource "aws_ecs_task_definition" "this" {
  family                   = var.service_name
  cpu                      = local.cpu
  memory                   = local.memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = local.image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "SERVICE_NAME", value = var.service_name },
        { name = "PORT", value = tostring(var.container_port) },
      ]

      secrets = [
        for env_name, arn in var.secrets : {
          name      = env_name
          valueFrom = arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = var.service_name
        }
      }
    }
  ])

  tags = local.tags
}

data "aws_region" "current" {}

resource "aws_ecs_service" "this" {
  name                               = var.service_name
  cluster                            = var.cluster_name
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  enable_execute_command             = var.enable_execute_command
  health_check_grace_period_seconds  = 60
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  propagate_tags                     = "SERVICE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  wait_for_steady_state = true

  lifecycle {
    # Autoscaling owns count after the first apply. desired_count is the create-time seed.
    ignore_changes = [desired_count]
  }

  tags = local.tags

  depends_on = [aws_lb_listener_rule.this]
}
