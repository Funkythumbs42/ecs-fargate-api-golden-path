variable "name" { type = string }
variable "vpc_cidr" { type = string }
variable "azs" {
  type    = list(string)
  default = ["eu-west-1a", "eu-west-1b"]
}
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }
variable "cluster_name" { type = string }
variable "ecr_repositories" {
  type    = list(string)
  default = ["example-api"]
}
variable "manage_ecr" {
  type    = bool
  default = false
}
variable "container_insights" {
  type    = bool
  default = false
}
variable "tags" {
  type    = map(string)
  default = {}
}
