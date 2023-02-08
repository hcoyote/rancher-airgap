# rancher-airgap

A quick stub out of an airgapped Rancher install utilizing AWS EC2 infrastructure.


# Softwarae Dependencies

* Terraform
* Ansible
* lablabs.rke Ansible module


Note: The TF security group setup 

# API/metadata dependencies

## Github IP list

In attempting to lock down complete outbound access, we need to limit certain RKE setup operations to github locations. We need to gather the list of IP addresses used for `github.com`. For now, we do this manually and update the Terraform egress rule, using the following to generate the list.

```
curl -s https://api.github.com/meta | jq '[.web[] | select(. | contains("::")| not)]'
```
