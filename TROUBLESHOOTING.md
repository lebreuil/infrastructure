# Kubernetes Infrastructure Troubleshooting Guide

This guide covers common troubleshooting commands for the Infomaniak
managed Kubernetes infrastructure running NGINX Ingress, cert-manager,
Argo CD.

---

## Nodes

```bash
# List all nodes with status and roles
kubectl get nodes

# List nodes with labels
kubectl get nodes --show-labels

# Check resource allocation per node
kubectl describe nodes | grep -A8 "Allocated resources"

# Check which pods are running on a specific node
kubectl get pods -A -o wide --no-headers | grep <node-name>

# Count pods per node
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | sort | uniq -c | sort -rn

# Check node conditions (memory pressure, disk pressure etc.)
kubectl describe nodes | grep -A5 "Conditions:"
```

---

## Pods

```bash
# List all pods across all namespaces with node assignment
kubectl get pods -A -o wide

# List failed or evicted pods
kubectl get pods -A --field-selector=status.phase==Failed

# Delete all failed/evicted pods
kubectl get pods -A --field-selector=status.phase==Failed \
  -o json | kubectl delete -f -

# Describe a pod for detailed events and errors
kubectl describe pod <pod-name> -n <namespace>

# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check logs from previous crashed container
kubectl logs <pod-name> -n <namespace> --previous

# Check logs from a specific container in a pod
kubectl logs <pod-name> -n <namespace> -c <container-name>

# Check logs from all containers in a pod
kubectl logs <pod-name> -n <namespace> --all-containers

# Force delete a stuck terminating pod
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# Check events in a namespace sorted by time
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Watch events in real time
kubectl get events -n <namespace> --sort-by='.lastTimestamp' -w
```

---

## NGINX Ingress Controller

```bash
# Check NGINX ingress controller pods
kubectl get pods -n nginx-ingress

# Check all ingress resources across all namespaces
kubectl get ingress -A

# Describe a specific ingress
kubectl describe ingress <ingress-name> -n <namespace>

# Check NGINX ingress controller logs
kubectl logs -n nginx-ingress -l app.kubernetes.io/name=nginx-ingress --tail=50

# Check NGINX configuration for a specific host
kubectl exec -n nginx-ingress \
  $(kubectl get pods -n nginx-ingress -o jsonpath='{.items[0].metadata.name}') \
  -- nginx -T 2>/dev/null | grep -A10 "<hostname>"

# Check the LoadBalancer service and external IP
kubectl get svc -n nginx-ingress

# Test SSL directly against NGINX bypassing Cloudflare
curl -v --resolve "<domain>:443:<nginx-external-ip>" https://<domain>
```

---

## cert-manager

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check all certificates across all namespaces
kubectl get certificate -A

# Check certificate requests
kubectl get certificaterequest -A

# Describe a certificate for detailed status
kubectl describe certificate <cert-name> -n <namespace>

# Check ACME challenge status
kubectl get challenge -A

# Check ACME order status
kubectl get order -A

# Check the ClusterIssuer status
kubectl describe clusterissuer letsencrypt-prod

# Check TLS secrets
kubectl get secret <secret-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=50
```

---

## Argo CD

```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD application status
kubectl get application -n argocd

# Describe an ArgoCD application
kubectl describe application <app-name> -n argocd

# Retrieve the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50

```

---

## OpenStack / Infomaniak

```bash
# List worker node instance IDs (for OpenStack CLI)
kubectl get nodes -o jsonpath='{.items[*].spec.providerID}'

# Get subnet ID from a worker node port
openstack --os-cloud <cloud-name> port list \
  --server <instance-uuid> -f json

# List available flavors sorted by RAM
openstack --os-cloud <cloud-name> flavor list --sort-column RAM -f table

# List subnets
openstack --os-cloud <cloud-name> subnet list -f json

# Show subnet details
openstack --os-cloud <cloud-name> subnet show <subnet-id> -f json

# Check OpenStack CCM pods
kubectl get pods -n kube-system | grep cloud-controller

# Check OpenStack CCM logs
kubectl logs -n kube-system \
  -l app=openstack-cloud-controller-manager --tail=50
```

---

## Helm

```bash
# List all Helm releases across all namespaces
helm list -A

# Check values of an existing Helm release
helm get values <release-name> -n <namespace>

# Check Helm release history
helm history <release-name> -n <namespace>

# Uninstall a failed Helm release
helm uninstall <release-name> -n <namespace>

# Render chart templates locally without installing
helm template <release-name> <chart> --version <version> \
  --set <key>=<value>

# Check available chart values
helm show values <chart> --version <version>
```

---

## Terraform

```bash
# List all resources in Terraform state
terraform state list

# Show details of a specific resource
terraform state show '<resource-address>'

# Remove a resource from state without deleting it
terraform state rm '<resource-address>'

# Target a specific resource for apply
terraform apply -target=<resource-address>

# Target a specific resource for destroy
terraform destroy -target=<resource-address>

# Refresh state from real infrastructure
terraform refresh

# Check provider schema attributes
terraform providers schema -json | python3 -c "
import json, sys
schema = json.load(sys.stdin)
# Replace with the provider and resource you want to inspect
resource = schema['provider_schemas']['registry.terraform.io/<provider>']['resource_schemas']['<resource_name>']
print(json.dumps(list(resource['block']['attributes'].keys()), indent=2))
"
```

---

## Network Connectivity

```bash
# Test internet connectivity from a pod
kubectl run test-net --image=busybox --restart=Never -- \
  wget -qO- https://www.google.com
kubectl describe pod test-net
kubectl delete pod test-net

# Test Docker Hub connectivity from a pod
kubectl run test-pull --image=curlimages/curl --restart=Never -- \
  curl -I https://registry-1.docker.io
kubectl describe pod test-pull
kubectl delete pod test-pull

# Test image pull from Docker Hub
kubectl run test-image --image=<image>:<tag> --restart=Never
kubectl describe pod test-image
kubectl delete pod test-image

# Check node internet access
kubectl run test-curl --image=curlimages/curl --restart=Never -- \
  curl -I https://www.cloudflare.com/ips-v4
kubectl delete pod test-curl
```

---

## Common Issues and Solutions

| Symptom | Likely Cause | Solution |
|---|---|---|
| Pod `Pending` — node affinity | Wrong `nodeSelector` label | Check node labels with `kubectl get nodes --show-labels` |
| Pod `Pending` — insufficient resources | Node out of memory/CPU | Upgrade node flavor or add nodes |
| Pod `CrashLoopBackOff` | App crash or bad config | Check `kubectl logs --previous` |
| Pod `Evicted` | Node memory pressure | Check `kubectl describe nodes` allocated resources |
| `ContainerStatusUnknown` | Node failure or eviction | Delete pod, let it reschedule |
| Image pull `not found` | Wrong image tag | Check image exists on registry |
| Image pull `403 Forbidden` | Private image or rate limit | Add image pull secret |
| Helm `cannot re-use a name` | Failed release still exists | `helm uninstall <release> -n <namespace>` |
| Helm schema validation error | Helm 3.18.x regression | Add `disable_openapi_validation = true` |
| `kubectl logs` TLS timeout | Kubelet not directly reachable | Use `kubectl get pod -o yaml` instead |
| cert-manager challenge pending | DNS not propagated | Wait or check Cloudflare API token permissions |
| LoadBalancer IP pending | CCM not provisioning LB | Check CCM logs and subnet annotation |
| ArgoCD unreachable after deploy | Resource pressure evicted pods | Check pod status and node resources |
