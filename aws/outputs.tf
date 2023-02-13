terraform {
  required_version = ">= 1.0" 
}

output "leader" {
  value = {
    for instance in aws_instance.leader :
    instance.public_ip => instance.private_ip
  }
}

output "worker" {
  value = {
    for instance in aws_instance.worker :
    instance.public_ip => instance.private_ip
  }
}

output "proxy" {
  value = {
    for instance in aws_instance.proxy :
    instance.public_ip => instance.private_ip
  }
}

output "ssh_user" {
  value = var.distro_ssh_user[var.distro]
}

output "public_key_path" {
  value = var.public_key_path
}
