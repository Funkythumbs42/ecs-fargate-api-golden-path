variable "service_name" { type = string }
variable "image_digest" {
  description = "sha256 digest from the build pipeline. CI overrides this with -var."
  type        = string
}
variable "cpu_mem_preset" { type = string }
variable "container_port" { type = number }
variable "secrets" {
  description = "env var name => SSM or Secrets Manager ARN. Never plaintext."
  type        = map(string)
}
variable "desired_count" { type = number }
variable "min_capacity" { type = number }
variable "max_capacity" { type = number }
variable "health_check_path" {
  type    = string
  default = "/health"
}
variable "host_header" { type = string }
variable "enable_execute_command" { type = bool }
variable "log_retention_days" { type = number }
variable "platform_state_bucket" { type = string }
variable "platform_state_key" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
