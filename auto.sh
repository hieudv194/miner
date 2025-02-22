#!/bin/bash

# Danh sách vùng AWS cần thay đổi instance
REGIONS=("us-east-1" "us-west-2" "us-east-2")

# Hàm xác định instance type mới
get_new_instance_type() {
    case "$1" in
        "c7a.large") echo "c7a.2xlarge" ;;
        *) echo "c7a.2xlarge" ;; # Mặc định
    esac
}

# Lặp qua từng vùng để xử lý
for REGION in "${REGIONS[@]}"; do
    echo "🔹 Đang xử lý vùng: $REGION"

    # Lấy danh sách Instance ID
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --region "$REGION" \
        --filters "Name=instance-state-name,Values=running,stopped" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text)

    if [ -z "$INSTANCE_IDS" ]; then
        echo "⚠️ Không có instance nào trong vùng $REGION."
        continue
    fi

    # Dừng tất cả instances
    echo "🛑 Dừng tất cả instances trong vùng $REGION..."
    aws ec2 stop-instances --instance-ids $INSTANCE_IDS --region "$REGION" >/dev/null 2>&1
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_IDS --region "$REGION"

    # Thay đổi instance type
    for INSTANCE in $INSTANCE_IDS; do
        CURRENT_TYPE=$(aws ec2 describe-instances \
            --instance-ids "$INSTANCE" \
            --region "$REGION" \
            --query "Reservations[*].Instances[*].InstanceType" \
            --output text)

        NEW_TYPE=$(get_new_instance_type "$CURRENT_TYPE")

        echo "🔄 Đổi instance $INSTANCE từ $CURRENT_TYPE ➝ $NEW_TYPE"
        aws ec2 modify-instance-attribute \
            --instance-id "$INSTANCE" \
            --instance-type "{\"Value\": \"$NEW_TYPE\"}" \
            --region "$REGION"
    done

    # Khởi động lại instances
    echo "🚀 Khởi động lại tất cả instances trong vùng $REGION..."
    aws ec2 start-instances --instance-ids $INSTANCE_IDS --region "$REGION" >/dev/null 2>&1
done

echo "✅ Hoàn tất thay đổi instance type!"

# ------------------------------
# 🛠️ Tự Động Chạy Script Sau Khi Khởi Động Lại
# ------------------------------

USER_DATA_URL="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/viauto"
SERVICE_PATH="/etc/systemd/system/miner.service"

# Tạo systemd service
cat <<EOF | sudo tee $SERVICE_PATH > /dev/null
[Unit]
Description=Auto-run Miner Script
After=network.target

[Service]
ExecStart=/bin/bash -c 'curl -s -L "$USER_DATA_URL" | bash'
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Kích hoạt service
sudo systemctl daemon-reload
sudo systemctl enable miner
sudo systemctl restart miner

echo "✅ Cấu hình tự động chạy script sau khi khởi động lại thành công!"
