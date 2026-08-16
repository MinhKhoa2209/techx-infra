output "distribution_id" { value = var.enabled ? aws_cloudfront_distribution.this[0].id : null }
output "domain_name" { value = var.enabled ? aws_cloudfront_distribution.this[0].domain_name : null }
output "status" { value = var.enabled ? aws_cloudfront_distribution.this[0].status : null }

