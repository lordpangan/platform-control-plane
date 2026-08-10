CLUSTER               ?= platform-brain
ANSIBLE_DIR           := ansible
BOOTSTRAP_DIR         := bootstrap/aws-state
AWS_PROFILE_BOOTSTRAP ?= platform-engineer-admin

.DEFAULT_GOAL := help
.PHONY: help up up-vm down down-vm status argocd-password bootstrap-aws teardown-aws-state

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

bootstrap-aws:  ## One-time: create the AWS state backend + scoped IAM user
	@aws sts get-caller-identity --profile $(AWS_PROFILE_BOOTSTRAP) >/dev/null 2>&1 \
	  || aws sso login --profile $(AWS_PROFILE_BOOTSTRAP)
	cd $(BOOTSTRAP_DIR) && terraform init && terraform apply

teardown-aws-state:  ## Rare: destroy the AWS state backend + IAM user (empty the bucket first)
	cd $(BOOTSTRAP_DIR) && terraform destroy
