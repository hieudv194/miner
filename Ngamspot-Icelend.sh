#!/bin/bash

# 🌍 Danh sách các vùng và AMI tương ứng
declare -A region_image_map=(
    ["eu-west-1"]="ami-0e9085e60087ce171"
)

# 🚀 Vòng lặp qua từng vùng để thiết lập
for region in "${!region_image_map[@]}"; do
    echo "======================================="
    echo "🌍 Processing region: $region"
    image_id=${region_image_map[$region]}
    
    # 🗝 Kiểm tra hoặc tạo Key Pair
    key_name="KeyPair77-$region"
    if ! aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" > /dev/null 2>&1; then
        aws ec2 create-key-pair \
            --key-name "$key_name" \
            --region "$region" \
            --query "KeyMaterial" \
            --output text > "${key_name}.pem"
        chmod 400 "${key_name}.pem"
        echo "✅ Created Key Pair: $key_name"
    else
        echo "🔹 Key Pair $key_name already exists."
    fi

    # 🔒 Kiểm tra hoặc tạo Security Group
    sg_name="Random-$region"
    sg_id=$(aws ec2 describe-security-groups --group-names "$sg_name" --region "$region" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

    if [ -z "$sg_id" ]; then
        sg_id=$(aws ec2 create-security-group \
            --group-name "$sg_name" \
            --description "Security group for $region" \
            --region "$region" \
            --query "GroupId" --output text)
        echo "✅ Created Security Group: $sg_name ($sg_id)"
    else
        echo "🔹 Security Group $sg_name already exists: $sg_id"
    fi

    # 🔓 Đảm bảo SSH (22) mở cho Security Group
    if ! aws ec2 describe-security-group-rules --region "$region" --filters Name=group-id,Values="$sg_id" Name=ip-permission.from-port,Values=22 > /dev/null 2>&1; then
        aws ec2 authorize-security-group-ingress \
            --group-id "$sg_id" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$region"
        echo "✅ Enabled SSH (22) access for $sg_name"
    fi

    # 📌 Kiểm tra Launch Template trước khi tạo
    launch_template_name="SpotLaunchTemplate-$region"
    aws ec2 describe-launch-templates --launch-template-names "$launch_template_name" --region "$region" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "🚀 Creating Launch Template: $launch_template_name"
        aws ec2 create-launch-template \
            --launch-template-name "$launch_template_name" \
            --version-description "Version1" \
            --launch-template-data "{
                \"ImageId\": \"$image_id\",
                \"InstanceType\": \"c7a.large\",
                \"KeyName\": \"$key_name\",
                \"SecurityGroupIds\": [\"$sg_id\"]
            }" \
            --region "$region"
        echo "✅ Created Launch Template: $launch_template_name"
    else
        echo "🔹 Launch Template $launch_template_name already exists."
    fi

    # 🔍 Lấy Subnet ID cho Auto Scaling Group
    subnet_id=$(aws ec2 describe-subnets --region "$region" --query "Subnets[0].SubnetId" --output text)

    if [ -z "$subnet_id" ]; then
        echo "❌ No available Subnet found in $region. Skipping."
        continue
    fi
    echo "🔹 Using Subnet ID: $subnet_id"

done

# 🚀 Khởi chạy Spot Instances từ Launch Template
for region in "${!region_image_map[@]}"; do
    launch_template_name="SpotLaunchTemplate-$region"
    echo "======================================="
    echo "🚀 Launching Spot Instances in $region using $launch_template_name"

    # Kiểm tra lại Launch Template trước khi chạy instance
    aws ec2 describe-launch-templates --launch-template-names "$launch_template_name" --region "$region" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "❌ Launch Template $launch_template_name not found. Skipping..."
        continue
    fi

    aws ec2 run-instances \
        --launch-template "LaunchTemplateName=$launch_template_name,Version=1" \
        --instance-market-options "MarketType=spot" \
        --count 1 --region "$region"
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully launched Spot Instance in $region"
    else
        echo "❌ Failed to launch Spot Instance in $region" >&2
    fi
done

echo "🎉 Hoàn tất quá trình triển khai!"
