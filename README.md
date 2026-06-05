# Infomaniak
infomaniak cloud tests

## resources

[Infomaniak cloud documentation](https://docs.infomaniak.cloud/getting_started/)

[infomaniak provider documentation](https://registry.terraform.io/providers/Infomaniak/infomaniak/latest/docs)

[OpenStack provider documentation](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)

[Infomaniak s3 documentation](https://docs.infomaniak.cloud/object_storage/s3/)

## Setup the infomaniak public cloud

In the [Infomaniak manager](https://manager.infomaniak.com/v3/hosting/) create a cloud and a project.

Get the cloud.yaml file and copy it to the  ~/.config/openstack/ folder

In the the main.tf file update the openstack provider cloud parameter definition as:  <User>-<region>. 

Retrieve the [infomaniak token](https://www.infomaniak.com/en/support/faq/2582/add-and-manage-infomaniak-api-tokens)


## get kubeconfig

´´´
terraform output -raw kubeconfig > kubeconfig
´´´

## flux

[flux operator](https://github.com/controlplaneio-fluxcd/terraform-kubernetes-flux-operator-bootstrap)

[Terraform module](https://registry.terraform.io/modules/controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes/latest)