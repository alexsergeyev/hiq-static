data "aws_cloudfront_cache_policy" "cache_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_origin_request_policy" "origin_cors" {
  name = "Managed-CORS-S3Origin"
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

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

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.website.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
  price_class         = "PriceClass_100"
  wait_for_deployment = false

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "s3-default"
    cache_policy_id          = data.aws_cloudfront_cache_policy.cache_optimized.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.origin_cors.id
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_caching_min_ttl = 300
    error_code            = 403
    response_code         = 404
    response_page_path    = local.error_page
  }
}

resource "aws_route53_record" "website_ipv4" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "website_ipv6" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

