variable "enabled" {
  type    = bool
  default = false
}

variable "name" { type = string }
variable "domain_name" { type = string }
variable "certificate_arn" { type = string }
variable "origin_alb_arn" { type = string }
variable "origin_domain_name" { type = string }
variable "tags" { type = map(string) }

