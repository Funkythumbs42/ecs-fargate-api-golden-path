# Placeholder values. Personal sandbox account 784318225077.
name                 = "example-platform-prod"
vpc_cidr             = "10.30.0.0/16"
azs                  = ["eu-west-1a", "eu-west-1b"]
public_subnet_cidrs  = ["10.30.0.0/24", "10.30.1.0/24"]
private_subnet_cidrs = ["10.30.10.0/24", "10.30.11.0/24"]
cluster_name         = "example-apps-prod"
ecr_repositories     = ["example-api"]
manage_ecr           = false
container_insights   = true
tags = {
  Environment = "prod"
  Example     = "true"
}
