variable "enabled" {
  type    = bool
  default = false
}

variable "zone_name" { type = string }
variable "vpc_id" { type = string }
variable "alb_arn" { type = string }
variable "tags" { type = map(string) }

