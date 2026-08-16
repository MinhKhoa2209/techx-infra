variable "enabled" {
  type    = bool
  default = false
}

variable "name" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_id" { type = string }
variable "client_cidr" { type = string }
variable "server_certificate_arn" { type = string }
variable "client_root_certificate_arn" { type = string }
variable "alb_security_group_id" { type = string }
variable "eks_security_group_id" { type = string }
variable "tags" { type = map(string) }
