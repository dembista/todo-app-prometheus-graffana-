variable "aws_region" {
  description = "Région AWS où provisionner l'infrastructure"
  type        = string
  default     = "eu-west-3" # Paris
}

variable "project_name" {
  description = "Préfixe utilisé pour nommer toutes les ressources"
  type        = string
  default     = "medishop-todo"
}

variable "availability_zone" {
  description = "Zone de disponibilité pour les subnets et instances"
  type        = string
  default     = "eu-west-3a"
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Bloc CIDR du sous-réseau public (Front)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Bloc CIDR du sous-réseau privé (Back, DB)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "Type d'instance EC2 (tier gratuit)"
  type        = string
  default     = "t3.micro"
}

variable "admin_ip" {
  description = "IP publique de l'administrateur, autorisée en SSH sur le Front (format CIDR, ex: 1.2.3.4/32)"
  type        = string
  # Pas de valeur par défaut : à fournir obligatoirement dans terraform.tfvars
}

variable "ssh_public_key_path" {
  description = "Chemin local vers la clé publique SSH à injecter dans les instances"
  type        = string
  default     = "~/.ssh/medishop-todo.pub"
}

variable "key_name" {
  description = "Nom donné à la key pair AWS"
  type        = string
  default     = "medishop-todo-key"
}

variable "backend_port" {
  description = "Port sur lequel écoute l'API backend (Express)"
  type        = number
  default     = 3000
}

variable "db_port" {
  description = "Port sur lequel écoute PostgreSQL"
  type        = number
  default     = 5432
}

variable "node_exporter_port" {
  description = "Port d'ecoute de node_exporter (metriques systeme)"
  type        = number
  default     = 9100
}

variable "grafana_port" {
  description = "Port d'ecoute de Grafana (dashboard admin uniquement)"
  type        = number
  default     = 3001
}