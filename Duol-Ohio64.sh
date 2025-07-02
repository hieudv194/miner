#!/bin/bash

# Danh sách các region và AMI ID tương ứng
declare -A region_image_map=(
    ["us-east-1"]="ami-0e2c8caa4b6378d8c"
    ["us-west-2"]="ami-05d38da78ce859165"
    ["us-east-2"]="ami-0cb91c7de36eed2cb"
)

# URL chứa User Data trên GitHub
user_data_url="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/vixmrLM-64"
user_data_file="/tmp/user_data.sh"

echo "Downloading user-data from GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

if [ ! -s "$user_data_file" ]; then
    echo "Error: Failed to download user-data from GitHub."
    exit 1
fi

# Mã hóa User Data thành base64
user_data_base64=$(base64 -w 0 "$user_data_file")

for region in "${!region_image_map[@]}"; do
    echo "Processing region: $region"
    image_id=${region_image_map[$region]}
    key_name="KeyPairOhioh-$region"
    sg_name="Random-$region"
    
    # Kiểm tra hoặc tạo Key Pair
    if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" > /dev/null 2>&1; then
        echo "Key Pair $key_name đã tồn tại trong $region"
    else
        aws ec2 create-key-pair --key-name "$key_name" --region "$region" --query "KeyMaterial" --output text > "${key_name}.pem"
        chmod 400 "${key_name}.pem"
        echo "Đã tạo Key Pair $key_name trong $region"
    fi

    # Kiểm tra hoặc tạo Security Group
    sg_id=$(aws ec2 describe-security-groups --group-names "$sg_name" --region "$region" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
    if [ -z "$sg_id" ]; then
        sg_id=$(aws ec2 create-security-group --group-name "$sg_name" --description "Security group cho $region" --region "$region" --query "GroupId" --output text)
        echo "Đã tạo Security Group $sg_name với ID $sg_id trong $region"
    else
        echo "Security Group $sg_name đã tồn tại với ID $sg_id trong $region"
    fi

    # Mở cổng SSH nếu chưa có
    if ! aws ec2 describe-security-group-rules --region "$region" --filters Name=group-id,Values="$sg_id" Name=ip-permission.from-port,Values=22 Name=ip-permission.to-port,Values=22 Name=ip-permission.cidr,Values=0.0.0.0/0 > /dev/null 2>&1; then
        aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$region"
        echo "Đã mở cổng SSH (22) cho Security Group $sg_name trong $region"
    fi

    # Lấy Subnet ID
    subnet_id=$(aws ec2 describe-subnets --region "$region" --query "Subnets[0].SubnetId" --output text)
    if [ -z "$subnet_id" ]; then
        echo "Không tìm thấy Subnet khả dụng trong $region. Bỏ qua region này."
        continue
    fi
    
     # Gửi yêu cầu Spot persistent (tự khởi động lại khi bị reclaim)
    spot_instance_id=$(aws ec2 request-spot-instances \
        --instance-count 1 \
        --type "persistent" \
        --instance-interruption-behavior "stop" \
        --launch-specification "{
            \"ImageId\": \"$image_id\",
            \"InstanceType\": \"c7a.16xlarge\",
            \"KeyName\": \"$key_name\",
            \"SecurityGroupIds\": [\"$sg_id\"],
            \"SubnetId\": \"$subnet_id\",
            \"UserData\": \"$user_data_base64\"
        }" \
        --region "$region" \
        --query "SpotInstanceRequests[0].SpotInstanceRequestId" \
        --output text)

    echo "Đã gửi yêu cầu Spot Persistent Instance: $spot_instance_id trong $region"

    # Chờ instance được cấp
    echo "Đang chờ Spot Instance $spot_instance_id được cấp..."
    aws ec2 wait spot-instance-request-fulfilled \
        --spot-instance-request-ids "$spot_instance_id" \
        --region "$region"

    echo "✔ Spot Instance $spot_instance_id ở $region đã được cấp thành công!"
done

echo "Hoàn tất khởi tạo Spot EC2 Persistent Instances!"
