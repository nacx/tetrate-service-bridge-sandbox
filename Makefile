# Copyright (c) Tetrate, Inc 2021 All Rights Reserved.
# 
# Default variables
terraform_apply_args = -compact-warnings -auto-approve
terraform_destroy_args = -compact-warnings -auto-approve 
terraform_workspace_args = -force
terraform_output_args = -json
#terraform_apply_args = 
# Functions

.PHONY: all
all: tsb

.PHONY: help
help : Makefile
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n"} \
			/^[.a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36mmake %-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: init
init:  ## Terraform init
	@echo "Please refer to the latest instructions and terraform.tfvars.json file format at https://github.com/smarunich/tetrate-service-bridge-sandbox#usage"

.PHONY: k8s
k8s: azure_k8s aws_k8s gcp_k8s  ## Deploys k8s cluster for MP and N-number of CPs(*) 

.PHONY: azure_k8s
azure_k8s: init  ## Deploys azure k8s cluster for MP and N-number of CPs(*) leveraging AKS
	@/bin/sh -c '\
		index=0; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		jq -r '.azure_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		cluster_name="aks-$$name_prefix-$$region-$$index"; \
		echo "cloud=azure region=$$region cluster_id=$$index cluster_name=$$cluster_name"; \
		cd "infra/azure"; \
		terraform workspace new azure-$$index-$$region; \
		terraform workspace select azure-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -target module.azure_base -var-file="../../terraform.tfvars.json" -var=azure_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=azure_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform output ${terraform_output_args} | jq . > ../../outputs/terraform_outputs/terraform-azure-$$cluster_name-$$index.json; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'

.PHONY: aws_k8s
aws_k8s: init  ## Deploys EKS K8s cluster (CPs only)
	@/bin/sh -c '\
		index=0; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		jq -r '.aws_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		cluster_name="eks-$$name_prefix-$$region-$$index"; \
		echo "cloud=aws region=$$region cluster_id=$$index cluster_name=$$cluster_name"; \
		cd "infra/aws"; \
		terraform workspace new aws-$$index-$$region; \
		terraform workspace select aws-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=aws_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform output ${terraform_output_args} | jq . > ../../outputs/terraform_outputs/terraform-aws-$$cluster_name-$$index.json; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'

.PHONY: gcp_k8s
gcp_k8s: init  ## Deploys GKE K8s cluster (CPs only)
	@/bin/sh -c '\
		index=0; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		jq -r '.gcp_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		cluster_name="gke-$$name_prefix-$$region-$$index"; \
		echo "cloud=gcp region=$$region cluster_id=$$index cluster_name=$$cluster_name"; \
		cd "infra/gcp"; \
		terraform workspace new gcp-$$index-$$region; \
		terraform workspace select gcp-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -target module.gcp_base -var-file="../../terraform.tfvars.json" -var=gcp_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=gcp_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform output ${terraform_output_args} | jq . > ../../outputs/terraform_outputs/terraform-gcp-$$cluster_name-$$index.json; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'

.PHONY: tsb_mp
tsb_mp:  ## Deploys MP
	@echo "Refreshing k8s access tokens..."
	@make k8s
	@echo "Deploying TSB Management Plane..."
	@/bin/sh -c '\
		cloud=`jq -r '.tsb_mp.cloud' terraform.tfvars.json`; \
		fqdn=`jq -r '.tsb_fqdn' terraform.tfvars.json`; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		cluster_id=`jq .tsb_mp.cluster_id terraform.tfvars.json`; \
		region=`jq -r ."$$cloud"_k8s_regions[$$cluster_id] terraform.tfvars.json`; \
		cd "tsb/mp"; \
		terraform workspace select default; \
		terraform init; \
		terraform apply ${terraform_apply_args} -target=module.cert-manager -target=module.es -var-file="../../terraform.tfvars.json"; \
		terraform apply ${terraform_apply_args} -target=module.tsb_mp.kubectl_manifest.manifests_certs -var-file="../../terraform.tfvars.json"; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json"; \
		terraform output ${terraform_output_args} | jq . > ../../outputs/terraform_outputs/terraform-tsb-mp.json; \
		address=`jq -r "if .ingress_ip.value != \"\" then .ingress_ip.value else .ingress_hostname.value end" ../../outputs/terraform_outputs/terraform-tsb-mp.json`; \
		terraform -chdir=../../modules/$$cloud/register_fqdn init; \
		terraform -chdir=../../modules/$$cloud/register_fqdn apply ${terraform_apply_args} -var=address=$$address -var=fqdn=$$fqdn -var=name_prefix=$$name_prefix -var=cluster_id=$$cluster_id -var=region=$$region; \
		terraform workspace select default; \
		cd "../.."; \
		'

.PHONY: tsb_cp
tsb_cp:  ## Onboards CP on AKS cluster with ID=1
	@echo "Refreshing k8s access tokens..."
	@echo "Onboarding clusters, i.e. TSB CP rollouts..."
	@make gcp_k8s
	@/bin/sh -c '\
		index=0; \
		jq -r '.gcp_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		echo "cloud=gcp region=$$region cluster_id=$$index"; \
		cd "tsb/cp"; \
		terraform workspace new gcp-$$index-$$region; \
		terraform workspace select gcp-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=cloud=gcp -var=cluster_id=$$index; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@make aws_k8s
	@/bin/sh -c '\
		index=0; \
		jq -r '.aws_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		echo "cloud=aws region=$$region cluster_id=$$index"; \
		cd "tsb/cp"; \
		terraform workspace new aws-$$index-$$region; \
		terraform workspace select aws-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=cloud=aws -var=cluster_id=$$index; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@make azure_k8s
	@/bin/sh -c '\
		index=0; \
		jq -r '.azure_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		echo "cloud=azure region=$$region cluster_id=$$index"; \
		cd "tsb/cp"; \
		terraform workspace new azure-$$index-$$region; \
		terraform workspace select azure-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=cloud=azure -var=cluster_id=$$index; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'

