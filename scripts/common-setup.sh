#!/bin/bash
# 3대(Control Plane, Worker x2) 모두에 공통으로 적용되는 kubeadm 사전작업
# 참고: https://kubernetes.io/docs/setup/production-environment/container-runtimes/
set -euo pipefail

echo ">>> [1/6] swap 비활성화"
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo ">>> [2/6] 커널 모듈 로드 (overlay, br_netfilter)"
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

echo ">>> [3/6] sysctl 네트워크 설정 (브릿지 트래픽이 iptables를 타도록)"
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo ">>> [4/6] containerd 설치"
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg apt-transport-https
sudo apt-get install -y containerd

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
# systemd cgroup driver 사용 (kubelet과 맞추기 위해 필수)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo ">>> [5/6] kubeadm, kubelet, kubectl 설치 (v1.30)"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo ">>> [6/6] 완료. 버전 확인"
kubeadm version
kubectl version --client
kubelet --version
echo ">>> $(hostname) 사전작업 완료"
