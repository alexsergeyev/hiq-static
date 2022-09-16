# See: https://github.blog/changelog/2022-01-13-github-actions-update-on-oidc-based-deployments-to-aws/
locals {
  github_thumbprint = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  github_repo       = "terraform-demo"
}
resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = local.github_thumbprint
  url             = "https://token.actions.githubusercontent.com"
}

module "github-demo" {
  source      = "./modules/github"
  repo_name   = local.github_repo
  repo_policy = data.aws_iam_policy_document.s3_rw.json
}

data "aws_iam_policy_document" "s3_rw" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListAllMyBuckets"
    ]
    resources = [aws_s3_bucket.s3_bucket.arn]
  }
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:GetObjectAcl",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
      "s3:DeleteObject"
    ]
    resources = ["${aws_s3_bucket.s3_bucket.arn}/*"]
  }
}
