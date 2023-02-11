# rancher-airgap

A quick stub out of an airgapped Rancher install utilizing AWS EC2 infrastructure.


# Software Dependencies

* Terraform
* Ansible
* lablabs.rke Ansible module
* geerlingguy.docker Ansible module
# [rpardini/docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy) docker container


Note: The TF security group setup 

# API/metadata dependencies

## Github IP list

In attempting to lock down complete outbound access, we need to limit certain RKE setup operations to github locations. We need to gather the list of IP addresses used for `github.com`. For now, we do this manually and update the Terraform egress rule, using the following to generate the list.

```
curl -s https://api.github.com/meta | jq '[.web[] | select(. | contains("::")| not)]'
```

# Terraform Layout

This build works only for AWS.

This will build a VPC that contains two security groups, one for a proxy node that has full outbound access, and one for the locked down rancher/rke2 cluster. The two security groups are linked so nodes in one can communicate with nodes in the other. This is to facilitate using the proxy for container downloads.

## Rancher

## Proxy

The proxy builds a single small node running docker in order to launch an instance of `rpardini/docker-registry-proxy`.


# Running the build

The repo contains a `Makefile` with several targets to facilitate launching things.

```
$ make
Makefile Help:


play - run playbook
vplay - more verbosity for ansible playbook run
galaxy - prereqs installation automatically run if requirements.yml is updated
rke_local_artifacts - try to download rke artifacts for a copy-mode airgap install
tf-apply - run the terraform
tf-destroy - bring down the Terraform build out and cleanup
test-aws-access - try to detect if no valid login session
clean - clean everything
clean_rke_local_artifacts - cleanup the local artifact download location
```
