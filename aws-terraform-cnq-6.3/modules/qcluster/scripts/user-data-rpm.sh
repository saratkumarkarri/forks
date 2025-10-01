#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
#User data runs only on first boot cycle

# Install package function
function install_package() {
    local pkg="$1"
    local max_retries=5
    local attempt=0
    local wait_time=10

    if ! command -v "$pkg" > /dev/null 2>&1; then
        echo "$pkg not installed, installing..."
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

# Validate we may reach S3
if [ $(curl -sI -w "%%{http_code}\\n" "s3.${bucket_region}.amazonaws.com" -o /dev/null --connect-timeout 10 --retry 10 --retry-delay 5 --max-time 200) == "405" ]; then
  echo "S3 Reachable"
else
  echo "S3 Unreachable"
  exit 1
fi

#/opt/tools/bin/configure_proxy.sh
#sleep 10
#cloud-init init --local
#sleep 10

# Validate we may reach the internet
if [ $(curl -sLk -w "%%{http_code}\\n" "google.com" -o /dev/null --connect-timeout 10 --retry 3 --retry-delay 5 --max-time 60) == "200" ]; then
  echo "Internet Reachable"
else
  echo "Internet Unreachable"
  exit 1
fi

# Change working dir to /root
cd /root

# Do Rocky specific commands
# Setup EPL repository
if ! egrep -q '^ID="rhel"' /etc/os-release; then
    dnf -y config-manager --set-enabled crb
    install_package epel-release
    crb enable
fi

# Install packages via dnf
install_package "jq"
install_package "systemd-container"
install_package "systemd-resolved"
install_package "unzip"

# Make config files we need and put them where desired
mkdir -p /etc/cloud/cloud.cfg.d
cat << EOF > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
disable_network_activation: true
network:
    config: disabled
EOF
mkdir -p /etc/sysctl.d/
cat << EOF > /etc/sysctl.d/99-rocky9.conf
# Enable io_uring for all processes
kernel.io_uring_disabled = 0
EOF
sysctl -w kernel.io_uring_disabled=0

# Set SELINUX into permissive mode
sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
setenforce Permissive
# Remove packages we don't want
dnf -y remove NetworkManager
systemctl stop NetworkManager.service || echo "NetworkManager not in use"
systemctl mask NetworkManager
# Disable systemd-timesyncd
systemctl stop systemd-timesyncd.service || echo "systemd-timesyncd not in use"
systemctl mask --now systemd-timesyncd
# Disable rpcbind
systemctl stop rpcbind.service || echo "rpcbind not in use"
systemctl mask --now rpcbind
# Disable rpcbind.socket
systemctl stop rpcbind.socket || echo "rpcbind socket not in use"
systemctl mask --now rpcbind.socket
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

# Install AWS cli
if aws --ver >/dev/null 2>&1; then
  echo "AWS CLI already installed"
else
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
fi

export QUMULO_ATLAS_OVERRIDES='{"read_cache_remote_disk_threshold_bytes":1099511627776}'

# Download and install Qumulo rpm
aws s3 cp --region ${bucket_region} s3://"${bucket_name}/${install_s3_prefix}qumulo-core.rpm" ./qumulo-core.rpm
dnf install -y ./qumulo-core.rpm
