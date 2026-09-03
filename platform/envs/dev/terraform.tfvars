# Placeholder values. Account 123456789012 is fake.
name                 = "example-platform-dev"
vpc_cidr             = "10.10.0.0/16"
azs                  = ["eu-west-1a", "eu-west-1b"]
public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
cluster_name         = "example-apps-dev"
ecr_repositories     = ["example-api"]
manage_ecr           = true
container_insights   = false
tags = {
  Environment = "dev"
  Example     = "true"
}
