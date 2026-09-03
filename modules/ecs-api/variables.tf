variable "service_name" {
  description = "ECS service / task family name. Lowercase, DNS-safe. Used in naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-32 chars, start with a letter, and be lowercase alphanumeric plus hyphens."
  }
}

variable "image_digest" {
  description = "Image digest only (sha256:...). CI builds and pushes the image, then passes this in. Never a mutable tag."
  type        = string

  validation {
    condition     = can(regex("^(sha256:)?[a-f0-9]{64}$", var.image_digest))
    error_message = "image_digest must be a 64-char hex digest, optionally prefixed with sha256:."
  }
}

variable "cpu_mem_preset" {
  description = "Fargate size preset: small (256/512), medium (512/1024), large (1024/2048)."
  type        = string

  validation {
    condition     = contains(["small", "medium", "large"], var.cpu_mem_preset)
    error_message = "cpu_mem_preset must be one of: small, medium, large."
  }
}

variable "container_port" {
  description = "Port the container listens on (ALB target and security-group ingress)."
  type        = number

  validation {
    condition     = var.container_port > 0 && var.container_port < 65536
    error_message = "container_port must be a valid TCP port."
  }
}

variable "secrets" {
  description = <<-EOT
    Container secrets. Map of env-var name => SSM Parameter Store or Secrets Manager ARN.
    Values must be ARNs, never secret strings. Empty map is valid if the service has no secrets.
  EOT
  type        = map(string)

  validation {
    condition = alltrue([
      for arn in values(var.secrets) : can(regex("^arn:aws:(ssm|secretsmanager):", arn))
    ])
    error_message = "Every secrets value must be an ssm or secretsmanager ARN, not a plaintext secret."
  }
}

variable "ecr_repository_url" {
  description = "ECR repository URL without tag or digest (e.g. 123456789012.dkr.ecr.eu-west-1.amazonaws.com/example-api)."
  type        = string
}

variable "cluster_name" {
  description = "Existing ECS cluster name (platform output)."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID (platform output)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for awsvpc ENIs (platform output). Fargate tasks stay private."
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Provide at least two private subnet IDs (two AZs)."
  }
}

variable "alb_listener_arn" {
  description = "ALB listener ARN to attach a rule to (platform output)."
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB security group ID. Service SG admits this SG on container_port only."
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB arn_suffix, used for ALBRequestCountPerTarget autoscaling."
  type        = string
}

variable "assign_public_ip" {
  description = "Must stay false on this golden path. Tasks run in private subnets behind NAT."
  type        = bool
  default     = false

  validation {
    condition     = var.assign_public_ip == false
    error_message = "assign_public_ip must be false. Public IP on Fargate tasks is not this golden path."
  }
}

variable "desired_count" {
  description = "Steady-state task count. Autoscaling min defaults to this unless min_capacity is set."
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Autoscaling minimum. Null means desired_count."
  type        = number
  default     = null
}

variable "max_capacity" {
  description = "Autoscaling maximum."
  type        = number
  default     = 4
}

variable "cpu_target_utilization" {
  description = "Target CPU utilization percent for tracking autoscaling."
  type        = number
  default     = 70
}

variable "alb_requests_per_target" {
  description = "Target ALB request count per task for tracking autoscaling."
  type        = number
  default     = 1000
}

variable "health_check_path" {
  description = "ALB HTTP health-check path."
  type        = string
  default     = "/health"
}

variable "host_header" {
  description = "If set, ALB rule matches this host header. If null, rule is path-based (path_pattern)."
  type        = string
  default     = null
}

variable "path_pattern" {
  description = "Path pattern used when host_header is null. Ignored when host_header is set (host rule takes the service)."
  type        = string
  default     = "/*"
}

variable "listener_rule_priority" {
  description = "Explicit ALB rule priority. Null derives a stable value from service_name."
  type        = number
  default     = null
}

variable "enable_execute_command" {
  description = "ECS Exec. Keep false in prod. Optional in non-prod."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the service log group."
  type        = number
  default     = 14
}

variable "kms_key_arns" {
  description = "Optional CMK ARNs the execution role may use to decrypt secrets. Empty if using AWS-managed keys."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}
