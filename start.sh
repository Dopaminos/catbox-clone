#!/bin/bash

set -e

# Check critical files
echo "Checking critical files..."
for file in deploy/k8s/kind-config.yaml deploy/k8s/catbox-deployment.yaml deploy/k8s/catbox-service.yaml services/catbox-clone/Dockerfile services/catbox-clone/main.go; do
    if [ ! -f "$file" ]; then
        echo "Error: $file is missing"
        exit 1
    fi
done

# Start Docker
echo "Starting Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Check and recreate Kind cluster
echo "Checking Kind cluster..."
if kind get clusters | grep -q "dev-cluster"; then
    echo "Deleting existing Kind cluster..."
    kind delete cluster --name dev-cluster
fi
kind create cluster --name dev-cluster --config deploy/k8s/kind-config.yaml
kubectl wait --for=condition=Ready nodes --all --timeout=60s || { echo "Cluster not ready"; exit 1; }

# Build and load catbox-clone Docker image
echo "Building and loading catbox-clone..."
docker build -t catbox-clone:dev -f services/catbox-clone/Dockerfile services/catbox-clone/ || { echo "Docker build failed"; exit 1; }
kind load docker-image catbox-clone:dev --name dev-cluster

# Deploy NGINX Ingress Controller
echo "Deploying NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s || { echo "Ingress not ready"; exit 1; }

# Install Prometheus and Grafana
echo "Installing Prometheus and Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace || { echo "Prometheus failed"; exit 1; }
helm install grafana grafana/grafana -n monitoring || { echo "Grafana failed"; exit 1; }

# Deploy catbox-clone
echo "Deploying catbox-clone..."
kubectl apply -f deploy/k8s/catbox-deployment.yaml
kubectl apply -f deploy/k8s/catbox-service.yaml
kubectl wait --for=condition=ready pod -l app=catbox-clone --timeout=60s || { echo "catbox-clone not ready"; exit 1; }

# Configure Prometheus ServiceMonitor
echo "Configuring ServiceMonitor..."
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

