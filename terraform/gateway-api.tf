
# kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

# Fetch manifest from a URL
data "http" "gateway_api_standard_install" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml"
}

# Split the multi-document YAML
data "kubectl_file_documents" "gateway_api" {
  content = data.http.gateway_api_standard_install.response_body
}

# Apply all resources
resource "kubectl_manifest" "gateway_api" {
  for_each  = data.kubectl_file_documents.gateway_api.manifests
  yaml_body = each.value

  server_side_apply = true
  wait              = true
}