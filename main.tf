terraform {
  required_version = ">= 1.5.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ---------------------------------------------------------
# Always Free 가드 (Micro 전환 시 OCPU/메모리는 고정이라 부트볼륨만 체크)
# ---------------------------------------------------------
locals {
  total_boot_volume_gbs = var.node_count * var.boot_volume_gbs
}

check "always_free_limits" {
  assert {
    condition     = (local.total_boot_volume_gbs <= 200)
    error_message = <<EOT
Always Free(블록 스토리지) 한도(200GB) 초과입니다.
- 총 부트 볼륨: ${local.total_boot_volume_gbs} GB (한도 200GB)
node_count 또는 boot_volume_gbs를 줄이세요.
EOT
  }
}

# -----------------
# Networking
# -----------------
resource "oci_core_vcn" "this" {
  cidr_block     = var.vcn_cidr
  compartment_id = var.compartment_ocid
  display_name   = "free-vcn"
  dns_label      = "freevcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "free-igw"
  enabled        = true
}

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "free-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_security_list" "sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "free-sl"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }

  # SSH 22
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP 80
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS 443
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_subnet" "public" {
  cidr_block                 = var.subnet_cidr
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.this.id
  display_name               = "free-public-subnet"
  route_table_id             = oci_core_route_table.rt.id
  security_list_ids          = [oci_core_security_list.sl.id]
  prohibit_public_ip_on_vnic = false
  dns_label                  = "pub"
}

# -------------------------------------------
# Image lookup (Oracle Linux 8, x86 for E2 Micro)
# -------------------------------------------
data "oci_core_images" "ol8_x86" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# -------------
# Instances
# -------------
resource "oci_core_instance" "node" {
  count               = var.node_count
  # Chuncheon은 AD가 1개뿐이므로 기존 var.availability_domain(AD-1) 사용 권장
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = format("k3s-node-%02d", count.index + 1)

  # >>> 핵심: E2 Micro (x86)로 전환
  shape = "VM.Standard.E2.1.Micro"

  # (중요) A1.Flex 전용 shape_config 블록은 제거해야 함
  # shape_config { ... }  # <-- 삭제

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    display_name     = format("k3s-node-vnic-%02d", count.index + 1)
    hostname_label   = format("k3s%02d", count.index + 1) # [a-z0-9-]만 허용
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ol8_x86.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("${path.module}/cloudinit.yaml"))
  }
}
