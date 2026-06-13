variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of public subnet IDs"
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the ALB"
}

variable "environment" {
  type        = string
  description = "Environment name"
}

variable "certificate_arn" {
  type        = string
  description = "ARN of ACM certificate for HTTPS"
  default     = null
}

variable "health_check_path" {
  type        = string
  description = "Health check path"
  default     = "/health"
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}
