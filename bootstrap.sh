#!/bin/bash
set -e

echo "[+] installing core packages"
sudo apt update
sudo apt install -y curl wget unzip git docker.io ansible make gnupg lsb-release apt-transport-https ca-certificates

echo "[+] installing Go"
GO_VERSION=1.22.3
wget https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
rm go${GO_VERSION}.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
export PATH=$PATH:/usr/local/go/bin

echo "[+] installing Helm"
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "[+] installing Kind"
GO111MODULE=on go install sigs.k8s.io/kind@v0.23.0
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
export PATH=$PATH:$(go env GOPATH)/bin

echo "[+] installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

echo "[+] installing ansible collections"
ansible-galaxy collection install community.kubernetes
ansible-galaxy collection install community.general

echo "[+] done — reload your terminal if PATHs were updated"
