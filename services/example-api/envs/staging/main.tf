terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region              = "eu-west-1"
  allowed_account_ids = ["784318225077"]
}

# Platform stack is a separate state key. This root is service-only.
data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.platform_state_bucket
    key    = var.platform_state_key
    region = "eu-west-1"
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
}

module "api" {
  source = "../../../../modules/ecs-api"

  service_name           = var.service_name
  image_digest           = var.image_digest
  cpu_mem_preset         = var.cpu_mem_preset
  container_port         = var.container_port
  secrets                = var.secrets
  desired_count          = var.desired_count
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
  health_check_path      = var.health_check_path
  host_header            = var.host_header
  enable_execute_command = var.enable_execute_command
  log_retention_days     = var.log_retention_days
  assign_public_ip       = false
  tags                   = var.tags

  ecr_repository_url    = local.platform.ecr_repository_urls[var.service_name]
  cluster_name          = local.platform.ecs_cluster_name
  vpc_id                = local.platform.vpc_id
  private_subnet_ids    = local.platform.private_subnet_ids
  alb_listener_arn      = local.platform.alb_http_listener_arn
  alb_security_group_id = local.platform.alb_security_group_id
  alb_arn_suffix        = local.platform.alb_arn_suffix
}

output "service_name" { value = module.api.service_name }
output "task_definition_arn" { value = module.api.task_definition_arn }
output "target_group_arn" { value = module.api.target_group_arn }
output "log_group" { value = module.api.log_group }
output "security_group_id" { value = module.api.security_group_id }
output "image" { value = module.api.image }
output "image_digest" { value = module.api.image_digest }
