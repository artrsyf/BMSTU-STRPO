GITLAB_URL ?= http://gitlab.local:8929
REGISTRY_HOST ?= registry.local:5050
WORK_NAME ?= driving-school
KUBE_NAMESPACE ?= $(WORK_NAME)
K8S_OUT ?= .generated/$(WORK_NAME)
KUBECONFIG ?= $(HOME)/.kube/k3s.yaml
RUNNER_NAMESPACE ?= gitlab-runner
RUNNER_TOKEN ?=
STUDENT_NAME ?=
TOKEN_DURATION ?= 8h
API_SERVER ?=

export KUBECONFIG

.PHONY: help gitlab-up gitlab-down gitlab-logs gitlab-password wsl-local-dns k3s-check k3s-registry-config k3s-local-dns render-work work-namespace registry-secret runner-install runner-uninstall student-context work-status

help:
	@echo "Targets:"
	@echo "  make gitlab-up                 Start local GitLab CE"
	@echo "  make gitlab-password           Print initial GitLab root password"
	@echo "  make gitlab-logs               Follow GitLab logs"
	@echo "  make gitlab-down               Stop local GitLab CE"
	@echo "  make wsl-local-dns             Add local names to WSL /etc/hosts"
	@echo "  make k3s-check                 Check k3s cluster status"
	@echo "  make k3s-registry-config       Configure k3s containerd to use local HTTP registry"
	@echo "  make k3s-local-dns             Add gitlab.local/registry.local/labs.local to CoreDNS"
	@echo "  make render-work               Render namespace/RBAC manifests for WORK_NAME=$(WORK_NAME)"
	@echo "  make work-namespace            Apply namespace/quota/limits/RBAC for work"
	@echo "  make registry-secret           Create imagePullSecret; requires REGISTRY_USER=... REGISTRY_PASSWORD=..."
	@echo "  make runner-install            Install GitLab Runner; requires RUNNER_TOKEN=..."
	@echo "  make runner-uninstall          Remove GitLab Runner"
	@echo "  make student-context           Create limited kubeconfig; requires STUDENT_NAME=..."
	@echo "  make work-status               Show resources in work namespace"
	@echo ""
	@echo "Configuration:"
	@echo "  KUBECONFIG=$(KUBECONFIG)"
	@echo "  RUNNER_NAMESPACE=$(RUNNER_NAMESPACE)"
	@echo "  WORK_NAME=$(WORK_NAME)"

gitlab-up:
	docker compose up -d
	@echo "GitLab is starting at $(GITLAB_URL). First boot can take 5-10 minutes."

gitlab-down:
	docker compose down

gitlab-logs:
	docker logs -f simodo-local-gitlab

gitlab-password:
	docker exec -it simodo-local-gitlab cat /etc/gitlab/initial_root_password

wsl-local-dns:
	chmod +x configure-wsl-local-hosts.sh
	sh configure-wsl-local-hosts.sh

k3s-check:
	kubectl get nodes
	kubectl get pods -A

k3s-registry-config:
	sudo mkdir -p /etc/rancher/k3s
	sudo cp registries.yaml /etc/rancher/k3s/registries.yaml
	sudo systemctl restart k3s
	kubectl get nodes

k3s-local-dns:
	chmod +x configure-coredns-local-hosts.sh
	sh configure-coredns-local-hosts.sh

render-work:
	chmod +x render-work.sh
	WORK_NAME="$(WORK_NAME)" \
	KUBE_NAMESPACE="$(KUBE_NAMESPACE)" \
	K8S_OUT="$(K8S_OUT)" \
	RUNNER_NAMESPACE="$(RUNNER_NAMESPACE)" \
	sh render-work.sh

work-namespace: render-work
	kubectl apply -f $(K8S_OUT)/00-namespace.yaml
	kubectl apply -f $(K8S_OUT)/01-runner-deploy-rbac.yaml
	kubectl -n $(KUBE_NAMESPACE) get quota,limitrange

registry-secret:
	test -n "$(REGISTRY_USER)" || { echo "REGISTRY_USER is required"; exit 1; }
	test -n "$(REGISTRY_PASSWORD)" || { echo "REGISTRY_PASSWORD is required"; exit 1; }
	kubectl -n $(KUBE_NAMESPACE) create secret docker-registry gitlab-registry \
	  --docker-server=$(REGISTRY_HOST) \
	  --docker-username="$(REGISTRY_USER)" \
	  --docker-password="$(REGISTRY_PASSWORD)" \
	  --dry-run=client -o yaml | kubectl apply -f -

runner-install:
	test -n "$(RUNNER_TOKEN)" || { echo "RUNNER_TOKEN is required"; exit 1; }
	kubectl create namespace $(RUNNER_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	helm repo add gitlab https://charts.gitlab.io || true
	helm repo update
	helm upgrade --install gitlab-runner gitlab/gitlab-runner \
	  -n $(RUNNER_NAMESPACE) \
	  --set gitlabUrl=$(GITLAB_URL) \
	  --set runnerToken=$(RUNNER_TOKEN) \
	  -f runner-values.yaml
	kubectl -n $(RUNNER_NAMESPACE) rollout status deploy/gitlab-runner --timeout=180s

runner-uninstall:
	helm uninstall gitlab-runner -n $(RUNNER_NAMESPACE) || true

student-context:
	test -n "$(STUDENT_NAME)" || { echo "STUDENT_NAME is required"; exit 1; }
	chmod +x create-student-context.sh
	WORK_NAME="$(WORK_NAME)" \
	KUBE_NAMESPACE="$(KUBE_NAMESPACE)" \
	STUDENT_NAME="$(STUDENT_NAME)" \
	TOKEN_DURATION="$(TOKEN_DURATION)" \
	API_SERVER="$(API_SERVER)" \
	KUBECONFIG="$(KUBECONFIG)" \
	sh create-student-context.sh

work-status:
	kubectl -n $(KUBE_NAMESPACE) get deploy,po,svc,ingress,secret
