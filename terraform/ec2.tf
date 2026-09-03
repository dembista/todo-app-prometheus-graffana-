# AMI Ubuntu 22.04 LTS.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  # AMI figee sur celle utilisee lors du dernier apply reussi, pour la
  # stabilite jusqu'a la soutenance. Passez a data.aws_ami.ubuntu.id si
  # vous voulez explicitement reprendre la derniere image disponible.
  ami_id = "ami-015cabafc8f6249fe"
}

resource "aws_key_pair" "admin" {
  key_name   = var.key_name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

# --- Front : sous-réseau public, IP publique ---
resource "aws_instance" "front" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.front.id]
  key_name                    = aws_key_pair.admin.key_name
  associate_public_ip_address = true

  tags = {
    Name = "${var.project_name}-front"
    Role = "front"
  }
}

# --- Back : sous-réseau privé, pas d'IP publique ---
resource "aws_instance" "back" {
  ami                     = local.ami_id
  instance_type           = var.instance_type
  subnet_id               = aws_subnet.private.id
  vpc_security_group_ids  = [aws_security_group.back.id]
  key_name                = aws_key_pair.admin.key_name

  tags = {
    Name = "${var.project_name}-back"
    Role = "back"
  }

  depends_on = [aws_nat_gateway.main]
}

# --- DB : sous-réseau privé, pas d'IP publique ---
resource "aws_instance" "db" {
  ami                     = local.ami_id
  instance_type           = var.instance_type
  subnet_id               = aws_subnet.private.id
  vpc_security_group_ids  = [aws_security_group.db.id]
  key_name                = aws_key_pair.admin.key_name

  tags = {
    Name = "${var.project_name}-db"
    Role = "db"
  }

  depends_on = [aws_nat_gateway.main]
}