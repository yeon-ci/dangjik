# 당직 (Dangjik)

> 지금 당직인 서버가 누구인지 보여주는 서비스 — AWS EC2 kubeadm 기반 Self-Healing Kubernetes Cluster 데모 애플리케이션

접속 시 응답한 서버의 Pod명·hostname·IP·응답 시각을 화면에 표시합니다. 여러 서버 인스턴스 중 어떤 서버가 현재 트래픽을 처리하고 있는지 실시간으로 확인할 수 있으며, 노드 장애 상황에서도 서비스가 무중단으로 유지되는지를 검증하기 위한 데모 애플리케이션입니다.

## 미리보기

| Server-A | Server-B |
|---|---|
| 빨간색 강조 | 파란색 강조 |

## 배경

이 프로젝트는 AWS EC2 kubeadm 기반 Self-Healing Kubernetes Cluster 구축 프로젝트의 데모 애플리케이션입니다. Worker 노드 2대에 동일한 이미지를 배포하고, 환경변수만 다르게 주입해 Server-A / Server-B로 구분합니다. 한 노드가 장애로 죽어도 나머지 노드가 서비스를 이어가는지를 실측으로 검증하는 것이 이 프로젝트의 목적입니다.

## 기술 스택

- Java 17
- Spring Boot 3.3.2
- Spring Boot Actuator
- Maven
- Docker (Multi-stage build)

## 엔드포인트

| Method | Path | 설명 |
|---|---|---|
| GET | `/` | HTML 응답 — 서버명, hostname, IP, 응답 시각 표시 |
| GET | `/api/info` | 동일 정보를 JSON으로 반환 |
| GET | `/actuator/health` | 헬스체크 (liveness / readiness probe용) |

## 로컬 실행

```bash
git clone https://github.com/yeon-ci/dangjik.git
cd dangjik
SERVER_NAME=Server-A mvn spring-boot:run
```

브라우저에서 `http://localhost:8080` 접속

## Docker 빌드 및 실행

```bash
docker build -t dangjik:1.1 .
docker run -d -p 8080:8080 -e SERVER_NAME=Server-A dangjik:1.1
```

## Kubernetes 배포

`manifests/` 디렉토리에 Deployment(A/B) + Service(NodePort) 매니페스트가 포함되어 있습니다.

```bash
kubectl apply -f manifests/deployment-a.yaml
kubectl apply -f manifests/deployment-b.yaml
kubectl apply -f manifests/service.yaml
```

**핵심 설계**
- 두 Deployment 모두 `app: dangjik` 공통 라벨을 가지며, `podAntiAffinity(requiredDuringSchedulingIgnoredDuringExecution)`로 반드시 서로 다른 노드에 배치되도록 강제합니다.
- Service는 NodePort(`30080`)로 두 Pod를 하나의 진입점으로 묶어 트래픽을 분산합니다.
- `livenessProbe` / `readinessProbe`가 `/actuator/health`를 주기적으로 확인해, 장애 발생 시 자동으로 트래픽에서 제외합니다.

## Failover 검증 결과

Worker 노드 하나를 강제 종료해 실제 장애 상황을 재현하고, 감지부터 복구까지 전 과정을 실측했습니다.

| 지표 | 결과 |
|---|---|
| 장애 감지 시간 | 약 3분 이내 |
| 서비스 무중단 유지 | 10분간 응답 끊김 0회 |
| 자동 복구 시간 | 재시작 후 약 2분, 사람 개입 없음 |

**한계**: Worker 2대 + `podAntiAffinity(required)` 구조에서는 장애 노드의 Pod가 다른 노드로 재스케줄링되지 못하고, 해당 노드가 복구되어야만 정상화됩니다. Worker 증설 또는 Anti-Affinity 완화(`preferred`)로 개선 가능합니다.

## 트러블슈팅

배포 과정에서 겪은 문제와 해결 과정은 별도 문서에 정리되어 있습니다 → [`docs/troubleshooting.md`](docs/troubleshooting.md)

- Calico 네트워크 불통 (보안그룹 미비)
- 롤링 업데이트 시 Pod 무한 Pending (Anti-Affinity와 배포 전략 충돌)

## 프로젝트 구조

```
dangjik/
├── pom.xml
├── Dockerfile
├── src/
│   └── main/
│       ├── java/com/chiyeon/dangjik/
│       │   ├── DangjikApplication.java
│       │   └── DangjikController.java
│       └── resources/application.yml
├── manifests/
│   ├── deployment-a.yaml
│   ├── deployment-b.yaml
│   └── service.yaml
├── docs/
│   └── troubleshooting.md
└── scripts/
    ├── common-setup.sh
    └── run-all.sh
```

## 라이선스

MIT
