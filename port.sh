# Set up port forwarding with kubectl
echo "Setting up port forwarding..."
kubectl port-forward svc/catbox-clone 8080:80 -n default &
sleep 2
kubectl port-forward svc/grafana 3000:80 -n monitoring &
sleep 2
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
sleep 2
# Verify services
echo "Verifying services..."
if curl -s -f http://localhost:8080/ >/dev/null; then
    echo "catbox-clone: http://localhost:8080/"
else
    echo "Warning: catbox-clone not accessible at http://localhost:8080/"
fi
if curl -s -f http://localhost:9090/ >/dev/null; then
    echo "Prometheus: http://localhost:9090/"
else
    echo "Warning: Prometheus not accessible at http://localhost:9090/"
fi
if curl -s -f http://localhost:3000/ >/dev/null; then
    echo "Grafana: http://localhost:3000/ (admin/grafana)"
else
    echo "Warning: Grafana not accessible at http://localhost:3000/"
fi

echo "Setup complete. Access services from Windows browser using localhost:<port>. Keep this terminal open for port forwarding."
