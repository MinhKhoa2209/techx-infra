variable "region" {
  type    = string
  default = "us-east-1"
  validation {
    condition     = var.region == "us-east-1"
    error_message = "This demo is restricted to us-east-1."
  }
}

variable "project" {
  type    = string
  default = "techx"
}

variable "environment" {
  type    = string
  default = "demo"
}

variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
  validation {
    condition     = length(var.availability_zones) == 2 && alltrue([for az in var.availability_zones : startswith(az, "us-east-1")]) && length(distinct(var.availability_zones)) == 2
    error_message = "Choose exactly two distinct us-east-1 availability zones."
  }
}

variable "public_access_cidrs" {
  type = list(string)
  validation {
    condition     = length(var.public_access_cidrs) == 1 && can(cidrhost(var.public_access_cidrs[0], 0)) && endswith(var.public_access_cidrs[0], "/32") && var.public_access_cidrs[0] != "0.0.0.0/32"
    error_message = "Set exactly one non-zero public IPv4 /32 for EKS API access."
  }
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
  validation {
    condition     = var.kubernetes_version == "1.35"
    error_message = "The reviewed demo contract pins Kubernetes 1.35."
  }
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
  validation {
    condition     = var.node_instance_type == "t3.medium"
    error_message = "The cost-reviewed demo permits one t3.medium only."
  }
}

variable "node_disk_size_gib" {
  type    = number
  default = 20
  validation {
    condition     = var.node_disk_size_gib == 20
    error_message = "The demo node root disk is fixed at 20 GiB."
  }
}

variable "addon_versions" {
  type = map(string)
  default = {
    vpc-cni    = "v1.22.3-eksbuild.1"
    kube-proxy = "v1.35.3-eksbuild.17"
    coredns    = "v1.13.2-eksbuild.11"
  }
  validation {
    condition     = toset(keys(var.addon_versions)) == toset(["vpc-cni", "kube-proxy", "coredns"]) && alltrue([for version in values(var.addon_versions) : startswith(version, "v")])
    error_message = "Pin exactly vpc-cni, kube-proxy, and coredns addon versions."
  }
}

variable "budget_alert_email" {
  type      = string
  default   = null
  nullable  = true
  sensitive = true
  validation {
    condition     = var.budget_alert_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a valid email address."
  }
}
