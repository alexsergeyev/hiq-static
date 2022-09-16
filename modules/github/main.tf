data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

variable "repo_name" {
  type = string
}

variable "repo_policy" {
  type = string
}

variable "repo_prefix" {
  type    = string
  default = "repo:alexsergeyev"
}

variable "repo_refs" {
  type    = string
  default = "*"
}

output "role_arn" {
  value = aws_iam_role.github.arn
}

resource "aws_iam_role" "github" {
  path                 = "/github/"
  name                 = var.repo_name
  max_session_duration = 3600
  assume_role_policy   = data.aws_iam_policy_document.repo_policy.json
  depends_on           = [data.aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy_attachment" "repo_access" {
  policy_arn = aws_iam_policy.repo_policy.arn
  role       = aws_iam_role.github.name
}

resource "aws_iam_policy" "repo_policy" {
  path   = "/github/"
  name   = var.repo_name
  policy = var.repo_policy
}

data "aws_iam_policy_document" "repo_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringLike"
      values   = ["${var.repo_prefix}/${var.repo_name}:${var.repo_refs}"]
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
