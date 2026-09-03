# Placeholder values. Personal sandbox account 784318225077.
name                 = "example-platform-staging"
vpc_cidr             = "10.20.0.0/16"
azs                  = ["eu-west-1a", "eu-west-1b"]
public_subnet_cidrs  = ["10.20.0.0/24", "10.20.1.0/24"]
private_subnet_cidrs = ["10.20.10.0/24", "10.20.11.0/24"]
cluster_name         = "example-apps-staging"
ecr_repositories     = ["example-api"]
manage_ecr           = false
container_insights   = true
tags = {
  Environment = "staging"
  Example     = "true"
}
