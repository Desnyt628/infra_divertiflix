# Divertiflix infra: shortcuts for the checks (the CI runs the same targets).
# Usage: make help

SHELL := /bin/bash
.DEFAULT_GOAL := help

ANSIBLE_DIR := ansible
TOFU_DIR    := tofu/proxmox

# Use the real vault password file when it exists, otherwise a dummy one:
# lint and syntax-check never decrypt anything, but ansible.cfg needs a file.
REAL_VAULT_PASS := $(HOME)/.vault_pass_divertiflix
ifneq ($(wildcard $(REAL_VAULT_PASS)),)
VAULT_PASS := $(REAL_VAULT_PASS)
else
VAULT_PASS := $(CURDIR)/.vault_pass_dummy
endif
export ANSIBLE_VAULT_PASSWORD_FILE := $(VAULT_PASS)

.PHONY: help lint yamllint ansible-lint syntax tofu-fmt tofu-validate check hooks clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'

$(CURDIR)/.vault_pass_dummy:
	@echo dummy > $@

lint: yamllint ansible-lint ## YAML and Ansible lint

yamllint: ## Lint every YAML file (rules in .yamllint)
	yamllint .

ansible-lint: $(VAULT_PASS) ## Lint the playbook and the roles
	cd $(ANSIBLE_DIR) && ansible-lint

syntax: $(VAULT_PASS) ## Ansible syntax-check (example inventory)
	@inv=$$(mktemp --suffix=.yml); \
	cp $(ANSIBLE_DIR)/inventory/hosts.yml.example $$inv; \
	cd $(ANSIBLE_DIR) && ansible-playbook -i $$inv playbook.yml --syntax-check; \
	rc=$$?; rm -f $$inv; exit $$rc

tofu-fmt: ## Check OpenTofu formatting
	tofu fmt -check -recursive -diff tofu/

tofu-validate: ## Validate the OpenTofu code (downloads the provider)
	tofu -chdir=$(TOFU_DIR) init -backend=false -input=false
	tofu -chdir=$(TOFU_DIR) validate

check: lint syntax tofu-fmt tofu-validate ## Run everything (same as the CI)

hooks: ## Enable the git pre-commit hooks (gitleaks)
	pre-commit install

clean: ## Remove the dummy vault password file
	rm -f .vault_pass_dummy