.PHONY: tsb
tsb: k8s tsb_mp tsb_cp  ## Deploys a full environment (MP+CP)
	@echo "Magic is on the way..."

.PHONY: argocd
argocd:  ## Deploys ArgoCD
	@echo "Refreshing k8s access tokens..."
	@echo "Deploying ArgoCD on Management Plane..."
	@make gcp_k8s
	@/bin/sh -c '\
		index=0; \
		jq -r '.gcp_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		echo "cloud=gcp region=$$region cluster_id=$$index"; \
		cd "addons/argocd"; \
		terraform workspace new gcp-$$index-$$region; \
		terraform workspace select gcp-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=cloud=gcp -var=cluster_id=$$index; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@make aws_k8s
	@/bin/sh -c '\
		index=0; \
		jq -r '.aws_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		echo "cloud=aws region=$$region cluster_id=$$index"; \
		cd "addons/argocd"; \
		terraform workspace new aws-$$index-$$region; \
		terraform workspace select aws-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=cloud=aws -var=cluster_id=$$index; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@make azure_k8s
	@/bin/sh -c '\
		index=0; \
		jq -r '.azure_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		echo "cloud=azure region=$$region cluster_id=$$index"; \
		cd "addons/argocd"; \
		terraform workspace new azure-$$index-$$region; \
		terraform workspace select azure-$$index-$$region; \
		terraform init; \
		terraform apply ${terraform_apply_args} -var-file="../../terraform.tfvars.json" -var=cloud=azure -var=cluster_id=$$index; \
		terraform workspace select default; \
		let index++; \
		cd "../.."; \
		done; \
		'

.PHONY: destroy
destroy:  ## Destroy the environment
	@/bin/sh -c '\
		cloud=`jq -r '.tsb_mp.cloud' terraform.tfvars.json`; \
		fqdn=`jq -r '.tsb_fqdn' terraform.tfvars.json`; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		cluster_id=`jq .tsb_mp.cluster_id terraform.tfvars.json`; \
		region=`jq -r ."$$cloud"_k8s_regions[$$cluster_id] terraform.tfvars.json`; \
		address=`jq -r "if .ingress_ip.value != \"\" then .ingress_ip.value else .ingress_hostname.value end" outputs/terraform_outputs/terraform-tsb-mp.json`; \
		cd "modules/$$cloud/register_fqdn"; \
		terraform destroy ${terraform_apply_args} -var=address=$$address -var=fqdn=$$fqdn -var=name_prefix=$$name_prefix -var=cluster_id=$$cluster_id -var=region=$$region; \
		rm -rf terraform.tfstate.d/; \
		rm -rf terraform.tfstate; \
		cd "../../.."; \
		'
	@/bin/sh -c '\
		index=0; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		jq -r '.gcp_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		cluster_name="gke-$$name_prefix-$$region-$$index"; \
		echo "cloud=gcp region=$$region cluster_id=$$index cluster_name=$$cluster_name"; \
		cd "infra/gcp"; \
		terraform workspace select gcp-$$index-$$region; \
		terraform destroy ${terraform_destroy_args} -var-file="../../terraform.tfvars.json" -var=gcp_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform workspace select default; \
		terraform workspace delete ${terraform_workspace_args} gcp-$$index-$$region; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@/bin/sh -c '\
		index=0; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		jq -r '.aws_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		cluster_name="eks-$$name_prefix-$$region-$$index"; \
		echo "cloud=aws region=$$region cluster_id=$$index cluster_name=$$cluster_name"; \
		cd "infra/aws"; \
		terraform workspace select aws-$$index-$$region; \
		terraform destroy ${terraform_destroy_args} -var-file="../../terraform.tfvars.json" -var=aws_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform workspace select default; \
		terraform workspace delete ${terraform_workspace_args} aws-$$index-$$region; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@/bin/sh -c '\
		index=0; \
		name_prefix=`jq -r '.name_prefix' terraform.tfvars.json`; \
		jq -r '.azure_k8s_regions[]' terraform.tfvars.json | while read -r region; do \
		cluster_name="aks-$$name_prefix-$$region-$$index"; \
		echo "cloud=azure region=$$region cluster_id=$$index cluster_name=$$cluster_name"; \
		cd "infra/azure"; \
		terraform workspace select azure-$$index-$$region; \
		terraform destroy ${terraform_destroy_args} -var-file="../../terraform.tfvars.json" -var=azure_k8s_region=$$region -var=cluster_name=$$cluster_name -var=cluster_id=$$index; \
		terraform workspace select default; \
		terraform workspace delete ${terraform_workspace_args} azure-$$index-$$region; \
		let index++; \
		cd "../.."; \
		done; \
		'
	@/bin/sh -c '\
		cd "tsb/cp"; \
		rm -rf terraform.tfstate.d/; \
		rm -rf terraform.tfstate; \
		cd "../.."; \
		'
	@/bin/sh -c '\
		cd "addons/argocd"; \
		rm -rf terraform.tfstate.d/; \
		rm -rf terraform.tfstate; \
		cd "../.."; \
		'
