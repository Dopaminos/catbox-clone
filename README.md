# catbox-clone 🐱📦

a minimal file hosting microservice with prometheus metrics, kubernetes deployment, and ci/cd automation.

---

## features

- drag-and-drop file uploads
- prometheus metrics on `/metrics`
- grafana dashboard support
- automatic deployment via:
  - `dev.sh` + kind for local
  - `prod.sh` + ansible for prod
- github actions workflows for ci

---

## usage

### dev (local via kind)

`
./dev.sh
`
opens

- app: http://localhost:8080
- prometheus: http://localhost:9090
- grafana: http://localhost:3000

`
./prod.sh
`
requires ansible inventory configured and ssh access to remote host

---

## metrics exposed on `/metrics` (prometheus format):
- http_requests_total
- http_request_duration_seconds
- catbox_storage_bytes
- catbox_network_bytes_sent_total
- catbox_network_bytes_received_total

## development
```
cd services/catbox-clone
go test ./...
```

