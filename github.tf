# See: https://github.blog/changelog/2022-01-13-github-actions-update-on-oidc-based-deployments-to-aws/
locals {
  github_thumbprint = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  github_path       = "repo:alexsergeyev/terraform-demo:*"
  github_repo       = "terraform-demo"
}
resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = local.github_thumbprint
  url             = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github" {
  name                 = "github-${local.github_repo}"
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.repo_policy.json
  depends_on           = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy_attachment" "repo_access" {
  policy_arn = aws_iam_policy.repo_policy.arn
  role       = aws_iam_role.github.name
}

resource "aws_iam_policy" "repo_policy" {
  name   = "github-${local.github_repo}"
  policy = data.aws_iam_policy_document.s3_rw.json
}

data "aws_iam_policy_document" "repo_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringLike"
      values   = [local.github_path]
      variable = "token.actions.githubusercontent.com:sub"
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "token.actions.githubusercontent.com:iss"
      values   = ["https://token.actions.githubusercontent.com"]
    }

    principals {
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
      type        = "Federated"
    }
  }
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
