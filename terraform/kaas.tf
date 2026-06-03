
resource "infomaniak_kaas" "kluster" {
  public_cloud_id         = var.public_cloud_id
  public_cloud_project_id = var.public_cloud_project_id

  name               = "default"
  pack_name          = "shared"
  kubernetes_version = "1.35"
  region             = "dc3-a"

}


resource "infomaniak_kaas_instance_pool" "instance_pool" {
  public_cloud_id         = infomaniak_kaas.kluster.public_cloud_id
  public_cloud_project_id = infomaniak_kaas.kluster.public_cloud_project_id
  kaas_id                 = infomaniak_kaas.kluster.id

  name              = "instance-pool-1"
  flavor_name       = "a1-ram2-disk20-perf1"
  min_instances     = 1
  max_instances     = 1
  availability_zone = "dc3-a-10"

}
