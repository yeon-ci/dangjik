# 트러블슈팅 기록

구축 과정에서 실제로 겪은 문제와 해결 과정을 기록합니다.

---

## 1. Calico 네트워크 불통 — Pod 간 통신 실패

### 증상
`kubectl get pods` 상으로는 Server-A, Server-B 모두 `1/1 Running`으로 정상 기동되었으나, 브라우저와 curl 양쪽 모두 NodePort(30080) 접속 시 응답 없이 타임아웃(`ERR_CONNECTION_TIMED_OUT`)이 발생했다.

### 진단 (범위를 좁혀가는 단계적 접근)

1. **애플리케이션 레이어 배제**: `kubectl logs deployment/dangjik-a`, `dangjik-b`로 Spring Boot 기동 로그 확인 → Tomcat 정상 기동, 에러 없음. 애플리케이션 자체는 정상.
2. **Service 레이어 확인**: `curl localhost:30080` (Control Plane에서) → 타임아웃. 외부 접근 문제가 아니라 클러스터 내부 문제로 범위를 좁힘.
3. **Pod 직접 확인**: `kubectl get pods -o wide`로 확인한 Pod IP에 직접 curl 시도(Service를 건너뛰고) → 역시 타임아웃. kube-proxy/Service 계층이 아니라 그보다 아래(Pod 네트워크 자체)의 문제로 좁힘.
4. **OS 방화벽 배제**: `sudo ufw status` → `inactive`. 노드 자체의 방화벽 문제는 배제.
5. **CNI 상태 확인**: `kubectl get pods -n kube-system -o wide` → `calico-node` 3개가 모두 `READY` 컬럼에서 `0/1`로 표시됨 (STATUS는 Running이지만 컨테이너 내부 readiness probe를 통과하지 못한 상태).

`Running`인데 `READY`가 `0/1`이라는 상태가 핵심 단서였다. 컨테이너 프로세스는 떠 있지만, Calico(felix)가 자기 자신의 상태 점검(BGP 피어링 등)을 통과하지 못하고 있다는 뜻이었다.

### 원인

Calico 공식 문서(Tigera Network requirements) 기준으로 노드 간 오버레이 네트워크 통신에 아래 3가지가 필수다.

| 용도 | 프로토콜/포트 | 비고 |
|---|---|---|
| BGP 피어링 (노드 간 라우팅 정보 교환) | TCP 179 | 전 노드 양방향 필수 |
| IP-in-IP 캡슐화 (기본 encapsulation) | IP 프로토콜 번호 4 | TCP/UDP가 아닌 별도 프로토콜이라 포트 지정 방식으로 열 수 없음 |
| VXLAN 캡슐화 (대체 encapsulation) | UDP 4789 | IP-in-IP 대신 VXLAN 모드 사용 시 |

당시 보안그룹에는 SSH(22, 내 IP 한정)와 NodePort 범위(30000-32767) 관련 규칙만 있었고, 위 3가지 중 어느 것도 열려 있지 않았다.

### 해결

노드 3대가 속한 보안그룹(`k8s-sg`)에 "모든 트래픽 허용, 소스: 자기 자신(`k8s-sg`)" 규칙을 추가했다. 프로토콜/포트를 하나씩 나열할 필요 없이 BGP·IP-in-IP·VXLAN을 포함한 Calico의 모든 노드 간 통신이 한 번에 허용된다. 적용 후 1분 이내에 `calico-node` 3개 모두 `1/1 Ready`로 전환되었고, Pod IP·NodePort 양쪽 모두 정상 응답을 확인했다.

### 실무 관점에서의 타당성

"모든 트래픽 허용"이라는 규칙은 직관적으로 위험해 보일 수 있어 실무 근거를 확인했다. AWS 공식 문서(Amazon EKS security group requirements)에 따르면, EKS가 자동 생성하는 클러스터 보안그룹도 정확히 "소스를 자기 자신으로 하는 전체 트래픽 허용" 규칙을 기본값으로 가진다. 이는 kubelet·CNI 등 쿠버네티스 구성 요소가 사용하는 포트가 버전·플러그인에 따라 유동적이기 때문에, 매니지드 서비스조차 포트를 일일이 나열하지 않고 이 방식을 택하는 것이다.

