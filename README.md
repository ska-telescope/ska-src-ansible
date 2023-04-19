# srcnet\_ansible\_playbooks

This repository contains ansible playbooks to build (prospective) infrastructure required by the SRCNet. These playbooks enable clusterapi based Kubernetes deployments using the clusterapi collection from `ska-ser-ansible-collections.ska_collections` (https://gitlab.com/ska-telescope/sdi/ska-ser-ansible-collections), requiring roles from the `ska_collections.minikube` collection for building a management cluster with Minikube and the `ska_collections.k8s` collection for post workload cluster deployment processing and customisation.

Fundamentally, this is a collection of ansible helpers that facilitate the deployment of Kubernetes clusters using the [openstack cluster api provider](https://github.com/kubernetes-sigs/cluster-api-provider-openstack).

## Overview

The clusterapi operator is an operator that works on the same principles as any other Kubernetes custom resource definition. The operator is deployed in a "management cluster" along with the desired cloud infrastructure providers that provide the driver interface for communicating with the specific infrastructure context. See the [clusterapi reference]( https://cluster-api.sigs.k8s.io/user/concepts.html) for details.

To create a "workload cluster" the user defines a collection of manifests that describe the machine and cluster layout. The corresponding manifest is then generated (using `clusterctl generate cluster`) and applied to the management cluster, which in turn orchestrates the creation of the workload cluster by communicating with the infrastructure provider (openstack in this case) and driving the [kubeadm configuration manager](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).

The clusterapi manifest specification enables a set of "pre" and "post" kubeadm init hooks that are applied to both the control plane and worker nodes in the target workload cluster. These hooks enable customisations of the deployment to be injected into the deployment workflow. This cannot be achieved by the `clusterctl generate cluster` flow directly, so [kustomize](https://kustomize.io/) templates are used to inject the necessary changes. These templates add in the execution of specific ansible-playbook flows for both the control plane and worker nodes so that the hosts are customised and the necessary baseline services are installed into the workload cluster e.g. containerd mirror configs, docker, helm tools, pod networking etc.

## Deployment workflow

This workflow assumes the existence of an "infrastructure management" machine, that is, a machine that can run the playbooks to create both the management and workload clusters.

### Infrastructure machine

At this point, the infrastructure machine must be created manually. The recipe looks something like:

1. Create new VM, e.g. src-infrastructure-manager, l3.micro, Ubuntu 20.04, SRCNet network, 192.168.1.102
2. Install [ansible](https://docs.ansible.com/ansible/latest/installation\_guide/installation\_distros.html#installing-ansible-on-ubuntu)
3. Install the openstack ansible collection (`ansible-galaxy collection install git+https://opendev.org/openstack/ansible-collections-openstack`). At time of writing, the bleeding edge in the apt repository contains a bug.
3. Install openstack sdk w/ cli
4. Add a `clouds.yaml` at /etc/openstack/clouds.yaml. Add `clouds.capi.yaml` which contains the `cacert` key
5. Add kubectl

   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

### Management cluster

From the infrastructure machine, the deployment workflow proceeds via Makefiles targets. A full end-to-end example is shown below.

First we need to create the machine that will be used to host the management cluster:

```bash
  $ make create-capi-management-machine-openstack
```

The intermediate working directory (e.g. where inventory files will be stored) can either be specified in the Makefile or the role defaults.

Next, create the management cluster:

```bash
  $ make capi-management
```

The management cluster name can either be specified in the Makefile or as a ninja2 `default` in the playbook. 

### Workload cluster

Finally, create a workload cluster:

```bash
  $ make capi-workload
```

The workload cluster name can either be specified in the Makefile or as a ninja2 `default` in the playbook. The control plane and worker node count can either be specified in the Makefile or the role defaults.

## Notes/gotchas

- Currently need to add symlinks to get around the fact that relative paths are used in the `ska-ser-ansible-collections` collections, e.g. 

  ```bash
  $ sudo ln -s /opt/srcnet_ansible_playbooks/ska-ser-ansible-collections/resources resources
  ```

- Need two versions of `clouds.yaml`. When creating the management machine, the one at `/etc/openstack/clouds.yaml` is used. When driving clusterapi, the one specified in `capi_workload_deploy` playbook (`capi_capo_openstack_cloud_config`) is used. This is because the key `cacert` is required by the latter but prohibited by the former.

- Capi images are not built beforehand; they are instead made on the fly against vanilla ubuntu images with kubeadm pre/post init hooks using kustomize - see [here](https://gitlab.com/ska-telescope/sdi/ska-ser-ansible-collections/-/tree/main/resources/clusterapi/kustomize/capobase). These kustomize snippets are merged together before being put through `clusterctl` to generate the workload cluster manfiests. See `/tmp/capo-config.log` on the control/worker plane for logs. Likewise, pod networking is done after join with post init hooks. Trying to use capi specific images has previously led to errors where kubernetes tries to use docker for networking rather than containerd.

- The last step getting the workload kubeconfig currently fails. However, this can be gotten explicitly from the management cluster by e.g.:

  ```bash 
  $ kubectl get secret/test-workload-kubeconfig -o json | jq -r .data.value | base64 --decode > /tmp/kubeconfig
  $ cd /tmp/
  $ kubectl get nodes --kubeconfig /tmp/kubeconfig

  NAME                                STATUS   ROLES           AGE   VERSION
  test-workload-control-plane-ckzw6   Ready    control-plane   32m   v1.25.7
  test-workload-md-0-xjq6n            Ready    <none>          27m   v1.25.7
  test-workload-md-0-xzsz5            Ready    <none>          27m   v1.25.7
  ```

## Outstanding issues

- Relative paths are a problem, especially those using the magic variable playbook\_dir as we're calling our own playbooks. We've gotten around most of these by creating symlinks where it expects to find stuff, but obviously that's massively hacky. Doing this isn't always possible either e.g. ones that traverse directly to /  in our folder structure.
- Unattended upgrades cause some workload nodes to fail [here](https://gitlab.com/ska-telescope/sdi/ska-ser-ansible-collections/-/blob/main/ansible\_collections/ska\_collections/k8s/roles/k8s/tasks/main.yml#L22), sometimes. The number of retries needs to be bumped considerably.
- We had a podman buildah dependency fail - it couldn't find 1.28.0-1. Doing an apt list gave us an earliest available version of 1.29.0-1, so we changed this variable in the role.
- At one point we were inadvertently using an old version of the services ansible repo to which changes had been committed. This caused a playbook naming mismatch when it pulls the repo in the kustomize tools snippet & it subsequently fell over. Resolved by pulling the latest version of the repo but possibly worth adding either a commit hash or tag to the corresponding clone command so things can be pinned to a specific vers?
- Need to manually accept fingerprint for ssh connection to management machine

## Reference

[Confluence page](https://confluence.skatelescope.org/x/ZYkEDQ)
