# Placeholder values. Personal sandbox account 784318225077.
name                 = "example-platform-dev"
vpc_cidr             = "10.10.0.0/16"
azs                  = ["eu-west-1a", "eu-west-1b"]
public_subnet_cidrs  = ["10.10.0.0/24", "10.10.1.0/24"]
private_subnet_cidrs = ["10.10.10.0/24", "10.10.11.0/24"]
cluster_name         = "example-apps-dev"
ecr_repositories     = ["example-api", "testapi2"]
manage_ecr           = true
container_insights   = false
tags = {
  Environment = "dev"
  Example     = "true"
}
