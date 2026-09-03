locals {
  presets = {
    small  = { cpu = 256, memory = 512 }
    medium = { cpu = 512, memory = 1024 }
    large  = { cpu = 1024, memory = 2048 }
  }

  cpu    = local.presets[var.cpu_mem_preset].cpu
  memory = local.presets[var.cpu_mem_preset].memory

  image_digest = startswith(var.image_digest, "sha256:") ? var.image_digest : "sha256:${var.image_digest}"
  image        = "${var.ecr_repository_url}@${local.image_digest}"

  container_name = "api"

  min_capacity = coalesce(var.min_capacity, var.desired_count)

  alb_name = (
    length("${var.service_name}-${var.environment}") <= 32
    ? "${var.service_name}-${var.environment}"
    : "${substr(var.service_name, 0, 32 - 1 - length(var.environment))}-${var.environment}"
  )

  alb_subnets = var.alb_internal ? var.private_subnet_ids : var.public_subnet_ids

  tags = merge(
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Module      = "ecs-api"
    },
    var.tags,
  )
}
