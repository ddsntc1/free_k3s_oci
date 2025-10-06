# free_k3s_oci
oci free tier로 쿠버네티스 배포환경 맹들기


# 🎯 Goal

**OCI 항상 무료(Always Free)** 한도 내에서 **완전 무료(₩0)** 로 k3s 단일/소규모 클러스터를 구성하고, 애플리케이션을 배포할 수 있는 최소 Terraform 템플릿과 절차입니다.

* **Compute**: Ampere A1 Free (총합 ≤ **4 OCPU / 24GB RAM**)
* **Block Volume 총합**: ≤ **200GB** (부트 볼륨 포함)
* **매니지드 LB/OKE 컨트롤 플레인 미사용** → 추가 비용 없음
* **k3s + Ingress-NGINX (baremetal)** 로 외부 노출

---

## 🗂️ 구조

```
free-k3s-oci/
├─ main.tf
├─ variables.tf
├─ outputs.tf
├─ cloudinit.yaml
└─ README.md (이 문서)
```

---

## ✅ 사양/구성(기본값)

* **노드 수**: `1` (원하면 2로 변경 가능)
* **각 노드 스펙**: `1 OCPU / 6 GB` (합계 1 OCPU / 6 GB)
* **부트 볼륨**: `60 GB` × 노드 수 (합계 60 GB)
* **네트워크**: VCN `10.0.0.0/16`, Public Subnet `10.0.1.0/24`
* **오픈 포트(보안리스트)**: `22, 80, 443` (필요 시 추가)
* **OS 이미지**: 최신 **Oracle Linux 8** (리전 자동 검색)

> 합계 한도를 유지하도록 변수에 기본값을 배치했습니다. 원하는 경우 아래 변수로 조정하세요.

---

## 🔧 사용 방법(빠른 시작)

1. **Terraform 설치** (로컬/CI 어디서든)
2. 디렉토리 생성 후 아래 파일들을 저장
3. `terraform init`
4. `terraform apply -auto-approve`
5. 출력(`k3s_info`)대로 SSH → `kubectl` 확인 → 앱 배포

> OCI 인증은 **환경변수** 또는 **변수 파일**로 제공합니다(둘 중 하나 선택). 아래 예시 참고.

---

## 🔐 OCI 인증 설정(택1)

### A) 환경변수로 설정

```bash
export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..."
export TF_VAR_user_ocid="ocid1.user.oc1..."
export TF_VAR_fingerprint="aa:bb:cc:..."
export TF_VAR_private_key_path="$HOME/.oci/oci_api_key.pem"
export TF_VAR_region="ap-seoul-1"      # 리전
export TF_VAR_compartment_ocid="ocid1.compartment.oc1..."

# SSH 공개키(필수)
export TF_VAR_ssh_public_key="$(cat $HOME/.ssh/id_rsa.pub)"
```

### B) terraform.tfvars 파일로 설정

```
tenancy_ocid       = "ocid1.tenancy.oc1..."
user_ocid          = "ocid1.user.oc1..."
fingerprint        = "aa:bb:cc:..."
private_key_path   = "~/.oci/oci_api_key.pem"
region             = "ap-seoul-1"
compartment_ocid   = "ocid1.compartment.oc1..."
ssh_public_key     = "ssh-ed25519 AAAA... user@host"
```

---

## 📄 cloudinit.yaml

> k3s 서버 설치(단일 노드), kubectl 사용권한, Ingress-NGINX(baremetal 프로필) 배포까지 자동화

```yaml
#cloud-config
package_update: true
package_upgrade: true
packages:
  - curl
  - git
  - tar
  - unzip
runcmd:
  - |
    echo "[1/5] Install k3s"
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
  - |
    echo "[2/5] Setup kubectl for ubuntu/oracle user if present"
    for U in ubuntu opc oracle; do
      if id "$U" >/dev/null 2>&1; then
        mkdir -p /home/$U/.kube
        ln -sf /etc/rancher/k3s/k3s.yaml /home/$U/.kube/config
        chown -R $U:$U /home/$U/.kube
      fi
    done
  - |
    echo "[3/5] Wait for node ready"
    until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
  - |
    echo "[4/5] Install Ingress-NGINX (baremetal)"
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
  - |
    echo "[5/5] Open basic firewall ports if firewalld exists"
    if command -v firewall-cmd >/dev/null 2>&1; then
      firewall-cmd --permanent --add-service=http || true
      firewall-cmd --permanent --add-service=https || true
      firewall-cmd --permanent --add-port=22/tcp || true
      firewall-cmd --reload || true
    fi
```

---

## 📄 main.tf

```hcl
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
  # most recent will be first
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
```

---

## 📄 variables.tf

