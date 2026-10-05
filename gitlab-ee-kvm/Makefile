TOFU        ?= tofu
TF_DIR      := terraform
ANSIBLE_DIR := ansible
# 例: make provision ANSIBLE_ARGS="--ask-vault-pass"
ANSIBLE_ARGS ?=

.PHONY: help init plan apply provision up destroy lint

help:
	@echo "make init       - OpenTofu provider と Ansible collection を取得"
	@echo "make plan       - VM 作成内容の確認"
	@echo "make apply      - KVM 上に Rocky Linux 10 VM を作成"
	@echo "make provision  - VM に GitLab EE をインストール"
	@echo "make up         - apply + provision"
	@echo "make destroy    - VM とディスクを削除"
	@echo "make lint       - IaC の静的検査"

init:
	$(TOFU) -chdir=$(TF_DIR) init
	cd $(ANSIBLE_DIR) && ansible-galaxy collection install -r requirements.yml

plan:
	$(TOFU) -chdir=$(TF_DIR) plan

apply:
	$(TOFU) -chdir=$(TF_DIR) apply

provision:
	cd $(ANSIBLE_DIR) && ansible-playbook site.yml $(ANSIBLE_ARGS)

up: apply provision

destroy:
	$(TOFU) -chdir=$(TF_DIR) destroy

lint:
	$(TOFU) -chdir=$(TF_DIR) fmt -check -recursive
	$(TOFU) -chdir=$(TF_DIR) validate
	cd $(ANSIBLE_DIR) && ansible-lint site.yml