다만 이 규칙이 안전한 이유는 전체 허용 자체가 아니라, 범위가 `0.0.0.0/0`이 아닌 "같은 보안그룹에 속한 노드 3대"로 한정(self-reference)되어 있기 때문이다. 프로덕션 환경에서 더 강화하려면:

- 포트를 `TCP 179` / `IP 프로토콜 4` / `UDP 4789`로 정확히 나열해 필요한 것만 개방
- 보안그룹 멤버십 자체를 최소화해 "전체 허용"의 영향 범위(blast radius)를 제한
- Calico의 GlobalNetworkPolicy/NetworkPolicy(Pod 단위)를 추가 적용해 이중 방어체계 구성

---

## 2. 롤링 업데이트 시 Pod가 영원히 Pending

### 증상

Docker 이미지를 `1.0` → `1.1`로 올리기 위해 매니페스트를 재적용했을 때, 새 Pod(`dangjik-a-xxxx`, `dangjik-b-xxxx`)가 계속 `Pending` 상태로 남아 스케줄링되지 않았다.

```
NAME                         READY   STATUS    NODE
dangjik-a-64fbbf6ff6-9jqfj   1/1     Running   ip-172-31-13-131
dangjik-a-8684bd6c9f-c64wn   0/1     Pending   <none>
dangjik-b-6dc477c8db-mbdxh   1/1     Running   ip-172-31-13-153
dangjik-b-748bdf8d7c-cdq89   0/1     Pending   <none>
```

### 원인

기본 배포 전략(`RollingUpdate`)은 새 Pod를 먼저 띄우고, 준비되면 기존 Pod를 지우는 방식이다. 그런데 `podAntiAffinity(requiredDuringSchedulingIgnoredDuringExecution)` 규칙 때문에 "app=dangjik Pod가 이미 있는 노드에는 못 뜬다"는 제약이 걸려 있었다. Worker가 정확히 2대이고 이미 둘 다 기존 Pod(A, B)로 꽉 차 있어서, 새 Pod가 갈 자리가 없어 영원히 `Pending` 상태에 머무는 교착 상태가 발생했다.

### 해결

Deployment의 `strategy.type`을 `Recreate`로 변경해, 기존 Pod를 먼저 종료해 자리를 비운 뒤 새 Pod를 배치하도록 수정했다.

```yaml
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      server: server-a
```

| 항목 | RollingUpdate (기본값) | Recreate (변경 후) |
|---|---|---|
| 배포 순서 | 새 Pod 먼저 생성 → 기존 Pod 종료 | 기존 Pod 먼저 종료 → 새 Pod 생성 |
| Worker 2대 + Anti-Affinity 환경 | 새 Pod가 스케줄링될 빈 노드 없음 → 무한 Pending | 기존 Pod 종료로 자리 확보 → 정상 스케줄링 |
| 무중단 여부 | 이론상 무중단 (단, 본 환경에선 불가) | 짧은 다운타임 발생 (교체 순간) |
| 적합한 상황 | 노드 수 > Pod 수, 여유 자원 있는 환경 | 노드 수 = Pod 수처럼 여유가 없는 환경 |

### 교훈

노드 수와 Pod 수가 정확히 일치하는 환경에서는 Anti-Affinity 규칙과 배포 전략을 함께 설계해야 한다. 무중단 배포가 항상 정답이 아니라, 클러스터의 실제 제약 조건(노드 수, 스케줄링 규칙)과 정합한 전략을 선택하는 것이 우선한다는 것을 확인했다.

---

## 3. Windows 환경 SSH 키 권한 문제

### 증상

Windows에서 `scp`/`ssh` 실행 시 아래와 같은 경고와 함께 접속이 거부되었다.

```
Bad permissions. Try removing permissions for user: BUILTIN\Users
WARNING: UNPROTECTED PRIVATE KEY FILE!
Permission denied (publickey).
```

### 원인

Windows 파일 시스템의 기본 권한 모델이 리눅스의 600/400 권한 체계와 달라, 일반 사용자 그룹(`BUILTIN\Users`)에게도 읽기 권한이 남아 있었다.

### 해결

`icacls` 명령으로 상속 권한을 제거하고 본인 계정에게만 읽기 권한을 부여했다.

```cmd
icacls keys\dangjik-key.pem /inheritance:r
icacls keys\dangjik-key.pem /grant:r "%username%":R
```
