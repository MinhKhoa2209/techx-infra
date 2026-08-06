resource "helm_release" "this" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = "argocd"
  create_namespace = true
  atomic           = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    configs = { params = { "server.insecure" = true } }
    controller = {
      replicas  = 1
      resources = { requests = { cpu = "50m", memory = "128Mi" }, limits = { cpu = "250m", memory = "384Mi" } }
    }
    server = {
      replicas  = 1
      service   = { type = "ClusterIP" }
      resources = { requests = { cpu = "25m", memory = "64Mi" }, limits = { cpu = "200m", memory = "256Mi" } }
    }
    repoServer = {
      replicas  = 1
      resources = { requests = { cpu = "25m", memory = "128Mi" }, limits = { cpu = "250m", memory = "384Mi" } }
    }
    applicationSet = {
      replicas  = 1
      resources = { requests = { cpu = "25m", memory = "64Mi" }, limits = { cpu = "150m", memory = "192Mi" } }
    }
    dex           = { enabled = false }
    notifications = { enabled = false }
    redis = {
      resources = { requests = { cpu = "25m", memory = "32Mi" }, limits = { cpu = "100m", memory = "128Mi" } }
    }
  })]
}
