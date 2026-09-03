output "front_public_ip" {
  description = "IP publique de l'instance Front (à pointer avec votre nom de domaine)"
  value       = aws_instance.front.public_ip
}

output "back_private_ip" {
  description = "IP privée de l'instance Back"
  value       = aws_instance.back.private_ip
}

output "db_private_ip" {
  description = "IP privée de l'instance DB"
  value       = aws_instance.db.private_ip
}

output "ssh_command_front" {
  description = "Commande pour se connecter en SSH au Front"
  value       = "ssh -i ~/.ssh/medishop-todo ubuntu@${aws_instance.front.public_ip}"
}

output "front_security_group_id" {
  description = "ID du Security Group du Front (utilisé par le pipeline CI/CD pour s'auto-whitelister temporairement en SSH)"
  value       = aws_security_group.front.id
}