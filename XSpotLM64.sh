#!/bin/bash

# Danh sách các khu vực (regions) cần tăng hạn mức
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

# Cấu hình chung
NEW_QUOTA_VALUE=64   # Giá trị hạn mức mới bạn muốn
SERVICE_CODE="ec2"   # Mã dịch vụ EC2
QUOTA_CODES=("L-34B43A08" "L-1216C47A")  # Mã hạn mức cho Instances (vCPU)

# Lặp qua từng khu vực
for REGION in "${REGIONS[@]}"; do
    echo "🔍 Đang xử lý khu vực: $REGION"

    # Lặp qua từng hạn mức
    for QUOTA_CODE in "${QUOTA_CODES[@]}"; do
        echo "🟢 Gửi yêu cầu tăng hạn mức $QUOTA_CODE lên $NEW_QUOTA_VALUE vCPU tại $REGION..."

        # Gửi yêu cầu tăng hạn mức
        aws service-quotas request-service-quota-increase \
            --service-code $SERVICE_CODE \
            --quota-code $QUOTA_CODE \
            --desired-value $NEW_QUOTA_VALUE \
            --region $REGION

        # Kiểm tra trạng thái yêu cầu
        if [ $? -eq 0 ]; then
            echo "✅ Yêu cầu tăng hạn mức $QUOTA_CODE thành công tại $REGION."
        else
            echo "❌ Lỗi khi gửi yêu cầu tăng hạn mức $QUOTA_CODE tại $REGION. Kiểm tra lại IAM hoặc quota hiện tại."
        fi
        echo "----------------------------------------"
    done
done

echo "🚀 Hoàn tất gửi yêu cầu tăng hạn mức!"
