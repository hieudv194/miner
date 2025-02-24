#!/bin/bash

# Danh sách các khu vực (regions) cần tăng hạn mức
REGIONS=("us-east-1" "us-west-2" "us-east-2")

# Cấu hình chung
NEW_QUOTA_VALUE=64   # Giá trị hạn mức mới bạn muốn
SERVICE_CODE="ec2"   # Mã dịch vụ EC2
QUOTA_CODE="L-34B43A08" "L-1216C47A"  # Mã hạn mức cho Instances (vCPU)

# Lặp qua từng khu vực và gửi yêu cầu tăng hạn mức
for REGION in "${REGIONS[@]}"; do
    echo "Đang xử lý khu vực: $REGION"

    # Yêu cầu tăng hạn mức
    aws service-quotas request-service-quota-increase \
        --service-code $SERVICE_CODE \
        --quota-code $QUOTA_CODE \
        --desired-value $NEW_QUOTA_VALUE \
        --region $REGION

    # Kiểm tra trạng thái yêu cầu
    if [ $? -eq 0 ]; then
        echo "Yêu cầu tăng hạn mức CPU cho Instances đã được gửi thành công tại khu vực $REGION."
    else
        echo "Có lỗi xảy ra khi gửi yêu cầu tại khu vực $REGION. Vui lòng kiểm tra lại cấu hình và quyền IAM."
    fi

    echo "----------------------------------------"
done
