output "endpoint_id" { value = var.enabled ? aws_ec2_client_vpn_endpoint.this[0].id : null }
output "dns_name" { value = var.enabled ? aws_ec2_client_vpn_endpoint.this[0].dns_name : null }
output "security_group_id" { value = var.enabled ? aws_security_group.this[0].id : null }
output "export_client_config_command" {
  value = var.enabled ? "aws ec2 export-client-vpn-client-configuration --region ${var.region} --client-vpn-endpoint-id ${aws_ec2_client_vpn_endpoint.this[0].id} --output text > client-vpn.private.ovpn" : null
}
