resource "aws_acm_certificate" "website" {
  domain_name       = local.domain_name
  validation_method = "DNS"
  depends_on        = [data.aws_route53_zone.main]
  provider          = aws.certificate_region
}

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

resource "aws_acm_certificate_validation" "acm" {
  certificate_arn         = aws_acm_certificate.website.arn
  validation_record_fqdns = [for record in aws_route53_record.acm : record.fqdn]
  provider                = aws.certificate_region
}
