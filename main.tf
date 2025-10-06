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

locals {
  total_ocpus           = var.node_count * var.ocpus_per_node
  total_memory_gbs      = var.node_count * var.memory_gbs_per_node
  total_boot_volume_gbs = var.node_count * var.boot_volume_gbs
}

check "always_free_limits" {
  assert = alltrue([
    local.total_ocpus <= 4,
    local.total_memory_gbs <= 24,
    local.total_boot_volume_gbs <= 200,
  ])

  error_message = <<EOT
Always Free 한도를 초과했습니다.
- 총 OCPU: ${local.total_ocpus} (한도 4)
- 총 메모리: ${local.total_memory_gbs}GB (한도 24GB)
- 총 부트 볼륨: ${local.total_boot_volume_gbs}GB (한도 200GB)
변수(node_count, ocpus_per_node, memory_gbs_per_node, boot_volume_gbs)를 조정하세요.
EOT
}

# --- Networking ---
resource "oci_core_vcn" "this" {
  cidr_block     = var.vcn_cidr
  compartment_id = var.compartment_ocid
  display_name   = "free-vcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "free-igw"
  is_enabled     = true
}

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "free-rt"
  route_rules = [{
    cidr_block        = "0.0.0.0/0"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }]
}

resource "oci_core_security_list" "sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.this.id
  display_name   = "free-sl"

  egress_security_rules = [{
    protocol    = "all"
    destination = "0.0.0.0/0"
  }]

  ingress_security_rules = [
    {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options = {
        min = 22
        max = 22
      }
    },
    {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options = {
        min = 80
        max = 80
      }
    },
    {
      protocol = "6"
      source   = "0.0.0.0/0"
      tcp_options = {
        min = 443
        max = 443
      }
    }
  ]
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

# --- Image lookup (Oracle Linux 8, latest) ---
data "oci_core_images" "ol8" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "8"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# --- Instances ---
resource "oci_core_instance" "node" {
  count               = var.node_count
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = format("k3s-node-%02d", count.index + 1)
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.ocpus_per_node
    memory_in_gbs = var.memory_gbs_per_node
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    display_name     = format("k3s-node-vnic-%02d", count.index + 1)
    hostname_label   = format("k3s%02d", count.index + 1)
  }

  source_details {
    source_type             = "image"
    image_id                = data.oci_core_images.ol8.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = base64encode(file("cloudinit.yaml"))
  }
}
