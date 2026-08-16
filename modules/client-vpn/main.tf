locals {
  dns_server = var.vpc_cidr != "" ? cidrhost(var.vpc_cidr, 2) : "10.0.0.2"
}

resource "aws_security_group" "this" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.name}-"
  description = "AWS Client VPN association security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-sg" })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_egress_rule" "vpc" {
  count = var.enabled ? 1 : 0

  security_group_id = aws_security_group.this[0].id
  description       = "Allow authenticated VPN clients to VPC resources"
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_cloudwatch_log_group" "this" {
  count = var.enabled ? 1 : 0

  name              = "/aws/client-vpn/${var.name}"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_cloudwatch_log_stream" "this" {
  count = var.enabled ? 1 : 0

  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.this[0].name
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  count = var.enabled ? 1 : 0

  description                   = var.name
  server_certificate_arn        = var.server_certificate_arn
  client_cidr_block             = var.client_cidr
  split_tunnel                  = true
  transport_protocol            = "udp"
  vpn_port                      = 443
  vpc_id                        = var.vpc_id
  security_group_ids            = [aws_security_group.this[0].id]
  session_timeout_hours         = 8
  disconnect_on_session_timeout = true
  dns_servers                   = [local.dns_server]

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = var.client_root_certificate_arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.this[0].name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.this[0].name
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition = !var.enabled || (
        var.vpc_id != "" &&
        var.vpc_cidr != "" &&
        var.subnet_id != "" &&
        var.server_certificate_arn != "" &&
        var.client_root_certificate_arn != ""
      )
      error_message = "VPC, subnet and both mutual-TLS certificate ARNs are required when Client VPN is enabled."
    }
  }
}

resource "aws_ec2_client_vpn_network_association" "this" {
  count = var.enabled ? 1 : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this[0].id
  subnet_id              = var.subnet_id
}

resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  count = var.enabled ? 1 : 0

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this[0].id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true
  description            = "Allow authenticated clients to the TechX VPC"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = var.enabled ? 1 : 0

  security_group_id            = var.alb_security_group_id
  description                  = "Client VPN to internal ALB HTTPS"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.this[0].id
}

resource "aws_vpc_security_group_ingress_rule" "eks_api" {
  count = var.enabled ? 1 : 0

  security_group_id            = var.eks_security_group_id
  description                  = "Client VPN to private EKS API"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.this[0].id
}

