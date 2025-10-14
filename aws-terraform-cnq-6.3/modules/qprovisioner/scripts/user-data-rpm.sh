Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
#User data runs every boot cycle

if [ $(curl -sI -w "%%{http_code}\\n" "s3.${bucket_region}.amazonaws.com" -o /dev/null --connect-timeout 10 --retry 10 --retry-delay 5 --max-time 200) == "405" ]; then
  echo "S3 Reachable"
else
  echo "S3 Unreachable"
  exit 1
fi

cd /root

function install_package() {
    local pkg="$1"
    local max_retries=5
    local attempt=0
    local wait_time=10

    if ! command -v "$pkg" > /dev/null 2>&1; then
        echo "$pkg not installed, installing..."
        sleep 5
        until dnf install -y "$pkg"; do
            attempt=$((attempt + 1))
            if [ "$attempt" -ge "$max_retries" ]; then
                echo "Failed to install $pkg after $max_retries attempts, exiting."
                exit 1
            fi
            echo "Could not get lock, retrying in $wait_time seconds... (Attempt: $attempt)"
            sleep "$wait_time"
        done
    else
        echo "$pkg already installed"
    fi
}

# Do Rocky specific commands
# Setup EPL repository
if ! egrep -q '^ID="rhel"' /etc/os-release; then
    dnf -y config-manager --set-enabled crb
    install_package epel-release
    crb enable
fi

# Install packages via dnf
install_package "jq"
install_package "wget"
install_package "traceroute"
install_package "unzip"

# Set SELINUX into permissive mode
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
setenforce Permissive

# Disable firewalld
systemctl stop firewalld.service  || echo "firewalld not in use"
systemctl mask --now firewalld
# Misc Os Setup
sysctl --system

# Install and run amazon-ssm-agent
if which amazon-ssm-agent >/dev/null 2>&1; then
  echo "AWS SSM Agent already installed"
else
  dnf install -y https://s3.${bucket_region}.amazonaws.com/amazon-ssm-${bucket_region}/latest/linux_amd64/amazon-ssm-agent.rpm
  systemctl enable amazon-ssm-agent
  systemctl start amazon-ssm-agent
fi

# Install AWS CLI
if aws --ver >/dev/null 2>&1; then
  echo "AWS CLI already installed"
else
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" --connect-timeout 10 --retry 10 --retry-delay 5
  unzip -q awscliv2.zip
  ./aws/install
fi

#if [[ ! -e "provision.sh" ]]; then
  aws s3 cp --region ${bucket_region} s3://"${bucket_name}/${scripts_s3_prefix}provision.sh" ./provision.sh
#fi

sed "" provision.sh > provision-sub.sh
sed -i.rep "s|\$${bucket_name}|${bucket_name}|g" provision-sub.sh
sed -i.rep "s|\$${bucket_region}|${bucket_region}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_fqdn}|${cluster_fqdn}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_name}|${cluster_name}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_secrets_arn}|${cluster_secrets_arn}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_sg_id}|${cluster_sg_id}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_persistent_bucket_uris}|${cluster_persistent_bucket_uris}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_persistent_bucket_names}|${cluster_persistent_bucket_names}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_persistent_storage_capacity_limit}|${cluster_persistent_storage_capacity_limit}|g" provision-sub.sh
sed -i.rep "s|\$${cluster_persistent_storage_type}|${cluster_persistent_storage_type}|g" provision-sub.sh
sed -i.rep "s|\$${deployment_unique_name}|${deployment_unique_name}|g" provision-sub.sh
sed -i.rep "s|\$${ena_express}|${ena_express}|g" provision-sub.sh
sed -i.rep "s|\$${existing_deployment_unique_name}|${existing_deployment_unique_name}|g" provision-sub.sh
sed -i.rep "s|\$${fault_domain_ids}|${fault_domain_ids}|g" provision-sub.sh
sed -i.rep "s|\$${flash_iops}|${flash_iops}|g" provision-sub.sh
sed -i.rep "s|\$${flash_tput}|${flash_tput}|g" provision-sub.sh
sed -i.rep "s|\$${floating_ips}|${floating_ips}|g" provision-sub.sh
sed -i.rep "s|\$${functions_s3_prefix}|${functions_s3_prefix}|g" provision-sub.sh
sed -i.rep "s|\$${install_s3_prefix}|${install_s3_prefix}|g" provision-sub.sh
sed -i.rep "s|\$${instance_ids}|${instance_ids}|g" provision-sub.sh
sed -i.rep "s|\$${max_floating_ips}|${max_floating_ips}|g" provision-sub.sh
sed -i.rep "s|\$${node1_ip}|${node1_ip}|g" provision-sub.sh
sed -i.rep "s|\$${number_azs}|${number_azs}|g" provision-sub.sh
sed -i.rep "s|\$${primary_ips}|${primary_ips}|g" provision-sub.sh
sed -i.rep "s|\$${replacement_cluster}|${replacement_cluster}|g" provision-sub.sh
sed -i.rep "s|\$${region}|${region}|g" provision-sub.sh
sed -i.rep "s|\$${scripts_path}|${scripts_path}|g" provision-sub.sh
sed -i.rep "s|\$${target_node_count}|${target_node_count}|g" provision-sub.sh
sed -i.rep "s|\$${temporary_password}|${temporary_password}|g" provision-sub.sh
sed -i.rep "s|\$${tun_refill_IOPS}|${tun_refill_IOPS}|g" provision-sub.sh
sed -i.rep "s|\$${tun_refill_Bps}|${tun_refill_Bps}|g" provision-sub.sh
sed -i.rep "s|\$${tun_EBS_BW}|${tun_EBS_BW}|g" provision-sub.sh
sed -i.rep "s|\$${tun_EC2_BW}|${tun_EC2_BW}|g" provision-sub.sh
sed -i.rep "s|\$${tun_disk_count}|${tun_disk_count}|g" provision-sub.sh
sed -i.rep "s|\$${version}|${version}|g" provision-sub.sh
  
chmod 700 provision-sub.sh
./provision-sub.sh

poweroff