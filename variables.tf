variable "cloud" {
  default = "azure"
}

locals {
  cloud = {
    aws   = module.aws_k8s
    azure = module.azure_k8s
  }
}

locals {
  jumpbox = {
    aws   = module.aws_jumpbox
    azure = module.azure_jumpbox
  }
}

locals {
  base = {
    aws   = module.aws_base
    azure = module.azure_base
  }
}

variable "name_prefix" {
  description = "name prefix"
}

variable "location" {
  description = "location"
}

variable "cidr" {
  description = "cidr"
}

variable "tsb_image_sync_username" {
}

variable "tsb_image_sync_apikey" {
}

variable "tsb_helm_username" {
  default = null
}

variable "tsb_helm_password" {
  default = null
}

variable "tsb_username" {
  default = "admin"
}

variable "tsb_password" {
}

variable "tsb_version" {
  default = "1.5.0"
}
variable "tsb_helm_version" {
  default = null
}
variable "tsb_fqdn" {
  default = "toa.cx.tetrate.info"
}
variable "dns_zone" {
  default = "cx.tetrate.info"
}

variable "tsb_org" {
  default = "tetrate"
}

variable "mp_as_tier1_cluster" {
  default = true
}
variable "jumpbox_username" {
  default = "tsbadmin"
}
variable "cluster_id" {
  default = 1
}

variable "aws_eks_k8s_version" {
  default = "1.21"
}

variable "azure_aks_k8s_version" {
  default = "1.22.6"
}

variable "aws_eks_app_clusters_count" {
  default = 1
}

variable "azure_aks_app_clusters_count" {
  default = 1
}
