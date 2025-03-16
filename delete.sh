#!/bin/bash

echo "Deleting IAM ServiceAccounts..."
eksctl delete iamserviceaccount \
    --name secrets-sa \
    --namespace vss \
    --cluster tf-eks-cluster

echo "Waiting for IAM ServiceAccount deletion to complete..."
sleep 5  # CloudFormation 스택 삭제 시간이 필요할 수 있으므로 잠시 대기

echo "Deleting namespaces..."
kubectl delete namespace vss
kubectl delete namespace infra

echo "Deleting storage classes..."
kubectl delete storageclass kafka-ebs-sc redis-ebs-sc

echo "Cleanup complete."