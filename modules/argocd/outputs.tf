output "release_name" { value = helm_release.this.name }
output "private_url" { value = var.private_ingress_enabled ? var.server_url : null }
