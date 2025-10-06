variable "tenancy_ocid" {
  type        = string
  description = "OCI 테넌시 OCID"
}

variable "user_ocid" {
  type        = string
  description = "API 사용자 OCID"
}

variable "fingerprint" {
  type        = string
  description = "API 키 지문"
}

variable "private_key_path" {
  type        = string
  description = "API 개인키 경로 (~/.oci/oci_api_key.pem)"
}

variable "region" {
  type        = string
  description = "배포 리전 (예: ap-seoul-1)"
}

variable "compartment_ocid" {
  type        = string
  description = "리소스를 생성할 컴파트먼트 OCID"
}

variable "availability_domain" {
  type        = string
  description = "예: kIdk:AP-SEOUL-1-AD-1 (OCI 콘솔에서 확인)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH 공개키 내용 (ssh-rsa/ssh-ed25519 ...)"

  validation {
    condition     = can(regex("^ssh-", var.ssh_public_key))
    error_message = "ssh_public_key 변수에는 'ssh-' 로 시작하는 공개키 문자열을 입력해야 합니다."
  }
}

# --- Free budget friendly defaults ---
variable "node_count" {
  type    = number
  default = 1

  validation {
    condition     = var.node_count >= 1 && var.node_count <= 4
    error_message = "node_count 값은 1~4 사이여야 합니다 (Always Free 한도 고려)."
  }
}

variable "ocpus_per_node" {
  type    = number
  default = 1

  validation {
    condition     = var.ocpus_per_node > 0
    error_message = "ocpus_per_node 값은 0보다 커야 합니다."
  }
}

variable "memory_gbs_per_node" {
  type    = number
  default = 6

  validation {
    condition     = var.memory_gbs_per_node >= 1
    error_message = "memory_gbs_per_node 값은 최소 1GB 이상이어야 합니다."
  }
}

variable "boot_volume_gbs" {
  type    = number
  default = 60

  validation {
    condition     = var.boot_volume_gbs >= 50
    error_message = "boot_volume_gbs 값은 최소 50GB 이상이어야 합니다 (Oracle Linux 기본 권장)."
  }
}

variable "vcn_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}
