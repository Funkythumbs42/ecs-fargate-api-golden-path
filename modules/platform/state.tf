# Optional bootstrap resources. Creating the bucket that will later hold
# *this* stack's state is a chicken-and-egg problem: apply locally first,
# then migrate, or create the bucket out of band. Default is off.

resource "aws_s3_bucket" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = var.state_bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  count  = var.create_state_backend ? 1 : 0
  bucket = aws_s3_bucket.tfstate[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  count                   = var.create_state_backend ? 1 : 0
  bucket                  = aws_s3_bucket.tfstate[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  count        = var.create_state_backend ? 1 : 0
  name         = var.state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = local.tags
}
