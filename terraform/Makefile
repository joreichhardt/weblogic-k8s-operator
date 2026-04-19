PROFILE ?= $(shell grep -s 'kube_context' terraform.tfvars | awk -F'"' '{print $$2}')
PROFILE := $(if $(PROFILE),$(PROFILE),minikube)

.PHONY: apply plan destroy ocr-login

apply: _minikube_start
	terraform apply -auto-approve

plan: _minikube_start
	terraform plan

destroy:
	terraform destroy

ocr-login: _minikube_start
	eval $$(minikube docker-env --profile=$(PROFILE)) && docker login container-registry.oracle.com

_minikube_start:
	minikube start --profile=$(PROFILE)
	kubectl wait --for=condition=Ready node/$(PROFILE) --timeout=120s
	kubectl wait --for=condition=Available deployment/coredns -n kube-system --timeout=120s
