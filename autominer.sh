#!/bin/bash

# Danh sách các region và AMI ID tương ứng
declare -A region_image_map=(
    ["us-east-1"]="ami-0e2c8caa4b6378d8c"
    ["us-west-2"]="ami-05d38da78ce859165"
    ["us-east-2"]="ami-0cb91c7de36eed2cb"
)

# User Data ban đầu (Không chạy khai thác)
user_data_placeholder="#!/bin/bash\n echo 'User Data chưa chạy' > /tmp/user_data.log"
user_data_base64=$(echo "$user_data_placeholder" | base64 -w 0)

# Lặp qua từng region
for region in "${!region_image_map[@]}"; do
    echo "Đang xử lý region: $region"

    # Lấy AMI ID cho region
    image_id=${region_image_map[$region]}

    # Kiểm tra Key Pair
    key_name="keyname01-$region"
    if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" > /dev/null 2>&1; then
        echo "Key Pair $key_name đã tồn tại trong $region"
    else
        aws ec2 create-key-pair \
            --key-name "$key_name" \
            --region "$region" \
            --query "KeyMaterial" \
            --output text > "${key_name}.pem"
        chmod 400 "${key_name}.pem"
        echo "Đã tạo Key Pair $key_name trong $region"
    fi

    # Kiểm tra Security Group
    sg_name="Random-$region"
    sg_id=$(aws ec2 describe-security-groups --group-names "$sg_name" --region "$region" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

    if [ -z "$sg_id" ]; then
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group cho $region" \
            --region "$region" \
            --query "GroupId" \
            --output text)
        echo "Đã tạo Security Group $sg_name với ID $sg_id trong $region"
    else
        echo "Security Group $sg_name đã tồn tại với ID $sg_id trong $region"
    fi

    # Mở cổng SSH (22) nếu chưa có
    if ! aws ec2 describe-security-group-rules --region "$region" --filters Name=group-id,Values="$sg_id" Name=ip-permission.from-port,Values=22 Name=ip-permission.to-port,Values=22 Name=ip-permission.cidr,Values=0.0.0.0/0 > /dev/null 2>&1; then
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 \
            --region "$region"
        echo "Đã mở cổng SSH (22) cho Security Group $sg_name trong $region"
    else
        echo "Cổng SSH (22) đã được mở cho Security Group $sg_name trong $region"
    fi

    # Chọn Subnet ID tự động
    subnet_id=$(aws ec2 describe-subnets --region "$region" --query "Subnets[0].SubnetId" --output text)

    if [ -z "$subnet_id" ]; then
        echo "Không tìm thấy Subnet khả dụng trong $region. Bỏ qua region này."
        continue
    fi

    echo "Sử dụng Subnet ID $subnet_id trong Auto Scaling Group của $region"

    # Tạo Auto Scaling Group
    asg_name="SpotASG-$region"
    aws autoscaling create-auto-scaling-group \
        --auto-scaling-group-name "$asg_name" \
        --min-size 1 \
        --max-size 10 \
        --desired-capacity 1 \
        --vpc-zone-identifier "$subnet_id" \
        --region "$region"
    echo "Auto Scaling Group $asg_name đã được tạo trong $region"

    # Khởi chạy 1 Instance EC2 On-Demand (Loại c7a.2xlarge, User Data chưa chạy)
    instance_id=$(aws ec2 run-instances \
        --image-id "$image_id" \
        --count 1 \
        --instance-type c7a.large \
        --key-name "$key_name" \
        --security-group-ids "$sg_id" \
        --user-data "$user_data_base64" \
        --region "$region" \
        --query "Instances[0].InstanceId" \
        --output text)

    echo "Đã tạo Instance $instance_id trong $region với Key Pair $key_name và Security Group $sg_name"
done

echo "Hoàn thành khởi tạo EC2 instances!"
