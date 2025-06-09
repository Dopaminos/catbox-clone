#!/bin/bash
# deploy to remote prod env using ansible

set -e

echo "[+] running ansible playbooks"
ansible-playbook -i deploy/ansible/inventory.ini deploy/ansible/install_docker.yml
ansible-playbook -i deploy/ansible/inventory.ini deploy/ansible/install_k8s.yml
