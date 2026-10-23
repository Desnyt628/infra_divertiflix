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

REPO_URL ?= https://github.com/Desnyt628/infra_divertiflix.git
REMOTE   ?= origin
BRANCH   ?= main

.PHONY: help update git-setup lint yamllint ansible-lint syntax tofu-fmt tofu-validate check hooks clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'

# For read-only clients: fetch the latest version and DISCARD any local change
# to tracked files. Untracked and git-ignored files (vault.yml, inventory,
# cert/, ...) are left alone. Works from a plain zip download (no .git folder).
update: git-setup ## Fetch the latest version, overwriting local changes to tracked files
	git fetch $(REMOTE) $(BRANCH)
	git checkout -f -B $(BRANCH) FETCH_HEAD
	@git branch --set-upstream-to=$(REMOTE)/$(BRANCH) $(BRANCH) >/dev/null 2>&1 || true
	@echo "Up to date: $$(git log -1 --format='%h %s (%cr)')"

# Make sure git is installed and this folder is a git clone of REPO_URL.
git-setup: ## Install git if missing and link this folder to the repo (zip download)
	@if ! command -v git >/dev/null 2>&1; then \
	  echo "git not found, installing it..."; \
	  SUDO=""; if [ "$$(id -u)" -ne 0 ]; then SUDO="sudo"; fi; \
	  if command -v apt-get >/dev/null 2>&1; then \
	    $$SUDO apt-get update && $$SUDO apt-get install -y git; \
	  elif command -v dnf >/dev/null 2>&1; then $$SUDO dnf install -y git; \
	  elif command -v yum >/dev/null 2>&1; then $$SUDO yum install -y git; \
	  elif command -v pacman >/dev/null 2>&1; then $$SUDO pacman -S --noconfirm git; \
	  elif command -v apk >/dev/null 2>&1; then $$SUDO apk add git; \
	  elif command -v brew >/dev/null 2>&1; then brew install git; \
	  else echo "No supported package manager: install git manually."; exit 1; fi; \
	fi
	@command -v git >/dev/null 2>&1 || { echo "git is still missing, aborting."; exit 1; }
	@if [ ! -d .git ]; then \
	  echo "No .git folder (zip download?): linking this folder to $(REPO_URL)"; \
	  git init -q -b $(BRANCH) . && git remote add $(REMOTE) $(REPO_URL); \
	fi
	@if ! git rev-parse --git-dir >/dev/null 2>&1; then \
	  echo "Trusting $(CURDIR) (different owner)"; \
	  git config --global --add safe.directory "$(CURDIR)"; \
	fi
	@if [ "$$(git remote get-url $(REMOTE) 2>/dev/null)" != "$(REPO_URL)" ]; then \
	  git remote remove $(REMOTE) 2>/dev/null || true; \
	  git remote add $(REMOTE) $(REPO_URL); \
	fi

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