output "rds_endpoint" {
  value = aws_db_instance.this.endpoint
}

output "rds_arn" {
  value = aws_db_instance.this.arn
}

output "rds_address" {
  value = aws_db_instance.this.address
}
