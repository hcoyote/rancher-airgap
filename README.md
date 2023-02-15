# rancher-airgap

A quick stub out of an airgapped Rancher install utilizing AWS EC2 infrastructure.


# Software Dependencies

* Terraform
* Ansible
* lablabs.rke Ansible module
* geerlingguy.docker Ansible module
* [rpardini/docker-registry-proxy](https://github.com/rpardini/docker-registry-proxy) docker container


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

# The environment being built

## Proxy

The proxy builds a single small node running docker in order to launch an instance of `rpardini/docker-registry-proxy`.

Additionally, we install tinyproxy to get around some configuration limitations in `docker-registry-proxy`. Tinyproxy runs outside of a container, directly in the proxy node OS.

The build out of the proxy node must come before the rancher build, due to the rancher-sg being heavily locked down from making outbound network connections.

The `docker-registry-proxy` will create two directories in /home/ubuntu for storing the proxy cache and the generated TLS CA and related certificates. The Ansible run will wait for the `ca.crt` to be accessible before continuing to the RKE install. 

*Note:* If the proxy build runs, but the certificate cannot be correctly generated _and_ downloaded to the RKE cluster, you will not be able to pull images required by launching pods.

*Warn:* If you ever destroy the proxy, or lose the certificates it generates, you will need to update these on the RKE cluster and fully restart it.

TODO: Replace with a container like https://github.com/kalaksi/docker-tinyproxy


## Rancher

The cluster is designed to be built out in an airgapped fashion using the `lablabs.rke` module. The initial list of containers for bootstrapping is defined in the playbook, but appears to be incomplete, as the build out stalls during rke2 bootstrapping if it cannot reach Docker Hub. 

As part of the ansible build out, we pre-seed the rancher build with the `docker-registry-proxy` self-signed CA and some additional environment variables to point Rancher to the proxy.

TODO: lablabs.rke2 only installs rke2, need to add support in this project for launching the Rancher management UI.

## Helm

We download and install Helm straight from Github.

## kubectl

We rely upon `kubectl` from the Rancher install, but it appears to place it in a non-obvious location under /var/lib. To facilitate easier interaction with the cluster, we make sure `/usr/local/bin/kubectl` is symlinked into the right location.

To make it easier to work with `kubectl` as an unprivileged user, make sure to copy `/etc/rancher/rke2/rke2.yaml` to `$HOME/.kube/config`

## stern

TODO: add the installation of `stern` to make dealing with Kubernetes log viewing easier


# Running the build


## Make targets for building
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

## How do I launch?

```
$ aws sso login
$ make tf-apply
$ make play
```

## Watching the docker proxy logs

```
ssh <proxynode>
sudo docker logs -f docker_registry_proxy
```

## Watching the tinyproxy logs

```
ssh <proxynode>
sudo tail -f /var/log/tinyproxy/tinproxy.log
```

## Connecting to your service 

For testing purposes, we're just going to use `kube port-forward` to validate connectivity to the service. Since we're airgapping the rancher install, any client connectivity would need a tunnel of some form inside the perimeter.

*Note: There are likely better ways to do this.*


### If a security group rule does not exist

If you do not have inbound ports open for your, you can create a tunnel with ssh.

```
ssh -L8080:localhost:8080 <rancher leader node>
kubectl port-forward -n <namespace> svc/<appname> 8080:8080
```

Then on your local machine, outside of the rke2 cluster, attempt to connect to http://localhost:8080/ with your browser


### If a security group rule exists

If you have an inbound port enabled for your security group, you can use `kubectl port-forward` to force open a listening port on the leader node's primary network interface.

```
ssh <rancher leader node>
kubectl port-forward --address 0.0.0.0 -n redpanda svc/redpanda-console 8080
```

This will make the leader node listen on 8080 to any incoming connection and then forward it to svc/redpanda-console
