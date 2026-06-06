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

```bash
export GITHUB_APP_PEM=`cat path/to/app.private-key.pem`
```

exemple:
https://github.com/yyewolf/infra/blob/main/terraform/modules/flux-bootstrap/providers.tf
https://yewolf.fr/blog/building-my-infra-on-infomaniak-kubernetes-managed/#openstack-proxy

## get the github app installation id

Go to the Organization settings
Click on 'GitHub Apps' under 'Third-party Access'
If there are multiple GitHub apps, choose your App and click on 'Configure'
Once your GitHub App is selected check the URL for obtaining 'GitHub App Installation ID'
The URL looks like this:

https://github.com/organizations/<Organization-name>/settings/installations/<ID>
Pick the <ID> part and that's your GitHub App Installation ID.

https://github.com/organizations/lebreuil/settings/installations/138501007

flux create secret githubapp flux-system \
  --app-id=3927717 \
  --app-installation-id=138501007 \
  --app-private-key=lebreuil-fluxcd.2026-05-31.private-key.pem

  ## netbox installation

flux create source helm netbox \
    --url=oci://ghcr.io/netbox-community/netbox-chart/netbox \
    --interval=10m \
    --export > netbox-source.yaml
