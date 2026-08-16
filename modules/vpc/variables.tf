variable "name" { type = string }

variable "vpc_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 20
    error_message = "vpc_cidr must be valid and large enough for two /24 subnets."
  }
}

variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "Exactly two distinct availability zones are required."
  }
}

variable "create_private_subnets" {
  type        = bool
  description = "Create two no-NAT private subnets for the internal ALB and CloudFront VPC origin."
  default     = false
}

variable "tags" { type = map(string) }
