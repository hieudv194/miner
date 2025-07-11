#!/bin/bash

# Thay bằng OCID thực tế của bạn
COMPARTMENT_ID="ocid1.tenancy.oc1..aaaaaaaapkn5lrcn6mwmop4z3tkdzfphi4njxoxizw7c6njeux3wlil32d5a"

# Kiểm tra SSH key, tạo nếu chưa có
if [ ! -f ~/.ssh/id_rsa ] || [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "🔑 Chưa có SSH key, đang tạo mới..."
    ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
else
    echo "🔑 Đã có SSH key: ~/.ssh/id_rsa.pub"
fi
SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)

# Lấy Availability Domain đầu tiên
AVAILABILITY_DOMAIN=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --query 'data[0].name' --raw-output)
echo "📍 Availability Domain: $AVAILABILITY_DOMAIN"

# Tạo VCN
VCN_NAME="MyFreeVCN"
VCN_CIDR="10.0.0.0/16"
echo "🚧 Đang tạo VCN..."
VCN_ID=$(oci network vcn create --cidr-block "$VCN_CIDR" --compartment-id "$COMPARTMENT_ID" --display-name "$VCN_NAME" --query "data.id" --raw-output)
echo "✅ VCN_ID: $VCN_ID"

# Tạo Internet Gateway
IG_NAME="MyInternetGateway"
echo "🚧 Đang tạo Internet Gateway..."
IG_ID=$(oci network internet-gateway create --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --is-enabled true --display-name "$IG_NAME" --query "data.id" --raw-output)
echo "✅ Internet Gateway ID: $IG_ID"

# Tạo Route Table
RT_NAME="MyRouteTable"
ROUTE_RULES='[{"cidrBlock":"0.0.0.0/0","networkEntityId":"'"$IG_ID"'"}]'
echo "🚧 Đang tạo Route Table..."
RT_ID=$(oci network route-table create --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --display-name "$RT_NAME" --route-rules "$ROUTE_RULES" --query "data.id" --raw-output)
echo "✅ Route Table ID: $RT_ID"

oci network vcn update --vcn-id "$VCN_ID" --default-route-table-id "$RT_ID"

# Tạo Security List
SECURITY_LIST_NAME="MySecurityList"
SECURITY_RULES='[
  {
    "protocol": "6",
    "source": "0.0.0.0/0",
    "tcpOptions": {"destinationPortRange": {"min": 22, "max": 22}},
    "isStateless": false
  },
  {
    "protocol": "1",
    "source": "0.0.0.0/0",
    "icmpOptions": {"type": 3, "code": 4},
    "isStateless": false
  }
]'
echo "🚧 Đang tạo Security List..."
SL_ID=$(oci network security-list create --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --display-name "$SECURITY_LIST_NAME" --ingress-security-rules "$SECURITY_RULES" --egress-security-rules '[{"protocol":"all","destination":"0.0.0.0/0"}]' --query "data.id" --raw-output)
echo "✅ Security List ID: $SL_ID"

# Tạo Subnet
SUBNET_NAME="MyFreeSubnet"
SUBNET_CIDR="10.0.1.0/24"
echo "🚧 Đang tạo Subnet..."
SUBNET_ID=$(oci network subnet create --cidr-block "$SUBNET_CIDR" --compartment-id "$COMPARTMENT_ID" --vcn-id "$VCN_ID" --display-name "$SUBNET_NAME" --availability-domain "$AVAILABILITY_DOMAIN" --security-list-ids "[\"$SL_ID\"]" --route-table-id "$RT_ID" --query "data.id" --raw-output)
echo "✅ Subnet ID: $SUBNET_ID"

# Lấy Image ID Ubuntu 22.04 phù hợp với shape
echo "🔍 Lấy Image ID Ubuntu..."
IMAGE_ID=$(oci compute image list --compartment-id "$COMPARTMENT_ID" --shape "VM.Standard.E2.1.Micro" --query "data[?contains(\"display-name\", 'Canonical-Ubuntu-22.04')].id | [0]" --raw-output)
echo "✅ Image ID: $IMAGE_ID"

# Tạo instance
INSTANCE_NAME="MyFreeInstance"
echo "🚀 Đang tạo Instance..."
oci compute instance launch \
  --availability-domain "$AVAILABILITY_DOMAIN" \
  --compartment-id "$COMPARTMENT_ID" \
  --shape "VM.Standard.E2.1.Micro" \
  --subnet-id "$SUBNET_ID" \
  --display-name "$INSTANCE_NAME" \
  --image-id "$IMAGE_ID" \
  --metadata '{"ssh_authorized_keys":"'"$SSH_PUBLIC_KEY"'"}'

echo "🎉 Hoàn tất: Máy ảo đã được tạo!"
