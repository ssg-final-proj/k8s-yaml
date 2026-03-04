# Stockstalk – k8s-yaml

Stockstalk 프로젝트의 Kubernetes 매니페스트를 모아둔 저장소입니다.  
EKS 환경 기준으로 네임스페이스, 환경변수(ConfigMap/ExternalSecret), Redis/Kafka, 각 서비스 배포, Ingress, NetworkPolicy, HPA를 관리합니다.

## 개요

이 저장소는 Stockstalk 서비스 배포에 필요한 Kubernetes 리소스를 정리한 레포입니다.  
애플리케이션 서비스는 `vss` 네임스페이스에, Redis/Kafka 같은 공용 인프라 리소스는 `infra` 네임스페이스에 분리해 운영합니다.

## 디렉터리 구조

```text
k8s-yaml/
├── apply.sh
├── delete.sh
├── namespace.yaml
├── ingress.yaml
├── networkpolicy.yaml
├── all-services-hpa.yaml
├── env/
│   ├── configmap.yaml
│   ├── cluster-secret-store.yaml
│   └── external-secret.yaml
├── redis/
│   ├── storageclass.yaml
│   ├── statefulset.yaml
│   └── service-redis.yaml
├── kafka/
│   ├── kafka-ebs-sc.yaml
│   ├── kafka-cluster.yaml
│   └── kafka-topic.yaml
├── auth/
│   ├── deployment-auth.yaml
│   └── service-auth.yaml
├── stock_kr/
│   ├── stock-key-secret.yaml
│   ├── stock-service.yaml
│   └── token-cronjob.yaml
├── portfolio/
│   └── portfolio-service.yaml
└── exchange/
    └── exchange-service.yaml
```

## 네임스페이스

- `vss` : 애플리케이션 서비스
- `infra` : Redis, Kafka 등 인프라 컴포넌트

```bash
kubectl create namespace vss
kubectl create namespace infra
```

## 서비스 포트

| Service | Container Port |
|---|---:|
| auth-service | 8001 |
| stock-kr-service | 8002 |
| portfolio-service | 8003 |
| exchange-service | 8004 |

## 배포 전 준비

- `kubectl`
- `helm`
- `eksctl`
- EKS kubeconfig 설정 완료
- External Secrets Operator 설치 가능 환경
- AWS Secrets Manager / IRSA 사용 가능 환경

## 배포 흐름

배포는 `apply.sh` 기준으로 다음 순서로 진행합니다.

1. namespace 생성
2. Secrets Manager 접근용 IRSA(`secrets-sa`) 생성
3. ConfigMap / ClusterSecretStore / ExternalSecret 적용
4. Redis 배포
5. Strimzi Kafka Operator 설치
6. Kafka / KafkaTopic 배포
7. Kafka Ready 대기
8. Auth / Stock / Portfolio / Exchange 서비스 배포
9. Ingress 적용
10. NetworkPolicy / HPA 적용

## 배포

```bash
chmod +x apply.sh
./apply.sh
```

## 삭제

```bash
chmod +x delete.sh
./delete.sh
```

## 환경 설정

### ConfigMap

`env/configmap.yaml`에서 공통 환경변수를 관리합니다.

주요 항목 예시

- `MYSQL_HOST`
- `MYSQL_PORT`
- `AUTH_SCHEMA`
- `PORTFOLIO_SCHEMA`
- `EXCHANGE_SCHEMA`
- `REDIS_HOST`
- `REDIS_PORT`
- `KAFKA_BROKER_HOST`
- `BASE_URL`

### External Secret

AWS Secrets Manager에서 DB 계정 정보를 가져와 `app-secret`으로 주입합니다.

- `MYSQL_USER`
- `MYSQL_PASSWORD`

### IRSA

Secrets Manager 접근을 위해 `secrets-sa` 서비스어카운트를 사용합니다.

```bash
eksctl create iamserviceaccount \
  --name secrets-sa \
  --namespace vss \
  --cluster tf-eks-cluster \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/SecretsManagerIRSAReadPolicy \
  --approve
```

## 주요 구성

### 1. Auth Service

- Deployment + Service 구성
- ConfigMap / Secret 기반 환경변수 주입
- `livenessProbe`: `/healthz`
- `readinessProbe`: `/readiness`
- `serviceAccountName: secrets-sa`

### 2. Stock KR Service

- Deployment + Service 구성
- 한국투자증권 키 파일을 Secret으로 마운트
- 필요 시 토큰 갱신용 CronJob 사용

### 3. Portfolio / Exchange Service

- 각각 Deployment + Service 구성
- 공통 ConfigMap / Secret 사용

### 4. Redis

- `infra` 네임스페이스에 배포
- StorageClass + StatefulSet + ClusterIP Service 구성
- EBS 기반 PVC 사용

### 5. Kafka

- Strimzi Operator 기반 배포
- KRaft 모드 사용
- KafkaNodePool + Kafka + KafkaTopic 구성
- `orders-topic` 사용

## Ingress

ALB Ingress를 사용하며, 도메인 기준으로 아래와 같이 라우팅합니다.

- `/auth` → `auth-service:8001`
- `/` → `stock-kr-service:8002`
- `/portfolio` → `portfolio-service:8003`
- `/exchange` → `exchange-service:8004`

`ingress.yaml`에서 환경별로 수정이 필요한 값

- `alb.ingress.kubernetes.io/certificate-arn`
- `external-dns.alpha.kubernetes.io/hostname`
- `spec.rules.host`

## 실행 확인

```bash
kubectl get all -n vss
kubectl get all -n infra
kubectl get ingress -n vss
```

## 트러블슈팅 메모

### IRSA 재생성 문제

네임스페이스를 삭제해도 CloudFormation 스택이 남아 있으면 `eksctl`이 기존 리소스를 제외(excluded) 처리할 수 있습니다.

이 경우 기존 IRSA 또는 CloudFormation 스택을 정리한 뒤 다시 생성해야 합니다.

### Kafka Ready 지연

Kafka Pod가 Ready 상태가 되기까지 시간이 꽤 걸릴 수 있습니다.

`apply.sh` 스크립트는 `kafka-k-nodes` Pod 3개가 모두 Ready 상태가 될 때까지 대기하도록 구성되어 있습니다.

## 참고

- DB 스키마 생성은 RDS에서 별도로 수행합니다.
- MySQL 컨테이너는 개발 테스트용이며 실제 환경에서는 RDS를 사용합니다.
- 운영 환경에서는 ConfigMap에 포함된 민감 정보는 Secret 또는 AWS Secrets Manager로 분리하는 것을 권장합니다.
