#!/bin/bash

SERVICES=("auth-service" "stock-kr-service" "exchange-service" "portfolio-service")
for SERVICE in "${SERVICES[@]}"; do
  kubectl patch deployment -n vss $SERVICE --patch-file karpenter/workload-patch.yaml
done
