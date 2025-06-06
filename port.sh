echo "[+] port forwarding (localhost)"
kubectl port-forward svc/catbox-clone 8080:80 &
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
