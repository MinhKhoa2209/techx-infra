locals {
  name = "${var.project}-${var.environment}"
  tags = { Project = var.project, Environment = var.environment, ManagedBy = "terraform" }
}

module "vpc" {
  source             = "../../modules/vpc"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.tags
}

module "ecr" {
  source = "../../modules/ecr"
  names  = ["techx/frontend", "techx/catalog", "techx/order"]
  tags   = local.tags
}

module "eks" {
  source              = "../../modules/eks"
  cluster_name        = local.name
  kubernetes_version  = var.kubernetes_version
  subnet_ids          = module.vpc.public_subnet_ids
  public_access_cidrs = var.public_access_cidrs
  node_instance_type  = var.node_instance_type
  node_disk_size_gib  = var.node_disk_size_gib
  addon_versions      = var.addon_versions
  tags                = local.tags
}

module "aws_load_balancer_controller" {
  source            = "../../modules/aws-load-balancer-controller"
  cluster_name      = module.eks.cluster_name
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  chart_version     = "3.3.0"
  iam_policy_url    = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.3.0/docs/install/iam_policy.json"
  iam_policy_sha256 = "16f232c9d9f79366fe949c4550ad517a202380058a9e48d45a4e215044a20a6a"
  cluster_ready_id  = module.eks.coredns_addon_id
  tags              = local.tags
}

module "argocd" {
  source        = "../../modules/argocd"
  chart_version = "9.5.17"
  depends_on    = [module.aws_load_balancer_controller]
}

resource "aws_budgets_budget" "project" {
  count        = var.budget_alert_email == null ? 0 : 1
  name         = "${local.name}-hard-cap"
  budget_type  = "COST"
  limit_amount = "80"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = [format("user:Project$%s", var.project)]
  }

  dynamic "notification" {
    for_each = toset([40, 60, 72])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "ABSOLUTE_VALUE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
  tags = local.tags
}
