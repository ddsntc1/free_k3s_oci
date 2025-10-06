# free_k3s_oci

Oracle Cloud Infrastructure(OCI)의 **Always Free** 리소스만 사용해서 k3s 단일/소규모 클러스터를 만드는 Terraform 템플릿입니다. [pcy06/oci-free-fully-managed-k8s](https://github.com/pcy06/oci-free-fully-managed-k8s) 내용을 참고해 VM(Compute) + k3s 조합으로 재구성했으며, 매니지드 Kubernetes(OKE/CKE) 비용이 발생하지 않도록 설계했습니다.

## 🎯 목표

- **Compute**: Ampere A1 Free (총합 ≤ **4 OCPU / 24GB RAM**)
- **Block Volume**: 총합 ≤ **200GB** (부트 볼륨 포함)
- **네트워크**: VCN + Public Subnet + Internet Gateway (모두 Always Free)
- **Kubernetes**: k3s + Ingress-NGINX (baremetal 프로필)
- **완전 무료**: Always Free 한도를 넘으면 Terraform `check`가 실패하도록 가드 추가

## 🗂️ 파일 구조

```
free_k3s_oci/
├─ main.tf                  # VCN, Subnet, Instance, k3s cloud-init
├─ variables.tf             # 입력 변수 및 Always Free 검증
├─ outputs.tf               # SSH / k3s 안내 출력
├─ cloudinit.yaml           # k3s + Ingress-NGINX 자동 설치
└─ terraform.tfvars.example # 변수 입력 예시
```

## ✅ 기본 스펙

| 항목 | 기본값 | 비고 |
| --- | --- | --- |
| 노드 수 | 1 | 최대 4까지 검증 | 
| 노드 스펙 | 1 OCPU / 6GB RAM | Ampere A1 Flex |
| 부트 볼륨 | 60GB | 노드 수 × 60GB |
| 오픈 포트 | 22, 80, 443 | 필요 시 Security List 수정 |
| OS 이미지 | Oracle Linux 8 최신 | 리전/AD에 맞춰 자동 검색 |

Terraform `check "always_free_limits"`가 노드 수, vCPU, 메모리, 부트 볼륨 총합이 Always Free 한도를 넘는지 사전에 검증합니다.

## 🔧 빠른 시작

1. **Terraform 설치** (>= 1.5)
2. 이 리포지토리를 클론 또는 파일 복사 후 디렉터리로 이동
3. `terraform.tfvars.example`를 복사해 사용자 값을 입력
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```
4. OCI API 인증 정보 및 SSH 공개키를 `terraform.tfvars` 혹은 환경변수(`TF_VAR_*`)로 입력
5. `terraform init`
6. `terraform apply`
7. 출력(`k3s_info`) 안내에 따라 SSH 접속 및 `kubectl` 확인

### 환경변수 예시

```bash
export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..."
export TF_VAR_user_ocid="ocid1.user.oc1..."
export TF_VAR_fingerprint="aa:bb:cc:..."
export TF_VAR_private_key_path="$HOME/.oci/oci_api_key.pem"
export TF_VAR_region="ap-seoul-1"
export TF_VAR_compartment_ocid="ocid1.compartment.oc1..."
export TF_VAR_availability_domain="kIdk:AP-SEOUL-1-AD-1"
export TF_VAR_ssh_public_key="$(cat $HOME/.ssh/id_rsa.pub)"
```

### terraform.tfvars 예시

```hcl
tenancy_ocid       = "ocid1.tenancy.oc1..."
user_ocid          = "ocid1.user.oc1..."
fingerprint        = "aa:bb:cc:..."
private_key_path   = "~/.oci/oci_api_key.pem"
region             = "ap-seoul-1"
compartment_ocid   = "ocid1.compartment.oc1..."
availability_domain = "kIdk:AP-SEOUL-1-AD-1"
ssh_public_key     = "ssh-ed25519 AAAA... user@host"

# 필요 시 조정
# node_count        = 1
# ocpus_per_node    = 1
# memory_gbs_per_node = 6
# boot_volume_gbs   = 60
```

## ☁️ 배포 후 확인 절차

1. `terraform output ssh_examples` 명령으로 SSH 접속 명령 확인
2. SSH 로그인 후 `kubectl get nodes` 로 Ready 상태 확인
3. `kubectl get pods -n ingress-nginx` 로 Ingress Controller 상태 확인
4. 애플리케이션 배포 후 Ingress 리소스로 80/443 노출 (또는 NodePort)

`cloudinit.yaml`은 다음을 자동 실행합니다.

1. 패키지 업데이트 및 필수 도구 설치
2. k3s 서버 설치 (`INSTALL_K3S_EXEC="--write-kubeconfig-mode 644"`)
3. Ubuntu/opc/oracle 사용자에 `~/.kube/config` 심볼릭 링크 생성
4. 노드 Ready 대기
5. Ingress-NGINX(baremetal) 배포
6. firewalld가 있을 경우 22/80/443 허용

## 🧹 정리

리소스가 더 이상 필요 없으면 다음 명령으로 비용을 완전히 0원으로 유지하세요.

```bash
terraform destroy
```

## 📌 참고

- OCI Always Free 정책: <https://www.oracle.com/cloud/free/>
- k3s 문서: <https://docs.k3s.io>
- Ingress-NGINX Baremetal: <https://kubernetes.github.io/ingress-nginx/deploy/baremetal/>
