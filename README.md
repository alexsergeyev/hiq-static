- [AWSCLI profile](#awscli-profile)
- [Terraform Cloud account and token](#terraform-cloud-account-and-token)
- [Create a Terraform configuration](#create-a-terraform-configuration)
- [Create an S3 bucket](#create-an-s3-bucket)
- [Create HTTPS certificate](#create-https-certificate)
- [Create CloudFront distribution](#create-cloudfront-distribution)
- [Allow access from Cloudfront to S3 bucket](#allow-access-from-cloudfront-to-s3-bucket)
- [Enable GitHub OIDC for AWS](#enable-github-oidc-for-aws)
  - [GitHub Role Policy](#github-role-policy)
  - [S3 Access Policy](#s3-access-policy)
  - [Add policies to the role](#add-policies-to-the-role)
- [Create GitHub module](#create-github-module)
- [Github Actions](#github-actions)
  - [Setup provider](#setup-provider)
  - [Create secrets](#create-secrets)


#### This workshop will provide a production-ready demo of setting up static website hosting using Terraform on AWS using S3, CloudFront, Route 53, etc. It will show use cases of Terraform, syntax, and best practices for managing infrastructure as code.

![Alt text](/assets/terraform02.png?raw=true "Schema")

## AWSCLI profile

cat ~/.aws/credentials

```
[hiqdemo]
aws_access_key_id = XXXXX
aws_secret_access_key = XXXXX
region = eu-north-1
```

## Terraform Cloud account and token

https://app.terraform.io/public/signup/account

https://learn.hashicorp.com/tutorials/terraform/cloud-login


## Create a Terraform configuration

Configure terraform state store on Terraform Cloud and add backend configuration for AWS provider.

```terraform

provider "aws" {
  region  = "eu-north-1"
  profile = "hiqdemo"    # Same name as in .aws/credentials
}

terraform {
  cloud {
    organization = "hiqdemo"

    workspaces {
      name = "static-demo"
    }
  }
}
```

Another option is to use an AWS S3 bucket as a state store.

```terraform
terraform {
  backend "s3" {
    bucket = "terraform-state-bucket"
    key    = "static-demo/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Create an S3 bucket 

Here we will use [local variables](https://www.terraform.io/language/values/locals):

```terraform
locals {
  s3_bucket   = "hiq-workshop"
}
```

And then [S3 Bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) with private ACL

```terraform
resource "aws_s3_bucket" "s3_bucket" {
  bucket        = local.s3_bucket
  force_destroy = true
}

resource "aws_s3_bucket_acl" "s3_bucket" {
  bucket = aws_s3_bucket.s3_bucket.bucket # reference the bucket name from the resource above
  acl    = "private"
}
```

## Create HTTPS certificate

Read DNS zone id by using [data source](https://www.terraform.io/language/providers/requirements.html#data-sources) and [external data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone):

```terraform
data "aws_route53_zone" "main" {
  name         = "${local.domain_name}."
  private_zone = false
}
```

We can create more than one alias in certificate resource and each of them will need DNS verification record ([using for_each ](https://www.terraform.io/language/meta-arguments/for_each#basic-syntax)):



```terraform
resource "aws_route53_record" "acm" {
  for_each = {
    for dvo in aws_acm_certificate.website.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id
  depends_on      = [aws_acm_certificate.website]
}
```

## Create CloudFront distribution

Create [CloudFront distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) with s3 bucket as origin and certificate as viewer certificate:


Origin access control recommended to grant access to S3 bucket only for CloudFront distribution:

https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html


```
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    origin_id                = "s3-default"
    domain_name              = aws_s3_bucket.s3_bucket.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }
  aliases = [local.domain_name]

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = local.index_page
  <...skip...>
}
```

## Allow access from Cloudfront to S3 bucket

Create [IAM policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) to allow CloudFront to access the S3 bucket:


```terraform
resource "aws_s3_bucket_policy" "cloudfront" {
  bucket = aws_s3_bucket.s3_bucket.id
  policy = data.aws_iam_policy_document.cloudfront.json
}

data "aws_iam_policy_document" "cloudfront" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.s3_bucket.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.s3_distribution.arn]
    }

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
  }
}
```

## Enable GitHub OIDC for AWS

![Alt text](/assets/terraform03.png?raw=true "Schema")

Use OpenID Connect within GitHub actions to authenticate with Amazon Web Services.

* https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
* https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html

```terraform
resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["sts.amazonaws.com"]
  url             = "https://token.actions.githubusercontent.com"
}
```

### GitHub Role Policy

```terraform

Allow specific repo to assume AWS role:

```terraform
data "aws_iam_policy_document" "repo_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringLike"
      values   = [repo:alexsergeyev/terraform-demo:*]
      variable = "token.actions.githubusercontent.com:sub"
    }
    < ... >
    principals {
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"]
      type        = "Federated"
    }
  }
}
```

Can be limited to pull requests or specific branch only


### S3 Access Policy

Allow writing to the specific S3 bucket:

```terraform
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
```

### Add policies to the role

```
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
```

## Create GitHub module

```terraform
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

output "role_arn" {
  value = aws_iam_role.github.arn
}
```



```terraform
module "github-demo" {
  source      = "./modules/github"
  repo_name   = local.github_repo
  repo_policy = data.aws_iam_policy_document.s3_rw.json
}
```

## Github Actions

```yaml
name: hiqdemo.com
on: push
jobs:
  hugo_deploy:
    permissions:
      id-token: write
      contents: read
    runs-on: ubuntu-latest
    steps:
      - name: "Login to AWS"
        uses: aws-actions/configure-aws-credentials@v1
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ secrets.AWS_REGION }}
      - name: Deploy
        run: |
          AWS_BUCKET=${{secrets.AWS_BUCKET}} hugo && hugo deploy --target=hiqdemo.com
```

### Setup provider

```terraform
data "aws_ssm_parameter" "github_token" {
  name            = "GITHUB_TOKEN"
  with_decryption = true
}

provider "github" {
  owner = "alexsergeyev"
  token = data.aws_ssm_parameter.github_token.value
}
```

### Create secrets

```terraform
locals {
  github_secrets = {
    "AWS_ROLE_ARN" = module.github-demo.role_arn
    "AWS_REGION"   = "eu-north-1"
    "AWS_BUCKET"   = aws_s3_bucket.s3_bucket.id
  }
}

resource "github_actions_secret" "aws" {
  for_each        = local.github_secrets
  repository      = local.github_repo
  secret_name     = each.key
  plaintext_value = each.value
}
```
