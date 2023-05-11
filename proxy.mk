.PHONY: all 

PROXY_MACHINE_NAME 		?= srcnet-proxy-2#							leave blank for default defined in playbook
PROXY_SECURITY_GROUP_NAME	?= srcnet-proxy-sg#							leave blank for default defined in playbook
PROXY_MACHINE_FLOATING_IP	?= 130.246.215.177#							must be available in the pool
PROXY_TARGET_HOSTS_GROUP	?= proxy_machine#          						the target group name for the proxy in the inventories file
PROXY_MACHINE_IMAGE		?= centos-stream-8-nogui#						leave blank for default defined in playbook
PROXY_MACHINE_SSH_USER		?= centos#								leave blank for default defined in playbook
PROXY_CFG_DIR_ABSPATH		?= /opt/ska-src-ansible/src-services-deployment/haproxy/etc#		leave blank for default defined in role defaults	
WORKING_DIR_ABSPATH     	?= /opt/ska-src-ansible/tmp#						where inventories etc. will be kept

ANSIBLE_EXTRA_VARS = --extra-vars working_dir_abspath=$(WORKING_DIR_ABSPATH) \
		     --extra-vars proxy_target_hosts_group=$(PROXY_TARGET_HOSTS_GROUP)
ifneq ($(PROXY_MACHINE_NAME),) 
	ANSIBLE_EXTRA_VARS += --extra-vars proxy_machine_name=$(PROXY_MACHINE_NAME) 
endif
ifneq ($(PROXY_SECURITY_GROUP_NAME),)
        ANSIBLE_EXTRA_VARS += --extra-vars proxy_security_group_name=$(PROXY_SECURITY_GROUP_NAME)
endif
ifneq ($(PROXY_MACHINE_FLOATING_IP),)
        ANSIBLE_EXTRA_VARS += --extra-vars proxy_machine_floating_ip=$(PROXY_MACHINE_FLOATING_IP)
endif
ifneq ($(PROXY_MACHINE_IMAGE),)
        ANSIBLE_EXTRA_VARS += --extra-vars proxy_machine_image=$(PROXY_MACHINE_IMAGE)
endif
ifneq ($(PROXY_MACHINE_SSH_USER),)
        ANSIBLE_EXTRA_VARS += --extra-vars proxy_machine_ssh_user=$(PROXY_MACHINE_SSH_USER)
endif
ifneq ($(PROXY_CFG_DIR_ABSPATH),)
        ANSIBLE_EXTRA_VARS += --extra-vars proxy_cfg_dir_abspath=$(PROXY_CFG_DIR_ABSPATH)
endif


all: create-proxy-security-group-openstack create-proxy-machine-openstack install-haproxy

pre:

create-proxy-security-group-openstack: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./cloud_machine/playbooks/create_proxy_security_group_openstack.yml -vv

create-proxy-machine-openstack: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ansible-playbook $(ANSIBLE_EXTRA_VARS) ./cloud_machine/playbooks/create_proxy_machine_openstack.yml -vv

delete-proxy-machine-openstack: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
	ansible-playbook $(ANSIBLE_EXTRA_VARS) ./cloud_machine/playbooks/delete_proxy_machine_openstack.yml -vv

install-haproxy: pre
	ANSIBLE_HOST_KEY_CHECKING=False \
        ansible-playbook $(ANSIBLE_EXTRA_VARS) ./proxy_machine/playbooks/install_haproxy.yml -i $(WORKING_DIR_ABSPATH)/inventory.ini -vv
