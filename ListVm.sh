#!/bin/bash

# Danh sách các vùng cần kiểm tra
REGIONS=("us-east-1" "us-east-2" "us-west-2")

echo "📌 Danh sách các máy đang chạy trong các vùng: ${REGIONS[*]}"

# Lặp qua từng vùng và liệt kê các instance đang chạy
for REGION in "${REGIONS[@]}"; do
    echo "🔹 Vùng: $REGION"
    
    # Lấy danh sách các instances đang chạy
    aws ec2 describe-instances --region $REGION --filters "Name=instance-state-name,Values=running" \
        --query "Reservations[*].Instances[*].[InstanceId, InstanceType, State.Name, InstanceLifecycle, PrivateIpAddress, PublicIpAddress]" \
        --output table
done
