provider "aws" {
  region  = "eu-north-1"
  profile = "hiqdemo"
}

provider "aws" {
  alias   = "certificate_region"
  region  = "us-east-1"
  profile = "hiqdemo"
}

terraform {
  cloud {
    organization = "hiqdemo"

    workspaces {
      name = "static-demo"
    }
  }
}

locals {
  s3_bucket   = "hiq-workshop"
  domain_name = "hiqdemo.com"
}

data "aws_route53_zone" "main" {
  name         = "${local.domain_name}."
  private_zone = false
}

resource "aws_s3_bucket" "s3_bucket" {
  bucket        = local.s3_bucket
  force_destroy = true
}

# Block all public access
resource "aws_s3_bucket_acl" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.bucket
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "s3_block" {
  bucket                  = aws_s3_bucket.s3_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
