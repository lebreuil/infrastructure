
resource "infomaniak_kaas" "cluster" {
  public_cloud_id         = var.public_cloud_id
  public_cloud_project_id = var.public_cloud_project_id

  name               = "default"
  pack_name          = "shared"
  kubernetes_version = "1.35"
  region             = "dc3-a"

}


resource "infomaniak_kaas_instance_pool" "workers" {
  public_cloud_id         = infomaniak_kaas.cluster.public_cloud_id
  public_cloud_project_id = infomaniak_kaas.cluster.public_cloud_project_id
  kaas_id                 = infomaniak_kaas.cluster.id

  name              = "instance-pool-1"
  flavor_name       = "a1-ram2-disk20-perf1"
  min_instances     = 2
  max_instances     = 2
  availability_zone = "dc3-a-10"

  labels = {
    "custom.kaas.infomaniak.cloud/node-role" = "worker"
  }

}

