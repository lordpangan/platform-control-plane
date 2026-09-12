CLUSTER               ?= platform-brain
ANSIBLE_DIR           := ansible
BOOTSTRAP_DIR         := bootstrap/aws-state
AWS_PROFILE_BOOTSTRAP ?= platform-engineer-admin

VM_INVENTORY          := inventories/proxmox/hosts.yml
VM_HOSTNAME           ?= platform-vm

# Read a host var out of the (gitignored) proxmox inventory, so the VM's address,
# user and toolchain path live in exactly one place and never reach git.
# Lazy (`=`), so `make help` doesn't pay for an ansible-inventory call.
vm_fact  = $(shell cd $(ANSIBLE_DIR) && ansible-inventory -i $(VM_INVENTORY) --host $(VM_HOSTNAME) 2>/dev/null \
             | python3 -c "import json,sys; print(json.load(sys.stdin).get('$(1)',''))")
VM_SSH    = $(call vm_fact,ansible_user)@$(call vm_fact,ansible_host)
# A non-interactive SSH session skips the shell profile, so the VM's devbox-global
# toolchain isn't on PATH. Prepend tools_path — the same inventory var Ansible uses.
VM_ENV    = export PATH="$(call vm_fact,tools_path):$$PATH";

.DEFAULT_GOAL := help
.PHONY: help up up-vm down down-vm status status-vm argocd-password argocd-password-vm argocd-ui argocd-ui-vm argocd-apps-vm bootstrap-aws teardown-aws-state

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

status-vm:  ## Show pod health on the Proxmox VM cluster
	@ssh $(VM_SSH) '$(VM_ENV) kubectl get pods -A'

argocd-password:  ## Print the ArgoCD initial admin password (local cluster)
	@kubectl --context kind-$(CLUSTER) -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

argocd-password-vm:  ## Print the ArgoCD admin password (Proxmox VM cluster)
	@ssh $(VM_SSH) '$(VM_ENV) kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath="{.data.password}" | base64 -d'; echo

argocd-ui:  ## Port-forward the ArgoCD UI to https://localhost:8080 (local cluster)
	@echo "ArgoCD UI -> https://localhost:8080   (user: admin, password: make argocd-password)"
	@kubectl --context kind-$(CLUSTER) -n argocd port-forward svc/argocd-server 8080:443

argocd-ui-vm:  ## Tunnel + port-forward the VM's ArgoCD UI to https://localhost:8080
	@echo "ArgoCD UI -> https://localhost:8080   (user: admin, password: make argocd-password-vm)"
	@echo "Ctrl-C to close the tunnel."
	@ssh -L 8080:localhost:8080 $(VM_SSH) \
	  '$(VM_ENV) kubectl -n argocd port-forward svc/argocd-server 8080:443'

argocd-apps-vm:  ## Watch ArgoCD Applications sync on the VM (wave order)
	@ssh $(VM_SSH) '$(VM_ENV) kubectl -n argocd get applications -w'

bootstrap-aws:  ## One-time: create the AWS state backend + scoped IAM user
	@aws sts get-caller-identity --profile $(AWS_PROFILE_BOOTSTRAP) >/dev/null 2>&1 \
	  || aws sso login --profile $(AWS_PROFILE_BOOTSTRAP)
	cd $(BOOTSTRAP_DIR) && terraform init && terraform apply

teardown-aws-state:  ## Rare: destroy the AWS state backend + IAM user (empty the bucket first)
	cd $(BOOTSTRAP_DIR) && terraform destroy
