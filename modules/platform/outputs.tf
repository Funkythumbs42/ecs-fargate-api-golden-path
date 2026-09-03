output "vpc_id" {
  description = "VPC ID for service modules."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Fargate tasks."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB)."
  value       = aws_subnet.public[*].id
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "alb_http_listener_arn" {
  description = "HTTP listener ARN. Service modules attach rules here."
  value       = aws_lb_listener.http.arn
}

output "alb_security_group_id" {
  description = "ALB security group. Service SGs admit this ID only."
  value       = aws_security_group.alb.id
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix for request-count autoscaling."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "Public ALB DNS name."
  value       = aws_lb.this.dns_name
}

output "ecr_repository_urls" {
  description = "Map of repository name => repository URL."
  value       = local.ecr_urls
}

output "ecr_repository_arns" {
  description = "Map of repository name => repository ARN."
  value       = local.ecr_arns
}
