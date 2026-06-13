variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to use"
  default     = 2
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
