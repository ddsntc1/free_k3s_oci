output "public_ips" {
  description = "프로비저닝된 k3s 노드의 공인 IP 목록"
  value       = [for n in oci_core_instance.node : n.public_ip]
}

output "ssh_examples" {
  description = "각 노드에 접속하기 위한 예시 SSH 명령"
  value       = [for n in oci_core_instance.node : format("ssh -i ~/.ssh/id_rsa opc@%s", n.public_ip)]
}

output "k3s_info" {
  description = "클러스터 접근 및 초기 확인 절차"
  value       = <<EOT
1) 위 public IP로 SSH 접속(기본 사용자: opc)
2) "kubectl get nodes" 로 Ready 확인
3) Ingress Controller 배포 완료까지 1~3분 대기
4) 서비스 노출은 Ingress 또는 NodePort로 구성
EOT
}
