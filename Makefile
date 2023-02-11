.PHONY: galaxy

default: 
	@echo "Makefile Help:\n\n"; 
	@grep '^# Target:' Makefile | sed -e 's/^# Target: //'

# Target: play - run playbook
play: galaxy
	ansible-playbook -i hosts.ini -v ansible/playbooks/rancher-airgap.yml	 --diff

# Target: vplay - more verbosity for ansible playbook run
vplay:  galaxy
	ansible-playbook -i hosts.ini -vv ansible/playbooks/rancher-airgap.yml	

# Target: galaxy - prereqs installation automatically run if requirements.yml is updated
galaxy: ansible/.requirements.yml.last_run

# galaxy calls this to trigger tracking of the touchfile so we know when we're up to date
ansible/.requirements.yml.last_run: ansible/requirements.yml
	ansible-galaxy install -r ansible/requirements.yml  && touch ansible/.requirements.yml.last_run
	


# Target: rke_local_artifacts - try to download rke artifacts for a copy-mode airgap install
rke_local_artifacts:
	mkdir -p local_artifacts
	for i in sha256sum-amd64.txt rke2.linux-amd64.tar.gz rke2-images.linux-amd64.tar.zst; do curl -LJO --output-dir local_artifacts https://github.com/rancher/rke2/releases/download/v1.25.3+rke2r1/$$i; done
	ls -l local_artifacts

# Target: tf-apply - run the terraform
tf-apply: test-aws-access
	cd aws && terraform apply

# Target: tf-destroy - bring down the Terraform build out and cleanup
tf-destroy: test-aws-access
	cd aws && terraform apply -destroy

# Target: test-aws-access - try to detect if no valid login session
test-aws-access:
	 @aws sts get-caller-identity --no-cli-pager --output text >/dev/null 2>&1 || (echo "No valid aws identity, try aws sso login first"; exit 1)

# Target: clean - clean everything
clean: clean_rke_local_artifacts


# Target: clean_rke_local_artifacts - cleanup the local artifact download location
clean_rke_local_artifacts:
	rm -rf local_artifacts


