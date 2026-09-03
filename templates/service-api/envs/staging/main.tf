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

# Platform stack (VPC, subnets, cluster, ECR) is a separate state key
# in the factory repo. This root is this app only, including its ALB.
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
  # Pin in production: replace ref=main with a tag or commit SHA.
  source = "git::https://github.com/Funkythumbs42/ecs-fargate-api-golden-path.git//modules/ecs-api?ref=main"

  service_name           = var.service_name
  environment            = var.environment
  image_digest           = var.image_digest
  cpu_mem_preset         = var.cpu_mem_preset
  container_port         = var.container_port
  secrets                = var.secrets
  desired_count          = var.desired_count
  min_capacity           = var.min_capacity
  max_capacity           = var.max_capacity
  health_check_path      = var.health_check_path
  alb_internal           = var.alb_internal
  enable_execute_command = var.enable_execute_command
  log_retention_days     = var.log_retention_days
  assign_public_ip       = false
  tags                   = var.tags

  ecr_repository_url = local.platform.ecr_repository_urls[var.service_name]
  cluster_name       = local.platform.ecs_cluster_name
  vpc_id             = local.platform.vpc_id
  private_subnet_ids = local.platform.private_subnet_ids
  public_subnet_ids  = local.platform.public_subnet_ids
}

output "service_name" { value = module.api.service_name }
output "task_definition_arn" { value = module.api.task_definition_arn }
output "target_group_arn" { value = module.api.target_group_arn }
output "log_group" { value = module.api.log_group }
output "security_group_id" { value = module.api.security_group_id }
output "image" { value = module.api.image }
output "image_digest" { value = module.api.image_digest }
output "alb_dns_name" { value = module.api.alb_dns_name }
output "alb_arn" { value = module.api.alb_arn }
output "alb_internal" { value = module.api.alb_internal }
