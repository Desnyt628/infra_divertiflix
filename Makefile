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

# Prefix for privileged commands (empty when already root).
BASHRC ?= $(HOME)/.bashrc

SUDO := $(shell if [ "$$(id -u)" -ne 0 ]; then echo sudo; fi)

# Fails with a clear message when we are not root and cannot use sudo.
SUDO_OK = if [ "$$(id -u)" -ne 0 ] && ! { command -v sudo >/dev/null 2>&1 && id -nG | tr ' ' '\n' | grep -qxE 'sudo|wheel'; }; then \
  echo "User $$(id -un) cannot use sudo. Either run as root (su -), or as root run:"; \
  echo "  usermod -aG sudo $$(id -un)   (then log out and back in)"; exit 1; fi

.PHONY: help deps deps-packages deps-opentofu deps-collections deps-ssh-key ssh-agent ssh-agent-remove update git-setup lint yamllint ansible-lint syntax tofu-fmt tofu-validate check hooks clean

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
	  $(SUDO_OK); \
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
	@if [ "$$(stat -c %u .)" != "$$(id -u)" ] && \
	   ! git config --global --get-all safe.directory | grep -qxF "$(CURDIR)"; then \
	  echo "Folder owned by another user: trusting $(CURDIR) (git safe.directory)"; \
	  git config --global --add safe.directory "$(CURDIR)"; \
	fi
	@if [ ! -d .git ]; then \
	  echo "No .git folder (zip download?): linking this folder to $(REPO_URL)"; \
	  git init -q -b $(BRANCH) . && git remote add $(REMOTE) $(REPO_URL); \
	fi
	@if [ "$$(git remote get-url $(REMOTE) 2>/dev/null)" != "$(REPO_URL)" ]; then \
	  git remote remove $(REMOTE) 2>/dev/null || true; \
	  git remote add $(REMOTE) $(REPO_URL); \
	fi

# ---------------------------------------------------------------------------
# Dependencies (Debian / Ubuntu). Safe to run again: everything is idempotent.
# ---------------------------------------------------------------------------
deps: deps-packages deps-opentofu deps-collections deps-ssh-key hooks ## Install everything needed (deploy + dev tools)
	@echo ""
	@echo "Dependencies installed. Still to do by hand (secrets are never handled here):"
	@echo "  - ssh-copy-id -i ~/.ssh/id_rsa root@<proxmox-ip>"
	@echo "  - export TF_VAR_proxmox_api_token='...'"
	@echo "  - create ~/.vault_pass_divertiflix (chmod 600) and fill vault.yml"

# apt packages: make, ssh client, Python, Ansible (+ collections), and the dev tools
deps-packages: git-setup
	@command -v apt-get >/dev/null 2>&1 || { echo "deps supports Debian/Ubuntu (apt) only."; exit 1; }
	@$(SUDO_OK)
	$(SUDO) apt-get update
	$(SUDO) apt-get install -y make openssh-client python3 curl gnupg ca-certificates \
	  ansible ansible-lint yamllint pre-commit

# OpenTofu is not in Debian's repos: add the official OpenTofu apt repository
# (signing keys in /etc/apt/keyrings, source in /etc/apt/sources.list.d/opentofu.list)
deps-opentofu: deps-packages
	@if command -v tofu >/dev/null 2>&1; then echo "OpenTofu already installed: $$(tofu version | head -1)"; else \
	  echo "Adding the official OpenTofu apt repository..."; \
	  $(SUDO) install -m 0755 -d /etc/apt/keyrings && \
	  curl -fsSL https://get.opentofu.org/opentofu.gpg | $(SUDO) tee /etc/apt/keyrings/opentofu.gpg >/dev/null && \
	  curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey | $(SUDO) gpg --no-tty --batch --dearmor --yes -o /etc/apt/keyrings/opentofu-repo.gpg >/dev/null && \
	  $(SUDO) chmod a+r /etc/apt/keyrings/opentofu.gpg /etc/apt/keyrings/opentofu-repo.gpg && \
	  printf '%s\n' \
	    'deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main' \
	    'deb-src [signed-by=/etc/apt/keyrings/opentofu.gpg,/etc/apt/keyrings/opentofu-repo.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main' \
	    | $(SUDO) tee /etc/apt/sources.list.d/opentofu.list >/dev/null && \
	  $(SUDO) chmod a+r /etc/apt/sources.list.d/opentofu.list && \
	  $(SUDO) apt-get update && $(SUDO) apt-get install -y tofu; \
	fi

# Ansible collections used by the roles, installed inside the repo (git-ignored)
deps-collections: deps-packages
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r collections/requirements.yml -p collections

# Create an SSH key only if none exists (ssh-keygen asks for the passphrase itself)
deps-ssh-key: deps-packages
	@if [ -f $(HOME)/.ssh/id_rsa ]; then echo "SSH key already exists, left untouched."; else \
	  mkdir -p $(HOME)/.ssh && chmod 700 $(HOME)/.ssh && \
	  ssh-keygen -t rsa -b 4096 -f $(HOME)/.ssh/id_rsa; \
	fi

# OPT-IN (not part of `make deps`): load the SSH key into an agent in every new terminal.
# OpenTofu connects to Proxmox through the ssh-agent, so the key must be loaded.
# Adds one marked block to ~/.bashrc; `make ssh-agent-remove` takes it out again.
ssh-agent: ## Opt-in: auto-start ssh-agent and load ~/.ssh/id_rsa from ~/.bashrc
	@if grep -q 'divertiflix ssh-agent' $(BASHRC) 2>/dev/null; then \
	  echo "Already present in $(BASHRC), nothing changed."; else \
	  printf '%s\n' '' \
	    '# >>> divertiflix ssh-agent (added by make ssh-agent) >>>' \
	    'if [ -z "$$SSH_AUTH_SOCK" ]; then eval "$$(ssh-agent -s)" >/dev/null; fi' \
	    'if [ -f "$$HOME/.ssh/id_rsa" ] && ! ssh-add -l >/dev/null 2>&1; then ssh-add "$$HOME/.ssh/id_rsa"; fi' \
	    '# <<< divertiflix ssh-agent <<<' >> $(BASHRC); \
	  echo "Block added to $(BASHRC). Open a new terminal (or run: source $(BASHRC))."; \
	fi

ssh-agent-remove: ## Remove the block added by `make ssh-agent`
	@sed -i '/# >>> divertiflix ssh-agent/,/# <<< divertiflix ssh-agent/d' $(BASHRC) 2>/dev/null; \
	  echo "Block removed from $(BASHRC) (if it was there)."

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