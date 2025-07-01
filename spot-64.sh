#!/bin/bash
#
# Launch persistent Spot Instances (stop/restore) và đảm bảo User Data always-run
#

# ====== 1. Map Region → AMI ======
declare -A region_image_map=(
    ["us-east-1"]="ami-0e2c8caa4b6378d8c"
    ["us-west-2"]="ami-05d38da78ce859165"
    ["us-east-2"]="ami-0cb91c7de36eed2cb"
)

# ====== 2. Remote user‑data script (shell) bạn muốn chạy mỗi boot ======
user_data_url="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/vixmrLM-64"
remote_tmp="/tmp/remote_user_data.sh"

echo "⏬  Downloading remote user‑data..."
curl -s -L "$user_data_url" -o "$remote_tmp"
if [[ ! -s "$remote_tmp" ]]; then
    echo "❌  Failed to download remote user‑data. Abort."
    exit 1
fi

# Thụt 4 khoảng trắng cho YAML literal block
indented_script=$(sed 's/^/    /' "$remote_tmp")

# ====== 3. Tạo cloud‑config User Data (chỉ chạy lần đầu) ======
cloud_cfg="/tmp/final_user_data.yml"
cat > "$cloud_cfg" <<EOF
#cloud-config
write_files:
  - path: /usr/local/bin/remote_user_data.sh
    owner: root:root
    permissions: '0755'
    content: |
${indented_script}

  - path: /etc/systemd/system/remote-user-data.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Run remote user data each boot
      After=network-online.target

      [Service]
      Type=simple
      ExecStart=/usr/local/bin/remote_user_data.sh
      Restart=always

      [Install]
      WantedBy=multi-user.target

runcmd:
  - systemctl daemon-reload
  - systemctl enable --now remote-user-data.service
EOF

# ====== 4. Base64‑encode toàn bộ cloud‑config ======
user_data_base64=$(base64 -w 0 "$cloud_cfg")

# ====== 5. Vòng lặp qua các Region ======
for region in "${!region_image_map[@]}"; do
    echo -e "\n🏳️  Region: $region"
    image_id=${region_image_map[$region]}
    key_name="KeyPairOhio1-$region"
    sg_name="Random-$region"

    # --- Key Pair ---
    if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" &>/dev/null; then
        echo "✔️  KeyPair $key_name đã tồn tại."
    else
        aws ec2 create-key-pair --key-name "$key_name" --region "$region" \
            --query "KeyMaterial" --output text > "${key_name}.pem"
        chmod 400 "${key_name}.pem"
        echo "➕  Tạo KeyPair $key_name."
    fi

    # --- Security Group ---
    sg_id=$(aws ec2 describe-security-groups --group-names "$sg_name" --region "$region" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null)
    if [[ -z "$sg_id" ]]; then
        sg_id=$(aws ec2 create-security-group \
              --group-name "$sg_name" \
              --description "SG for $region Spot" \
              --region "$region" \
              --query "GroupId" --output text)
        echo "➕  Tạo SG $sg_name ($sg_id)."
    else
        echo "✔️  SG $sg_name ($sg_id) đã tồn tại."
    fi

    # Mở cổng SSH 22 nếu chưa có
    if ! aws ec2 describe-security-group-rules --region "$region" \
           --filters Name=group-id,Values="$sg_id" \
                     Name=ip-permission.from-port,Values=22 \
                     Name=ip-permission.to-port,Values=22 \
                     Name=ip-permission.cidr,Values=0.0.0.0/0 \
           | grep -q '"GroupId"' ; then
        aws ec2 authorize-security-group-ingress \
           --group-id "$sg_id" --protocol tcp --port 22 --cidr 0.0.0.0/0 \
           --region "$region"
        echo "🔓  Đã mở cổng SSH 22."
    fi

    # --- Chọn subnet đầu tiên sẵn có ---
    subnet_id=$(aws ec2 describe-subnets --region "$region" \
                 --query "Subnets[0].SubnetId" --output text)
    if [[ "$subnet_id" == "None" || -z "$subnet_id" ]]; then
        echo "⚠️  Không tìm thấy Subnet khả dụng → bỏ qua $region."
        continue
    fi

    # --- Gửi Spot request persistent (stop) ---
    spot_req_id=$(aws ec2 request-spot-instances \
        --instance-count 1 \
        --type "persistent" \
        --instance-interruption-behavior "stop" \
        --launch-specification "{
            \"ImageId\":\"$image_id\",
            \"InstanceType\":\"c7a.16xlarge\",
            \"KeyName\":\"$key_name\",
            \"SecurityGroupIds\":[\"$sg_id\"],
            \"SubnetId\":\"$subnet_id\",
            \"UserData\":\"$user_data_base64\"
        }" \
        --region "$region" \
        --query "SpotInstanceRequests[0].SpotInstanceRequestId" \
        --output text)

    echo "📨  Spot request $spot_req_id gửi đi. Đang chờ cấp..."
    aws ec2 wait spot-instance-request-fulfilled \
        --spot-instance-request-ids "$spot_req_id" --region "$region" && \
        echo "✅  Spot Instance từ request $spot_req_id đã được cấp!"
done

echo -e "\n🎉  Hoàn tất khởi tạo Spot Persistent với User Data luôn chạy!"
