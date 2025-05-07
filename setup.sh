#!/bin/bash

set -e

# Check and install dependencies
echo "Checking dependencies..."
command -v docker >/dev/null 2>&1 || { echo "Installing Docker..."; sudo apt update; sudo apt install -y docker.io; }
command -v kubectl >/dev/null 2>&1 || { echo "Installing kubectl..."; curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"; sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; }
command -v kind >/dev/null 2>&1 || { echo "Installing Kind..."; curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64; sudo install -o root -g root -m 0755 kind /usr/local/bin/kind; }
command -v helm >/dev/null 2>&1 || { echo "Installing Helm..."; curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3; chmod 700 get_helm.sh; ./get_helm.sh; }

# Verify Docker service
echo "Checking Docker service..."
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
fi

# Create Kind cluster
echo "Creating Kind cluster..."
if ! kind get clusters | grep -q "dev-cluster"; then
    kind create cluster --name dev-cluster --config deploy/k8s/kind-config.yaml
else
    echo "Kind cluster dev-cluster already exists."
fi

# Verify cluster is ready
echo "Verifying cluster readiness..."
kubectl wait --for=condition=Ready nodes --all --timeout=60s || { echo "Cluster not ready"; exit 1; }

# Build and load catbox-clone Docker image
echo "Building and loading catbox-clone Docker image..."
docker build -t catbox-clone:dev -f services/catbox-clone/Dockerfile services/catbox-clone/ || { echo "Docker build failed"; exit 1; }
kind load docker-image catbox-clone:dev --name dev-cluster

# Deploy NGINX Ingress Controller
echo "Deploying NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s || { echo "Ingress controller not ready"; exit 1; }

# Install Prometheus and Grafana
echo "Installing Prometheus and Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace || { echo "Prometheus installation failed"; exit 1; }
helm install grafana grafana/grafana -n monitoring || { echo "Grafana installation failed"; exit 1; }

# Deploy catbox-clone
echo "Deploying catbox-clone..."
kubectl apply -f deploy/k8s/catbox-deployment.yaml
kubectl apply -f deploy/k8s/catbox-service.yaml
kubectl wait --for=condition=ready pod -l app=catbox-clone --timeout=60s || { echo "catbox-clone not ready"; exit 1; }

# Configure Prometheus ServiceMonitor
echo "Configuring Prometheus ServiceMonitor..."
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: catbox-clone-monitor
  namespace: default
spec:
  selector:
    matchLabels:
      app: catbox-clone
  endpoints:
  - port: http
    path: /metrics
EOF

# Verify service accessibility
echo "Verifying service accessibility..."
WSL_IP=$(ip addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if curl -s -f http://${WSL_IP}:8080/ >/dev/null; then
    echo "catbox-clone accessible at http://${WSL_IP}:8080/"
else
    echo "Warning: catbox-clone not accessible at http://${WSL_IP}:8080/"
fi
if curl -s -f http://10.244.1.5:9090/ >/dev/null; then
    echo "Prometheus accessible at http://10.244.1.5:9090/"
else
    echo "Warning: Prometheus not accessible at http://10.244.1.5:9090/"
fi
if curl -s -f http://${WSL_IP}:3000/ >/dev/null; then
    echo "Grafana accessible at http://${WSL_IP}:3000/ (admin/grafana)"
else
    echo "Warning: Grafana not accessible at http://${WSL_IP}:3000/"
fi

echo "Setup complete."
