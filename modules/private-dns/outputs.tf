output "zone_id" { value = var.enabled ? aws_route53_zone.this[0].zone_id : null }
output "hostname" { value = var.enabled ? var.zone_name : null }

