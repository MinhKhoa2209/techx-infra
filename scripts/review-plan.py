from __future__ import annotations

import collections
import json
import sys

stage = sys.argv[1] if len(sys.argv) > 1 else "foundation"
if stage not in {"foundation", "edge"}:
    raise AssertionError("stage must be foundation or edge")

plan = json.load(sys.stdin)
changes = plan.get("resource_changes", [])
allowed = {
    "aws_budgets_budget", "aws_cloudwatch_log_group", "aws_ecr_lifecycle_policy",
    "aws_ecr_repository", "aws_eks_addon", "aws_eks_cluster", "aws_eks_node_group",
    "aws_iam_openid_connect_provider", "aws_iam_policy", "aws_iam_role",
    "aws_iam_role_policy_attachment", "aws_internet_gateway", "aws_launch_template",
    "aws_route", "aws_route_table", "aws_route_table_association", "aws_subnet",
    "aws_vpc", "helm_release", "terraform_data", "aws_cloudfront_distribution",
    "aws_cloudfront_function", "aws_cloudfront_vpc_origin", "aws_cloudwatch_log_stream",
    "aws_ec2_client_vpn_authorization_rule", "aws_ec2_client_vpn_endpoint",
    "aws_ec2_client_vpn_network_association", "aws_route53_record", "aws_route53_zone",
    "aws_security_group", "aws_vpc_security_group_egress_rule",
    "aws_vpc_security_group_ingress_rule",
}
action_counts: collections.Counter[str] = collections.Counter()
type_counts: collections.Counter[str] = collections.Counter()
managed_count = 0
for change in changes:
    if change.get("mode") == "data":
        continue
    managed_count += 1
    actions = change["change"]["actions"]
    action_counts.update(actions)
    type_counts.update([change["type"]])
    if change["type"] not in allowed:
        raise AssertionError(f"out-of-scope resource type: {change['type']}")
    if actions != ["create"]:
        raise AssertionError(f"unexpected actions for {change['address']}: {actions}")

if stage == "foundation":
    if type_counts["helm_release"] != 2:
        raise AssertionError("foundation plan must contain controller and Argo CD Helm releases")
    if type_counts["aws_eks_cluster"] != 1 or type_counts["aws_eks_node_group"] != 1:
        raise AssertionError("foundation plan must contain one EKS cluster and one node group")
    if type_counts["aws_budgets_budget"] != 1:
        raise AssertionError("foundation plan must include the 40/60/72 USD project budget")
    if any(type_counts[name] for name in (
        "aws_cloudfront_distribution", "aws_ec2_client_vpn_endpoint", "aws_route53_zone"
    )):
        raise AssertionError("foundation plan must not create edge/VPN resources")
else:
    required_edge = {
        "aws_cloudfront_distribution": 1,
        "aws_cloudfront_function": 1,
        "aws_cloudfront_vpc_origin": 1,
        "aws_ec2_client_vpn_endpoint": 1,
        "aws_ec2_client_vpn_network_association": 1,
        "aws_ec2_client_vpn_authorization_rule": 1,
        "aws_route53_zone": 1,
        "aws_route53_record": 1,
    }
    for resource_type, expected in required_edge.items():
        if type_counts[resource_type] != expected:
            raise AssertionError(f"edge plan requires {expected} {resource_type}")
    if type_counts["aws_eks_cluster"] or type_counts["aws_eks_node_group"] or type_counts["helm_release"]:
        raise AssertionError("edge plan must not recreate EKS or Helm releases")

print(json.dumps({"stage": stage, "actions": dict(action_counts), "resourceCount": managed_count, "resourceTypes": dict(sorted(type_counts.items()))}, indent=2))
