CLUSTER     ?= platform-brain
ANSIBLE_DIR := ansible

.DEFAULT_GOAL := help
.PHONY: help up up-vm down status argocd-password

help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

up:  ## Build the brain locally (kind on this machine)
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventories/local/hosts.yml site.yml

up-vm:  ## Build the brain on the Proxmox VM (needs inventories/proxmox/hosts.yml)
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventories/proxmox/hosts.yml site.yml

down:  ## Delete the local kind cluster
	kind delete cluster --name $(CLUSTER)

down-vm:  ## Delete the kind cluster on the Proxmox VM
	cd $(ANSIBLE_DIR) && ansible-playbook -i inventories/proxmox/hosts.yml destroy.yml

status:  ## Show pod health across all namespaces
	kubectl --context kind-$(CLUSTER) get pods -A

argocd-password:  ## Print the ArgoCD initial admin password
	@kubectl --context kind-$(CLUSTER) -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo
