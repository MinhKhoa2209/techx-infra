from __future__ import annotations

import collections
import json
import sys

plan = json.load(sys.stdin)
changes = plan.get("resource_changes", [])
allowed = {
    "aws_budgets_budget", "aws_cloudwatch_log_group", "aws_ecr_lifecycle_policy",
    "aws_ecr_repository", "aws_eks_addon", "aws_eks_cluster", "aws_eks_node_group",
    "aws_iam_openid_connect_provider", "aws_iam_policy", "aws_iam_role",
    "aws_iam_role_policy_attachment", "aws_internet_gateway", "aws_launch_template",
    "aws_route", "aws_route_table", "aws_route_table_association", "aws_subnet",
    "aws_vpc", "helm_release", "terraform_data",
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

if type_counts["helm_release"] != 2:
    raise AssertionError("plan must contain exactly controller and Argo CD Helm releases")
if type_counts["aws_eks_cluster"] != 1 or type_counts["aws_eks_node_group"] != 1:
    raise AssertionError("plan must contain one EKS cluster and one node group")
if type_counts["aws_budgets_budget"] != 1:
    raise AssertionError("final plan must include the 40/60/72 USD project budget")

print(json.dumps({"actions": dict(action_counts), "resourceCount": managed_count, "resourceTypes": dict(sorted(type_counts.items()))}, indent=2))
