# SKA SRC Ansible

[[_TOC_]]

This repository contains ansible playbooks and makefile targets to build SKAOSRC IaC (infrastructure as code) in a self-documenting and repeatable way.

These playbooks assume the existence of an "infrastructure management" machine, that is, a machine to run the playbooks from.

## Creating an infrastructure machine

Currently the infrastructure machine must be created manually. The recipe looks something like:

1. Create a new VM on the same network as the management/workload machines will be
2. Install [ansible](https://docs.ansible.com/ansible/latest/installation\_guide/installation\_distros.html#installing-ansible-on-ubuntu)
3. Install the openstack ansible collection (`ansible-galaxy collection install git+https://opendev.org/openstack/ansible-collections-openstack`). At the time of writing, the latest edge version in the apt repository contains a bug, so we must use the bleeding edge version
3. Install the openstack sdk w/ cli
4. Add a `clouds.yaml` at `/etc/openstack/clouds.yaml` to enable communication with the openstack instance via the cli. Also add a duplicate `clouds.capi.yaml` containing the `cacert` key required by the clusterapi roles
5. Install kubectl:
```bash
$ curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
$ sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```
6. Clone this repository and initialise the dependent repositories (note that the `src-ansible-collections` repository, required by `proxy.mf` targets is currently private):
```bash
$ git submodule init && git submodule update
```

## Proxy machine (proxy.mf)

### Overview

These playbooks enable the creation of a HAProxy reverse proxy machine. By default, the makefile targets assume that the user has access to a private configuration repository, `src-services-deployment`, that contains part of the HAProxy configuration (userlists, frontends, backends), some of which is sensitive. 

Currently the procedure is only partly automated. The following needs to be done after machine creation:

- Add security groups for exposed ports, 
- Associate a floating IP to the instance, and
- Obtain SSL certs (assumes the CA is LetsEncrypt)

### Playbook listing

- `create_machine_openstack`
  - `create_proxy_machine_openstack`: create an instance for the proxy machine on Openstack
  - `delete_proxy_machine_openstack`: delete an instance of the proxy machine on Openstack
- `proxy_machine`
  - `install_haproxy`: install HAProxy on a centos machine

## Cluster API management and workload machines (capi.mf)

### Overview

These playbooks enable Cluster API based Kubernetes deployments using the `clusterapi` collection from `ska-ser-ansible-collections.ska_collections` (https://gitlab.com/ska-telescope/sdi/ska-ser-ansible-collections), requiring additional roles from the `ska_collections.minikube` collection for building a management cluster with Minikube and the `ska_collections.k8s` collection for post workload cluster deployment processing and customisation.

The Cluster API operator is an operator that works on the same principles as any other Kubernetes custom resource definition. The operator is deployed in a "management cluster" along with the desired cloud infrastructure providers, e.g. [the openstack cluster api provider](https://github.com/kubernetes-sigs/cluster-api-provider-openstack) that provide the driver interface for communicating with the specific infrastructure context. See the [clusterapi reference]( https://cluster-api.sigs.k8s.io/user/concepts.html) for details.

To create a "workload cluster" the user defines a collection of manifests that describe the machine and cluster layout. The corresponding manifest is then generated using `clusterctl generate cluster` and applied to the management cluster, which in turn orchestrates the creation of the workload cluster by communicating with the infrastructure provider (openstack in this case) and driving the [kubeadm configuration manager](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).

The Cluster API manifest specification enables a set of "pre" and "post" kubeadm init hooks that are applied to both the control plane and worker nodes in the target workload cluster. These hooks enable customisations of the deployment to be injected into the deployment workflow. This cannot be achieved by the `clusterctl generate cluster` flow directly, so [kustomize](https://kustomize.io/) templates are used to inject the necessary changes. These templates add in the execution of specific ansible-playbook flows for both the control plane and worker nodes so that the hosts are customised and the necessary baseline services are installed into the workload cluster e.g. containerd mirror configs, docker, helm tools, pod networking etc.

### Playbook listing

- `create_machine_openstack`
  - `create_capi_management_machine_openstack`: create an instance for the capi management machine on Openstack
  - `delete_capi_management_machine_openstack`: delete an instance of the capi management machine on Openstack
- `capi_workload`
  - `capi_workload_deploy`: create a capi workload cluster using the `ska_collections`.`clusterapi`.`createworkload` playbook
  - `capi_workload_post`:  deploy integral services on a capi workload cluster, e.g. ingress
  - `capi_workload_delete`: delete a capi workload cluster
- `capi_mananagement`
  - `capi_management_containers`: install containerisation  technologies on a capi management cluster
  - `capi_mmanagement_minikube`: install minikube on a capi management cluster
  - `capi_management_capo`: install clusterctl and the CAPO infrastructure provider on a capi management cluster

### Management cluster

From the infrastructure machine, the deployment workflow proceeds via Makefiles targets. A full end-to-end example is shown below.

First we need to create the machine that will be used to host the management cluster:

```bash
  $ make -f capi.mk  create-capi-management-machine-openstack
```

The intermediate working directory (e.g. where inventory files will be stored) can either be specified in the Makefile or the role defaults.

Next, create the management cluster:

```bash
  $ make -f capi.mk capi-management
```

The management cluster name can either be specified in the Makefile or as a ninja2 `default` in the playbook. 

### Workload cluster

Finally, create a workload cluster:

```bash
  $ make -f capi.mk  capi-workload
```

The workload cluster name can either be specified in the Makefile or as a ninja2 `default` in the playbook. The control plane and worker node count can either be specified in the Makefile or the role defaults.

### Notes & gotchas

- Currently need to add symlinks to get around the fact that relative paths are used in the `ska-ser-ansible-collections` collections, e.g. 

  ```bash
  $ sudo ln -s /opt/srcnet_ansible_playbooks/ska-ser-ansible-collections/resources resources
  ```

- Need two versions of `clouds.yaml`. When creating the management machine, the one at `/etc/openstack/clouds.yaml` is used. When driving clusterapi, the one specified in `capi_workload_deploy` playbook (`capi_capo_openstack_cloud_config`) is used. This is because the key `cacert` is required by the latter but prohibited by the former.

- Capi images are not built beforehand; they are instead made on the fly against vanilla ubuntu images with kubeadm pre/post init hooks using kustomize - see [here](https://gitlab.com/ska-telescope/sdi/ska-ser-ansible-collections/-/tree/main/resources/clusterapi/kustomize/capobase). These kustomize snippets are merged together before being put through `clusterctl` to generate the workload cluster manfests. See `/tmp/capo-config.log` on the control/worker plane for logs. Likewise, pod networking is done after join with post init hooks. *Trying to use capi specific images has previously led to errors where kubernetes tries to use docker for networking rather than containerd*.

- Roles in the `ska_collections`.`docker_base` collection have `defaults` that explictly specify package versions for e.g. buildah, crun. This has caused problems previously when these packages have been removed from apt repositories.

- Unattended upgrades cause some workload nodes to fail [here](https://gitlab.com/ska-telescope/sdi/ska-ser-ansible-collections/-/blob/main/ansible\_collections/ska\_collections/k8s/roles/k8s/tasks/main.yml#L22), sometimes.

## Reference

[Confluence page](https://confluence.skatelescope.org/x/ZYkEDQ)
