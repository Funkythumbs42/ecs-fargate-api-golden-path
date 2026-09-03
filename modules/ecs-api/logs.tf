resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.service_name}-${var.environment}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}
