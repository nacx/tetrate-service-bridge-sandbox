variable "cluster_id" {
  default = null
}

variable "tsb_fqdn" {
}

variable "gcp_k8s_regions" {
  default = []
}

variable "gcp_dns_project" {
  default = null
}

variable "external_dns_annotation_filter" {
  default = ""
}

variable "external_dns_label_filter" {
  default = ""
}

variable "external_dns_sources" {
  default = "service,ingress,istio-gateway"
}
