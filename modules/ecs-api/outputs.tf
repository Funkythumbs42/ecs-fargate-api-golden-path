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

output "alb_dns_name" {
  description = "DNS name of this app's ALB. curl http://<this>/health — no fake Host header."
  value       = aws_lb.this.dns_name
}

output "alb_arn" {
  description = "ARN of this app's ALB."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix for request-count autoscaling."
  value       = aws_lb.this.arn_suffix
}

output "alb_zone_id" {
  description = "Canonical hosted zone ID of this app's ALB (for Route53 aliases)."
  value       = aws_lb.this.zone_id
}

output "alb_security_group_id" {
  description = "Security group attached to this app's ALB."
  value       = aws_security_group.alb.id
}

output "alb_internal" {
  description = "Whether the ALB is internal."
  value       = var.alb_internal
}
