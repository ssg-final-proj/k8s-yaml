#!/bin/bash

declare -A BACKUP_INTERVALS=(
  [0]=60     # DB0: 1분
  [1]=300    # DB1: 5분
  [4]=86400  # DB4: 24시간
  [5]=3600   # DB5: 1시간
)

for DB in "${!BACKUP_INTERVALS[@]}"; do
  LAST_BACKUP=$(redis-cli -n $DB GET "last_backup" || echo 0)
  NOW=$(date +%s)
  
  if (( NOW - LAST_BACKUP >= ${BACKUP_INTERVALS[$DB]} )); then
    echo "[$(date)] DB$DB 백업 시작"
    redis-cli -n $DB --rdb /tmp/db${DB}.rdb
    aws s3 cp /tmp/db${DB}.rdb s3://redis-backup-bucket-hi/db${DB}/backup-$(date +\%Y\%m\%d-\%H\%M).rdb &
    redis-cli -n $DB SET "last_backup" $NOW
  fi
done

rm -f /tmp/db*.rdb
