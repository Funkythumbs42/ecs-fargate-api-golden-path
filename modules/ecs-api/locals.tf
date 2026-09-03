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

  listener_priority = var.listener_rule_priority != null ? var.listener_rule_priority : (
    (parseint(substr(md5(var.service_name), 0, 4), 16) % 49000) + 10
  )

  tags = merge(
    {
      Service   = var.service_name
      ManagedBy = "terraform"
      Module    = "ecs-api"
    },
    var.tags,
  )
}
