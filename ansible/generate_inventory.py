#!/usr/bin/env python3
"""
Génère ansible/inventory/hosts.ini à partir des outputs Terraform
(cf. TP DevOps section 3.2 : "Utilisation d'un inventaire dynamique ou
généré à partir des sorties Terraform").

Usage : depuis le dossier ansible/ :
    python3 generate_inventory.py
"""
import json
import subprocess
import sys
from pathlib import Path

TERRAFORM_DIR = Path(__file__).parent.parent / "terraform"
OUTPUT_FILE = Path(__file__).parent / "inventory" / "hosts.ini"
SSH_KEY_PATH = "~/.ssh/medishop-todo"


def get_terraform_outputs():
    try:
        result = subprocess.run(
            ["terraform", f"-chdir={TERRAFORM_DIR}", "output", "-json"],
            capture_output=True,
            text=True,
            check=True,
        )
    except FileNotFoundError:
        sys.exit("Erreur : terraform n'est pas installé ou pas dans le PATH.")
    except subprocess.CalledProcessError as e:
        sys.exit(f"Erreur en lisant les outputs Terraform :\n{e.stderr}")

    data = json.loads(result.stdout)
    try:
        return {
            "front_ip": data["front_public_ip"]["value"],
            "back_ip": data["back_private_ip"]["value"],
            "db_ip": data["db_private_ip"]["value"],
        }
    except KeyError as e:
        sys.exit(
            f"Output manquant : {e}. Avez-vous bien lancé `terraform apply` avant ?"
        )


def main():
    ips = get_terraform_outputs()

    inventory = f"""# Fichier généré automatiquement par generate_inventory.py
# Ne pas éditer à la main : relancez le script après un terraform apply.

[front]
front ansible_host={ips['front_ip']}

[front:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[back]
back ansible_host={ips['back_ip']}

[db]
db ansible_host={ips['db_ip']}

[back:vars]
ansible_ssh_common_args='-o ProxyJump=ubuntu@{ips['front_ip']} -o StrictHostKeyChecking=no'

[db:vars]
ansible_ssh_common_args='-o ProxyJump=ubuntu@{ips['front_ip']} -o StrictHostKeyChecking=no'

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file={SSH_KEY_PATH}
ansible_python_interpreter=/usr/bin/python3
"""

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(inventory)
    print(f"Inventaire écrit dans {OUTPUT_FILE}")
    print(f"  front = {ips['front_ip']}")
    print(f"  back  = {ips['back_ip']}")
    print(f"  db    = {ips['db_ip']}")


if __name__ == "__main__":
    main()
