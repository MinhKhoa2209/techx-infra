output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "ecr_repository_urls" { value = module.ecr.repository_urls }
output "configure_kubectl_command" { value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}" }
output "public_frontend_url" { value = "Available only after Phase 8: http://<ingress-alb-hostname>/" }
