- [Create a Terraform configuration](#create-a-terraform-configuration)
- [Create an S3 bucket](#create-an-s3-bucket)
- [Create HTTPS certificate](#create-https-certificate)
- [Create CloudFront distribution](#create-cloudfront-distribution)
- [Allow access from Cloudfront to S3 bucket](#allow-access-from-cloudfront-to-s3-bucket)


#### This workshop will provide a production-ready demo of setting up static website hosting using Terraform on AWS using S3, CloudFront, Route 53, etc. It will show use cases of Terraform, syntax, and best practices for managing infrastructure as code.

## Create a Terraform configuration

Configure terraform state store on Terraform Cloud and add backend configuration for AWS provider.

```terraform
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