```hcl
variable "tenancy_ocid"       { type = string }
variable "user_ocid"          { type = string }
variable "fingerprint"        { type = string }
variable "private_key_path"   { type = string }
variable "region"             { type = string }
variable "compartment_ocid"   { type = string }

variable "availability_domain" {
  description = "예: kIdk:AP-SEOUL-1-AD-1 (OCI 콘솔에서 확인)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH 공개키 내용 (ssh-rsa/ed25519 ...)"
  type        = string
}

# --- Free budget friendly defaults ---
variable "node_count"        { type = number default = 1 }
variable "ocpus_per_node"    { type = number default = 1 }
variable "memory_gbs_per_node" { type = number default = 6 }
variable "boot_volume_gbs"   { type = number default = 60 }

variable "vcn_cidr"    { type = string default = "10.0.0.0/16" }
variable "subnet_cidr" { type = string default = "10.0.1.0/24" }
```

---

## 📄 outputs.tf

```hcl
output "public_ips" {
  value = [for n in oci_core_instance.node : n.public_ip]
}

output "ssh_examples" {
  value = [for n in oci_core_instance.node : format("ssh -i ~/.ssh/id_rsa opc@%s", n.public_ip)]
}

output "k3s_info" {
  value = <<EOT
1) 위 public IP로 SSH 접속(기본 사용자: opc)
2) \"kubectl get nodes\" 로 Ready 확인
3) Ingress Controller 배포 완료까지 1~3분 대기
4) 서비스 노출은 Ingress 또는 NodePort로 구성
EOT
}
```

---

## 🚀 배포 후 점검

```bash
# SSH 접속 (예: 첫 번째 노드)
ssh -i ~/.ssh/id_rsa opc@<PUBLIC_IP>

# k3s 상태
kubectl get nodes -o wide
kubectl get pods -A

# Ingress-NGINX 확인
kubectl get ns ingress-nginx
kubectl get pods -n ingress-nginx -w
```

---

## 🌐 앱 배포 예시(myapp)

`myapp.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: myapp }
spec:
  replicas: 1
  selector: { matchLabels: { app: myapp } }
  template:
    metadata: { labels: { app: myapp } }
    spec:
      containers:
        - name: myapp
          image: ghcr.io/nginxinc/nginx-unprivileged:stable-alpine
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: myapp-svc }
spec:
  type: ClusterIP
  selector: { app: myapp }
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ing
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-svc
                port: { number: 80 }
```

배포:

```bash
kubectl apply -f myapp.yaml
kubectl get ingress myapp-ing -w
```

> baremetal 프로필은 기본적으로 NodePort를 이용하므로, VM 공인 IP + 노드포트/보안리스트 설정이 필요할 수 있습니다. 간단히는 `kubectl port-forward`로 빠르게 확인하세요.

---

## 🧮 한도 체크 가이드

* 총 OCPU = `node_count * ocpus_per_node` ≤ **4**
* 총 메모리(GB) = `node_count * memory_gbs_per_node` ≤ **24**
* 총 디스크(GB) = `node_count * boot_volume_gbs` ≤ **200**

> 2노드로 가려면: `node_count=2`, 각 노드 `1 OCPU / 6GB / 60GB` → 합계 **2 / 12GB / 120GB** (여유 충분)

---

## 🧩 확장 아이디어(무료 유지)

* **MetalLB**: 공용 IP/포트 설계가 필요할 때 L2 LB 도입
* **cert-manager + Let's Encrypt**: TLS 무료 자동화
* **OCIR(프라이빗 레지스트리)**: 이미지 푸시 후 `imagePullSecrets` 구성
* **Fail2ban/UFW**: SSH 보호, 불필요 포트 차단

---

## ❓자주 묻는 질문

* **Q. OKE를 쓰면 안 되나요?**
  A. OKE 컨트롤 플레인에 시간당 비용이 있어 ‘완전 무료’가 깨집니다. 본 템플릿은 VM + k3s로 0원 유지.

* **Q. Ubuntu로 바꾸고 싶어요**
  A. `data "oci_core_images"` 필터를 Ubuntu로 바꾸면 됩니다: `operating_system = "Canonical Ubuntu"`, `operating_system_version = "22.04"` 등.

* **Q. 접속 계정은?**
  A. Oracle Linux 기본 사용자 `opc` 입니다. Ubuntu는 `ubuntu`.

---

## 📌 다음 단계

원하시면, 여기에 **OCIR 로그인/시크릿 생성 자동화**, **Ingress + DNS + TLS(HTTPS)** 까지 붙인 버전을 확장해서 드릴게요. 또한, 현재 프로젝트의 **리소스/네임스페이스/헬스체크/리소스쿼터**까지 템플릿에 포함할 수 있습니다.
