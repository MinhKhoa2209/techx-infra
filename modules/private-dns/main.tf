data "aws_lb" "origin" {
  count = var.enabled ? 1 : 0
  arn   = var.alb_arn
}

resource "aws_route53_zone" "this" {
  count = var.enabled ? 1 : 0

  name          = var.zone_name
  comment       = "Private split-view DNS for ${var.zone_name}"
  force_destroy = true

  vpc { vpc_id = var.vpc_id }

  tags = merge(var.tags, { Name = "${var.zone_name}-private" })
}

resource "aws_route53_record" "apex" {
  count = var.enabled ? 1 : 0

  zone_id = aws_route53_zone.this[0].zone_id
  name    = var.zone_name
  type    = "A"

  alias {
    name                   = data.aws_lb.origin[0].dns_name
    zone_id                = data.aws_lb.origin[0].zone_id
    evaluate_target_health = true
  }
}

