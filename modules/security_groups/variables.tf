variable "vpc_id" {
  type        = string
  description = "VPC ID to create security groups in"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR block allowed for SSH access to bastion"
  default     = "0.0.0.0/0"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
