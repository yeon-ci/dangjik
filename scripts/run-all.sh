#!/bin/bash
# 로컬(Git Bash)에서 실행 — 3대 노드에 순서대로 사전작업 스크립트를 복사·실행합니다.
set -euo pipefail

KEY="keys/dangjik-key.pem"
SCRIPT="scripts/common-setup.sh"

declare -A NODES=(
  [k8s-control-plane]="13.124.213.82"
  [k8s-worker-1]="54.180.141.193"
  [k8s-worker-2]="52.78.166.114"
)

for name in "${!NODES[@]}"; do
  ip="${NODES[$name]}"
  echo "=================================================="
  echo ">>> $name ($ip) 사전작업 시작"
  echo "=================================================="

  scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$SCRIPT" ubuntu@"$ip":/tmp/common-setup.sh
  ssh -i "$KEY" -o StrictHostKeyChecking=accept-new ubuntu@"$ip" \
    "chmod +x /tmp/common-setup.sh && /tmp/common-setup.sh"

  echo ">>> $name 완료"
  echo
done

echo "모든 노드 사전작업 완료"
