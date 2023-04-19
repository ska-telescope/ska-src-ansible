.PHONY: all create-capi-management-machine-openstack capi-management capi-workload pre

CAPI_MANAGEMENT_MACHINE_NAME 	?= "srcnet-capi-management-1"		# leave blank for default defined in playbook
CAPI_CLUSTER_NAME		?= "srcnet-workload-1"			# leave blank for default defined in playbook
CAPI_CONTROLPLANE_COUNT		?= 3 					# leave blank for default defined in role defaults
CAPI_WORKER_COUNT		?= 6					# leave blank for default defined in role defaults
WORKING_DIR_ABSPATH             ?= /opt/srcnet_ansible_playbooks/tmp
CAPI_MANAGEMENT_TARGET_HOSTS	?= "management_cluster"
CAPI_MANAGEMENT_KUBECONFIG	?= "/etc/kubeconfigs/$(CAPI_CLUSTER_NAME)"

ANSIBLE_EXTRA_VARS = --extra-vars working_dir_abspath=$(WORKING_DIR_ABSPATH) \
		     --extra-vars capi_management_target_hosts=$(CAPI_MANAGEMENT_TARGET_HOSTS) \
		     --extra-vars capi_management_kubeconfig=$(CAPI_MANAGEMENT_KUBECONFIG)
ifneq ($(CAPI_MANAGEMENT_MACHINE_NAME),) 
	ANSIBLE_EXTRA_VARS += --extra-vars capi_management_machine_name=$(CAPI_MANAGEMENT_MACHINE_NAME) 
endif
ifneq ($(CAPI_CLUSTER_NAME),)
	ANSIBLE_EXTRA_VARS += --extra-vars capi_cluster_name=$(CAPI_CLUSTER_NAME) 
endif
ifneq ($(CAPI_CONTROLPLANE_COUNT),)
	ANSIBLE_EXTRA_VARS += --extra-vars capi_controlplane_count=$(CAPI_CONTROLPLANE_COUNT) 
endif
ifneq ($(CAPI_WORKER_COUNT),)
	ANSIBLE_EXTRA_VARS += --extra-vars capi_worker_count=$(CAPI_WORKER_COUNT) 
endif	

all: create-capi-management-machine-openstack capi-management capi-workload

pre:
	git -C ska-ser-ansible-collections/ pull # update ska-ser-ansible-collections repo

create-capi-management-machine-openstack: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ansible-playbook $(ANSIBLE_EXTRA_VARS) ./cloud_machine/playbooks/create_capi_management_machine_openstack.yml -vv

delete-capi-management-machine-openstack: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ansible-playbook $(ANSIBLE_EXTRA_VARS) ./cloud_machine/playbooks/delete_capi_management_machine_openstack.yml -vv

capi-management: pre capi-management-containers capi-management-minikube capi-management-capo

capi-management-containers: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ANSIBLE_COLLECTIONS_PATHS=$(PWD)/ska-ser-ansible-collections/ \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./capi_management/playbooks/capi_management_containers.yml -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv 

capi-management-minikube: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ANSIBLE_COLLECTIONS_PATHS=$(PWD)/ska-ser-ansible-collections/ \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./capi_management/playbooks/capi_management_minikube.yml --tags "build" -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv 

capi-management-capo: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ANSIBLE_COLLECTIONS_PATHS=$(PWD)/ska-ser-ansible-collections/ \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./capi_management/playbooks/capi_management_capo.yml -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv 

capi-workload: pre capi-workload-deploy capi-workload-post

capi-workload-deploy: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ANSIBLE_COLLECTIONS_PATHS=$(PWD)/ska-ser-ansible-collections/ \
	ANSIBLE_LIBRARY=$(PWD)/ska-ser-ansible-collections/ansible_collections/ska_collections/clusterapi/plugins/modules \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./capi_workload/playbooks/capi_workload_deploy.yml -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv

capi-workload-post: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
        ANSIBLE_COLLECTIONS_PATHS=$(PWD)/ska-ser-ansible-collections/ \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./capi_workload/playbooks/capi_workload_post.yml -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv

capi-workload-delete: 
	ANSIBLE_HOST_KEY_CHECKING=False \
	ansible-playbook $(ANSIBLE_EXTRA_VARS) ./capi_workload/playbooks/capi_workload_delete.yml -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv
