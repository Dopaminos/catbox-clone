#!/bin/bash

set -e

# Check critical files
echo "Checking critical files..."
for file in deploy/k8s/kind-config.yaml deploy/k8s/catbox-deployment.yaml deploy/k8s/catbox-service.yaml services/catbox-clone/Dockerfile services/catbox-clone/main.go deploy/grafana/dashboards/catbox-dashboard.json; do
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

# Verify three nodes
echo "Verifying node count..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -ne 3 ]; then
    echo "Error: Expected 3 nodes, found $NODE_COUNT"
    exit 1
fi

# Allow scheduling on control-plane node
echo "Removing control-plane taint..."
kubectl taint nodes dev-cluster-control-plane node-role.kubernetes.io/control-plane:NoSchedule- || true

# Build and load catbox-clone Docker image
echo "Building and loading catbox-clone..."
docker build -t catbox-clone:dev -f services/catbox-clone/Dockerfile services/catbox-clone/ || { echo "Docker build failed"; exit 1; }
kind load docker-image catbox-clone:dev --name dev-cluster

# Deploy NGINX Ingress Controller
echo "Deploying NGINX Ingress..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
kubectl label nodes dev-cluster-worker ingress-ready=true
kubectl label nodes dev-cluster-worker2 ingress-ready=true
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s || { echo "Ingress not ready"; exit 1; }

# Install Prometheus and Grafana
echo "Installing Prometheus and Grafana..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring --create-namespace || { echo "Prometheus failed"; exit 1; }
helm install grafana grafana/grafana -n monitoring --set adminPassword=admin || { echo "Grafana failed"; exit 1; }

# Patch Kubernetes ServiceMonitors
echo "Patching Kubernetes ServiceMonitors..."
kubectl patch servicemonitor -n monitoring prometheus-kube-prometheus-kube-controller-manager --type='merge' -p '{"spec":{"endpoints":[{"port":"https-metrics","scheme":"https","tlsConfig":{"insecureSkipVerify":true}}]}}' || true
kubectl patch servicemonitor -n monitoring prometheus-kube-prometheus-kube-scheduler --type='merge' -p '{"spec":{"endpoints":[{"port":"https-metrics","scheme":"https","tlsConfig":{"insecureSkipVerify":true}}]}}' || true
kubectl patch servicemonitor -n monitoring prometheus-kube-prometheus-kube-etcd --type='merge' -p '{"spec":{"endpoints":[{"port":"https-metrics","scheme":"https","tlsConfig":{"insecureSkipVerify":true}}]}}' || true
kubectl delete servicemonitor -n monitoring prometheus-kube-prometheus-kube-proxy || true

# Wait for Grafana and Prometheus to be ready
echo "Waiting for Grafana and Prometheus to be ready..."
kubectl wait --namespace monitoring --for=condition=ready pod -l app.kubernetes.io/name=grafana --timeout=90s || { echo "Grafana not ready"; exit 1; }
kubectl wait --namespace monitoring --for=condition=ready pod -l app.kubernetes.io/name=prometheus --timeout=90s || { echo "Prometheus not ready"; exit 1; }

# Get Prometheus service cluster IP
echo "Retrieving Prometheus service IP..."
PROMETHEUS_IP=$(kubectl get svc -n monitoring prometheus-kube-prometheus-prometheus -o jsonpath='{.spec.clusterIP}')
if [ -z "$PROMETHEUS_IP" ]; then
    echo "Error: Could not retrieve Prometheus IP"
    exit 1
fi
PROMETHEUS_URL="http://${PROMETHEUS_IP}:9090"

# Port-forward Grafana temporarily
echo "Setting up Grafana port-forward..."
kubectl port-forward svc/grafana 3000:80 -n monitoring &
PORT_FORWARD_PID=$!
sleep 5

# Configure Prometheus data source in Grafana
echo "Configuring Prometheus data source..."
GRAFANA_URL="http://localhost:3000"
GRAFANA_ADMIN_USER="admin"
GRAFANA_ADMIN_PASSWORD="admin"
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
  --data "{
    \"name\": \"Prometheus\",
    \"type\": \"prometheus\",
    \"url\": \"${PROMETHEUS_URL}\",
    \"access\": \"proxy\",
    \"basicAuth\": false
  }" \
  ${GRAFANA_URL}/api/datasources || { echo "Failed to configure Prometheus data source"; kill $PORT_FORWARD_PID; exit 1; }

# Auto-import Grafana dashboard
echo "Importing Grafana dashboard..."
DASHBOARD_FILE="deploy/grafana/dashboards/catbox-dashboard.json"
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
  --data "{\"dashboard\": $(cat ${DASHBOARD_FILE}), \"overwrite\": true}" \
  ${GRAFANA_URL}/api/dashboards/db || { echo "Failed to import dashboard"; kill $PORT_FORWARD_PID; exit 1; }

# Stop port-forward
kill $PORT_FORWARD_PID
wait $PORT_FORWARD_PID 2>/dev/null || true

# Deploy catbox-clone
echo "Deploying catbox-clone..."
kubectl apply -f deploy/k8s/catbox-deployment.yaml
kubectl apply -f deploy/k8s/catbox-service.yaml
kubectl wait --for=condition=ready pod -l app=catbox-clone --timeout=60s || { echo "catbox-clone not ready"; exit 1; }

# Configure Prometheus ServiceMonitor in monitoring namespace
echo "Configuring ServiceMonitor..."
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: catbox-clone-monitor
  namespace: monitoring
spec:
  namespaceSelector:
    matchNames:
    - default
  selector:
    matchLabels:
      app: catbox-clone
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
    scheme: http
EOF

# Debug catbox-clone metrics
echo "Debugging catbox-clone metrics..."
kubectl port-forward svc/catbox-clone 8080:80 -n default &
CATBOX_PID=$!
sleep 5
curl -s http://localhost:8080/metrics | grep -E 'http_requests_total|catbox_storage_bytes|catbox_network_bytes_sent_total' || { echo "Failed to fetch catbox metrics"; kill $CATBOX_PID; exit 1; }
kill $CATBOX_PID
wait $CATBOX_PID 2>/dev/null || true

# Verify Prometheus targets
echo "Verifying Prometheus targets..."
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
PROMETHEUS_PID=$!
sleep 10
curl -s http://localhost:9090/api/v1/targets | grep -E '"scrapePool":"monitoring/catbox-clone-monitor/0"' || { echo "catbox-clone target not found"; curl -s http://localhost:9090/api/v1/targets; exit 1; }
kill $PROMETHEUS_PID
wait $PROMETHEUS_PID 2>/dev/null || true

echo "Setup complete. Access catbox-clone at http://localhost:8080 and Grafana at http://localhost:3000"