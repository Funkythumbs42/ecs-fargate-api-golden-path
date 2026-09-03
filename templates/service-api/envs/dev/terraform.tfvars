# Placeholder values. Personal sandbox account 784318225077.
# CI passes image_digest via -var; the zero digest is only so `terraform validate` can parse.
service_name           = "example-api"
environment            = "dev"
image_digest           = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
cpu_mem_preset         = "small"
container_port         = 8080
desired_count          = 1
min_capacity           = 1
max_capacity           = 2
health_check_path      = "/health"
alb_internal           = false
enable_execute_command = true
log_retention_days     = 7
platform_state_bucket  = "example-tfstate-784318225077-eu-west-1"
platform_state_key     = "platform/dev/terraform.tfstate"

# Required. Keys are container env names; values are ARNs only.
# secrets = {
#   DATABASE_URL = "arn:aws:ssm:eu-west-1:784318225077:parameter/example-api/dev/database-url"
# }
secrets = {}

tags = {
  Environment = "dev"
  Service     = "example-api"
}
