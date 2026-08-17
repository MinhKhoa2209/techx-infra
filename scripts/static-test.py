from __future__ import annotations
import pathlib
import re

root = pathlib.Path(__file__).parents[1]
text = "\n".join(path.read_text(encoding="utf-8") for path in root.rglob("*.tf"))
required = [
    'default = "1.35"', 'ami_type        = "AL2023_x86_64_STANDARD"',
    'http_tokens                 = "required"', 'http_put_response_hop_limit = 1',
    'volume_type           = "gp3"', 'encrypted             = true',
    'image_tag_mutability = "IMMUTABLE"', 'force_delete         = true',
    'retention_in_days = 7', 'enabled_cluster_log_types = ["api", "audit", "authenticator"]',
    'chart_version     = "3.3.0"', 'chart_version           = "9.5.17"',
    'for_each = toset([40, 60, 72])', 'limit_amount = "80"',
    'resource "aws_cloudfront_vpc_origin"',
    'resource "aws_ec2_client_vpn_endpoint"',
    'resource "aws_route53_zone"',
    'Managed-AllViewerAndCloudFrontHeaders-2022-06',
    'uri === \'/argocd\'',
    'cidrhost(var.vpc_cidr, 2)',
    '"server.rootpath" = var.server_rootpath',
    '"alb.ingress.kubernetes.io/scheme"',
    '"alb.ingress.kubernetes.io/group.order"',
    '"10"',
    '"alb.ingress.kubernetes.io/security-groups"',
    '"alb.ingress.kubernetes.io/subnets"',
    'referenced_security_group_id = aws_security_group.this[0].id',
]
for token in required:
    if token not in text:
        raise AssertionError(f"missing guardrail: {token}")
for forbidden in ("aws_nat_gateway", "aws_db_", "aws_wafv2_", "aws_route53_resolver_endpoint"):
    if re.search(rf'(?m)^resource\s+"{forbidden}', text):
        raise AssertionError(f"forbidden out-of-scope resource found: {forbidden}")
example = (root / "environments" / "demo" / "terraform.tfvars.example").read_text(encoding="utf-8")
if "0.0.0.0/0" in example:
    raise AssertionError("EKS API example must not allow 0.0.0.0/0")
if "enable_domain_vpn_edge                = false" not in example:
    raise AssertionError("edge/VPN resources must be opt-in in the example")
print("Terraform scope and guardrail assertions passed.")
