#!/bin/bash

# Danh sách vùng AWS cần thay đổi instance
REGIONS=("us-east-1" "us-west-2" "us-east-2")

# Hàm cập nhật instance type mới
get_new_instance_type() {
    case "$1" in
        "c7a.large") echo "c7a.2xlarge" ;;
        *) echo "c7a.2xlarge" ;; # Mặc định nếu không xác định được
    esac
}

# Lặp qua từng vùng để dừng và thay đổi instance type
for REGION in "${REGIONS[@]}"; do
    echo "🔹 Đang xử lý vùng: $REGION"

    # Lấy danh sách Instance ID trong vùng
    INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" \
        --query "Reservations[*].Instances[*].InstanceId" --output text)

    if [ -z "$INSTANCE_IDS" ]; then
        echo "⚠️ Không có instance nào trong vùng $REGION."
        continue
    fi

    echo "🛑 Dừng tất cả instances trong vùng $REGION..."
    echo "$INSTANCE_IDS" | xargs aws ec2 stop-instances --region "$REGION" --instance-ids --no-cli-pager
    aws ec2 wait instance-stopped --region "$REGION" --instance-ids $INSTANCE_IDS

    # Thay đổi instance type
    for INSTANCE in $INSTANCE_IDS; do
        CURRENT_TYPE=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --region "$REGION" \
            --query "Reservations[*].Instances[*].InstanceType" --output text)
        NEW_TYPE=$(get_new_instance_type "$CURRENT_TYPE")

        if [ "$CURRENT_TYPE" == "$NEW_TYPE" ]; then
            echo "✅ Instance $INSTANCE đã có type $NEW_TYPE, bỏ qua thay đổi."
            continue
        fi

        echo "🔄 Đổi instance $INSTANCE từ $CURRENT_TYPE ➝ $NEW_TYPE"
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE" \
            --instance-type "{\"Value\": \"$NEW_TYPE\"}" --region "$REGION" --no-cli-pager
            
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" \
        --attribute userData \
        --user-data "Value=$user_data_base64" \
        --region "$REGION"

aws ec2 reboot-instances --instance-ids "$INSTANCE_ID" --region "$REGION"

    done

    echo "🚀 Khởi động lại tất cả instances trong vùng $REGION..."
    echo "$INSTANCE_IDS" | xargs aws ec2 start-instances --region "$REGION" --instance-ids --no-cli-pager
done

echo "✅ Hoàn tất thay đổi instance type cho tất cả vùng!"
