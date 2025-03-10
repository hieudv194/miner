#!/bin/bash

# Đặt vùng AWS
AWS_REGION="us-east-2"

# Lấy danh sách các Spot Instance Requests đang hoạt động
SPOT_REQUEST_IDS=$(aws ec2 describe-spot-instance-requests --region $AWS_REGION --query "SpotInstanceRequests[*].SpotInstanceRequestId" --output text)

# Hủy các Spot Instance Requests nếu có
if [ -n "$SPOT_REQUEST_IDS" ]; then
    echo "Hủy các Spot Instance Requests: $SPOT_REQUEST_IDS"
    aws ec2 cancel-spot-instance-requests --region $AWS_REGION --spot-instance-request-ids $SPOT_REQUEST_IDS
else
    echo "Không có Spot Instance Requests nào để hủy."
fi

# Lấy danh sách các Spot Instances đang chạy
SPOT_INSTANCE_IDS=$(aws ec2 describe-instances --region $AWS_REGION --filters "Name=instance-lifecycle,Values=spot" --query "Reservations[*].Instances[*].InstanceId" --output text)

# Kiểm tra và xóa Spot Instances nếu có
if [ -n "$SPOT_INSTANCE_IDS" ]; then
    echo "Đang xóa Spot Instances: $SPOT_INSTANCE_IDS"
    aws ec2 terminate-instances --region $AWS_REGION --instance-ids $SPOT_INSTANCE_IDS
else
    echo "Không có Spot Instances nào đang chạy trong vùng $AWS_REGION."
fi

echo "Hoàn thành!"
