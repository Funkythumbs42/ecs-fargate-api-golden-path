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
  region = "eu-west-1"

  # Example account only. Do not apply this to a real account as-is.
  allowed_account_ids = ["123456789012"]
}

module "platform" {
  source = "../../../modules/platform"

  name                 = var.name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = var.cluster_name
  ecr_repositories     = var.ecr_repositories
  manage_ecr           = var.manage_ecr
  container_insights   = var.container_insights
  tags                 = var.tags
}

output "vpc_id" { value = module.platform.vpc_id }
output "private_subnet_ids" { value = module.platform.private_subnet_ids }
output "public_subnet_ids" { value = module.platform.public_subnet_ids }
output "ecs_cluster_name" { value = module.platform.ecs_cluster_name }
output "ecs_cluster_arn" { value = module.platform.ecs_cluster_arn }
output "alb_http_listener_arn" { value = module.platform.alb_http_listener_arn }
output "alb_security_group_id" { value = module.platform.alb_security_group_id }
output "alb_arn_suffix" { value = module.platform.alb_arn_suffix }
output "alb_dns_name" { value = module.platform.alb_dns_name }
output "ecr_repository_urls" { value = module.platform.ecr_repository_urls }
output "ecr_repository_arns" { value = module.platform.ecr_repository_arns }
