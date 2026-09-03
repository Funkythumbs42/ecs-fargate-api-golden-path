# One ECR repo per service, shared by all envs in this account. Creating it
# in every env directory would conflict. manage_ecr = true in exactly one env.

resource "aws_ecr_repository" "this" {
  for_each = var.manage_ecr ? toset(var.ecr_repositories) : toset([])

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the most recent 50 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 50
        }
        action = { type = "expire" }
      }
    ]
  })
}

data "aws_ecr_repository" "existing" {
  for_each = var.manage_ecr ? toset([]) : toset(var.ecr_repositories)
  name     = each.value
}

locals {
  ecr_urls = merge(
    { for k, r in aws_ecr_repository.this : k => r.repository_url },
    { for k, r in data.aws_ecr_repository.existing : k => r.repository_url },
  )
  ecr_arns = merge(
    { for k, r in aws_ecr_repository.this : k => r.arn },
    { for k, r in data.aws_ecr_repository.existing : k => r.arn },
  )
}
