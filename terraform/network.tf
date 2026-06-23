# # Reads worker nodes using the stable custom label applied at
# # instance pool creation time.
# data "kubernetes_nodes" "workers" {
#   metadata {
#     labels = {
#       "custom.kaas.infomaniak.cloud/node-role" = "worker"
#     }
#   }
#   depends_on = [infomaniak_kaas_instance_pool.workers]
# }

# locals {
#   # Extracts the OpenStack instance UUID from the providerID.
#   # Format: openstack://<region>/<instance-uuid>
#   instance_id = regex(
#     "openstack://[^/]*/([a-f0-9-]+)",
#     data.kubernetes_nodes.workers.nodes[0].spec[0].provider_id
#   )[0]
# }

# # Looks up the OpenStack port attached to the first worker node
# # to retrieve its network_id.
# data "openstack_networking_port_v2" "worker" {
#   device_id  = local.instance_id
#   status     = "ACTIVE"
#   depends_on = [data.kubernetes_nodes.workers]
# }

# # Retrieves the current OpenStack authentication scope to get the
# # project UUID for filtering networking resources.
# # The OpenStack project UUID differs from the Infomaniak internal
# # project ID (var.public_cloud_project_id) and cannot be derived from it.
# data "openstack_identity_auth_scope_v3" "current" {
#   name = "current"
# }

# # Looks up the subnet using network_id and tenant_id as combined filters.
# # network_id alone returns multiple results across projects.
# # tenant_id alone returns too many subnets across all networks.
# # Together they uniquely identify the single subnet used by the cluster.
# data "openstack_networking_subnet_v2" "kaas" {
#   network_id = data.openstack_networking_port_v2.worker.network_id
#   tenant_id  = data.openstack_identity_auth_scope_v3.current.project_id
#   depends_on = [data.openstack_networking_port_v2.worker]
# }

# locals {
#   subnet_id = data.openstack_networking_subnet_v2.kaas.id
# }

# output "subnet_id" {
#   description = "OpenStack subnet ID used by the KaaS cluster"
#   value       = local.subnet_id
# }