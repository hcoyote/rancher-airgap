default: 
	@echo "Makefile Help:\n\n"; 
	@grep '^# Target:' Makefile | sed -e 's/^# Target: //'

# Target: play - run playbook
play:
	ansible-playbook -i hosts.ini -v ansible/playbooks/rancher-airgap.yml	

vplay: 
	ansible-playbook -i hosts.ini -vv ansible/playbooks/rancher-airgap.yml	
	

# Target: rke_local_artifacts - try to download rke artifacts for a copy-mode airgap install
rke_local_artifacts:
	mkdir -p local_artifacts
	for i in sha256sum-amd64.txt rke2.linux-amd64.tar.gz rke2-images.linux-amd64.tar.zst; do curl -LJO --output-dir local_artifacts https://github.com/rancher/rke2/releases/download/v1.25.3+rke2r1/$$i; done
	ls -l local_artifacts

# Target: tf-apply - run the terraform
tf-apply:
	cd aws && terraform apply

tf-destroy:
	cd aws && terraform apply -destroy

# Target: clean - clean everything
clean: clean_rke_local_artifacts


# Target: clean_rke_local_artifacts - cleanup the local artifact download location
clean_rke_local_artifacts:
	rm -rf local_artifacts


