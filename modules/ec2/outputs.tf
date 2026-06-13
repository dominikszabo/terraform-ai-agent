output "bastion_id" {
  value = aws_instance.bastion.id
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "instance_profile_arn" {
  value = aws_iam_instance_profile.app.arn
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}
