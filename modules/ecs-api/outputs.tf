output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "target_group_arn" {
  description = "ALB target group ARN."
  value       = aws_lb_target_group.this.arn
}

output "log_group" {
  description = "CloudWatch log group name."
  value       = aws_cloudwatch_log_group.this.name
}

output "security_group_id" {
  description = "Task security group ID."
  value       = aws_security_group.service.id
}

output "image" {
  description = "Image URI actually deployed (repo@digest)."
  value       = local.image
}

output "image_digest" {
  description = "Digest currently in the task definition. Infra apply must pass this back in so a rollback of infra does not rewind the image."
  value       = var.image_digest
}
