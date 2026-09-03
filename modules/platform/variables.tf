variable "name" {
  description = "Short platform name, used as a prefix. Example: example-platform-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Use a distinct range per env."
  type        = string
}

variable "azs" {
  description = "Exactly two AZs for this stub. Prod landing zones usually take three."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "public_subnet_cidrs" {
  description = "One public subnet CIDR per AZ (ALB, NAT)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One private subnet CIDR per AZ (Fargate tasks)."
  type        = list(string)
}

variable "cluster_name" {
  description = "ECS cluster name."
  type        = string
}

variable "ecr_repositories" {
  description = "ECR repository names. One registry per account/region so Promote can reuse a digest across envs."
  type        = list(string)
  default     = ["example-api"]
}

variable "manage_ecr" {
  description = "true: create the repos. false: look up existing repos (other envs in the same account). Only one env should manage ECR."
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "Enable ECS Container Insights on the cluster."
  type        = bool
  default     = false
}

variable "create_state_backend" {
  description = "If true, create the S3 state bucket and DynamoDB lock table. Off by default; see README chicken-and-egg note."
  type        = bool
  default     = false
}

variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state (only used when create_state_backend is true)."
  type        = string
  default     = "example-tfstate-123456789012-eu-west-1"
}

variable "state_lock_table_name" {
  description = "DynamoDB table for state locking (only used when create_state_backend is true)."
  type        = string
  default     = "example-tfstate-lock"
}

variable "tags" {
  description = "Extra tags."
  type        = map(string)
  default     = {}
}
