#!/bin/bash -xe
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
#User data runs only on first boot cycle

#Install package function

function install_package() {
    local pkg="$1"
    local max_retries=5
    local attempt=0
    local wait_time=10

    if ! command -v "$pkg" > /dev/null 2>&1; then
        echo "$pkg not installed, installing..."
        sleep 5
        until apt-get install -y "$pkg"; do
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

# Remove contents in a dir
function clean_dir() {
    if [ -e $1 ] && [ ! $(find $1 -type d -empty) ]; then
    rm -rf $1/*
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

# Change working directory to root
cd /root

# Get linux revision
OS_RELEASE=`uname -r | tr -d '[:space:]'`

# Install packages via apt
apt-get update
install_package "jq"
install_package "unzip"
install_package "linux-tools-common"
install_package "linux-tools-$OS_RELEASE"
install_package "systemd-container"

# Remove the host's current network configuration
clean_dir /run/systemd/network/
clean_dir /etc/netplan/

# Stop cloud-init from configuring the host's networking
mkdir -p /etc/cloud/cloud.cfg.d
cat << EOF > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
disable_network_activation: true
network:
    config: disabled
EOF

# Disable systemd-timesyncd. Needed on Debian, not Ubuntu
systemctl stop systemd-timesyncd.service || echo "systemd-timesyncd not in use"
systemctl mask --now systemd-timesyncd

# Disable apparmor from preventing chrony from being run inside the container
# AppArmor may not be running, but we run this incase it is
apparmor_parser -R /etc/apparmor.d/usr.sbin.chronyd || echo "apparmor not in use"

# Install AWS CLI
if aws --ver >/dev/null 2>&1; then
  echo "AWS CLI already installed"
else
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -q awscliv2.zip
  ./aws/install
fi

export QUMULO_ATLAS_OVERRIDES='{"read_cache_remote_disk_threshold_bytes":1099511627776}'

aws s3 cp --region ${bucket_region} s3://"${bucket_name}/${install_s3_prefix}qumulo-core.deb" ./qumulo-core.deb

apt install -y ./qumulo-core.deb
