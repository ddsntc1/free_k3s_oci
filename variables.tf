variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key_path" { type = string }
variable "region" { type = string }
variable "compartment_ocid" { type = string }


variable "availability_domain" {
description = "예: kIdk:AP-SEOUL-1-AD-1 (OCI 콘솔에서 확인)"
type = string
}


variable "ssh_public_key" {
description = "SSH 공개키 내용 (ssh-rsa/ed25519 ...)"
type = string
}


# --- Free budget friendly defaults ---
variable "node_count" { type = number default = 1 }
variable "ocpus_per_node" { type = number default = 1 }
variable "memory_gbs_per_node" { type = number default = 6 }
variable "boot_volume_gbs" { type = number default = 60 }


variable "vcn_cidr" { type = string default = "10.0.0.0/16" }
variable "subnet_cidr" { type = string default = "10.0.1.0/24" }