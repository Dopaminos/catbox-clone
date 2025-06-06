#!/bin/bash
# run full dev setup with kind + prometheus + grafana

set -e

DOCKER_TAG=catbox-clone:dev
CLUSTER_NAME=catbox-cluster

if kind get clusters | grep -q "$CLUSTER_NAME"; then
  echo "[!] deleting existing kind cluster $CLUSTER_NAME"
  kind delete cluster --name "$CLUSTER_NAME"
fi

echo "[+] building dev image"
docker build -t $DOCKER_TAG ./services/catbox-clone

echo "[+] starting kind cluster"
kind create cluster --name $CLUSTER_NAME

echo "[+] loading docker image to kind"
kind load docker-image $DOCKER_TAG --name $CLUSTER_NAME

echo "[+] deploying application"
# skip non-k8s files manually
kubectl apply -f deploy/k8s/catbox-deployment.yaml
kubectl apply -f deploy/k8s/catbox-service.yaml
kubectl apply -f deploy/k8s/catbox-ingress.yaml

echo "[+] installing monitoring"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  -f deploy/monitoring/prometheus-values.yaml \
  -n monitoring --create-namespace

echo "[+] waiting for deployments to be ready"
kubectl wait --for=condition=available deployment/catbox-clone --timeout=90s
kubectl wait --for=condition=available deployment/prometheus-kube-prometheus-operator -n monitoring --timeout=90s
kubectl wait --for=condition=available deployment/prometheus-grafana -n monitoring --timeout=90s

echo "ready"