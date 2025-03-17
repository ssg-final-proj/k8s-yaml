#!/bin/bash

echo "Making namespace..."
 kubectl apply -f namespace.yaml

echo "Creating IRSA for Secrets Manager access..."
 eksctl create iamserviceaccount \
     --name secrets-sa \
     --namespace vss \
     --cluster tf-eks-cluster \
     --attach-policy-arn arn:aws:iam::707677861059:policy/SecretsManagerIRSAReadPolicy \
     --approve

echo "Applying environment configs..."
kubectl apply -f env/configmap.yaml
kubectl apply -f env/cluster-secret-store.yaml
kubectl apply -f env/external-secret.yaml

echo "Deploying Redis..."
kubectl apply -f redis/storageclass.yaml
kubectl apply -f redis/service-account.yaml
kubectl apply -f redis/redis-config.yaml
kubectl apply -f redis/redis-backup-script.yaml

kubectl apply -f redis/statefulset.yaml
kubectl apply -f redis/service-redis.yaml

echo "Installing Strimzi Kafka Operator..."
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator --namespace infra --create-namespace

echo "Deploying Kafka..."
kubectl apply -f kafka/kafka-ebs-sc.yaml
kubectl apply -f kafka/kafka-cluster.yaml
kubectl apply -f kafka/kafka-topic.yaml

# Kafka가 올라오는 데 시간이 걸릴 수 있으므로 대기
echo "Waiting for Kafka to be ready..."
until [ $(kubectl get pods -n infra | grep "kafka-k-nodes" | grep "1/1" | wc -l) -eq 3 ]; do 
  echo "Kafka pods ready: $(kubectl get pods -n infra | grep "kafka-k-nodes" | grep "1/1" | wc -l)/3"
  sleep 3
done
echo "All Kafka pods are ready!"

echo "Deploying Auth service..."
kubectl apply -f auth/deployment-auth.yaml
kubectl apply -f auth/service-auth.yaml

echo "Deploying Stock service..."
kubectl apply -f stock_kr/stock-key-secret.yaml
kubectl apply -f stock_kr/stock-service.yaml
# kubectl apply -f stock_kr/token-cronjob.yaml

echo "Deploying Portfolio service..."
kubectl apply -f portfolio/portfolio-service.yaml

echo "Deploying Exchange service..."
kubectl apply -f exchange/exchange-service.yaml

echo "Applying Ingress..."
kubectl apply -f ingress.yaml

# 모든 서비스가 정상적으로 올라온 후 마지막 단계에서 NetworkPolicy를 적용
echo "Applying Network Policies..."
kubectl apply -f networkpolicy.yaml

kubectl apply -f all-services-hpa.yaml

echo "Deployment completed!"
