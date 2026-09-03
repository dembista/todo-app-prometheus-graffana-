# --- SG Front : Internet -> Front (80/443), Admin -> Front (22 depuis son IP uniquement) ---
resource "aws_security_group" "front" {
  name        = "${var.project_name}-sg-front"
  description = "Autorise HTTP/HTTPS depuis Internet et SSH depuis admin uniquement"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP depuis Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS depuis Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH depuis IP administrateur uniquement"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  ingress {
    description = "Grafana depuis IP administrateur uniquement"
    from_port   = var.grafana_port
    to_port     = var.grafana_port
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    description = "Tout le trafic sortant autorise"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-front"
  }
}

# --- SG Back : uniquement accessible depuis Front, sur le port de l'API ---
resource "aws_security_group" "back" {
  name        = "${var.project_name}-sg-back"
  description = "Autorise uniquement le Front a atteindre API sur le port applicatif"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "API depuis le Front uniquement"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.front.id]
  }

  ingress {
    description     = "SSH depuis le Front uniquement, rebond bastion pour Ansible"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.front.id]
  }

  egress {
    description = "Tout le trafic sortant autorise, installation de paquets via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-back"
  }
}

# --- SG DB : uniquement accessible depuis Back, sur le port PostgreSQL ---
resource "aws_security_group" "db" {
  name        = "${var.project_name}-sg-db"
  description = "Autorise uniquement le Back a atteindre PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL depuis le Back uniquement"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.back.id]
  }

  ingress {
    description     = "SSH depuis le Front uniquement, rebond bastion pour Ansible"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.front.id]
  }

  egress {
    description = "Tout le trafic sortant autorise, installation de paquets via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-db"
  }
}