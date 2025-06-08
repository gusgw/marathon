#! /bin/bash
# user-data.sh: AWS EC2 instance initialization script for Marathon
#
# This script is executed by cloud-init when an EC2 instance launches.
# It sets up the environment, installs dependencies, configures storage,
# and launches the main Marathon job.
#
# Configuration:
#   Replace template variables before use:
#   {{ deploy }} - SSH deploy key for GitHub access
#   {{ input }} - GPG private key for decryption
#   {{ output }} - GPG public key for encryption

# Exit on any error
set -e
set -o pipefail

# Configuration
export WAIT=10.0
export SKIP=1
export MAX_WAIT=12

export worker="tobermory-2"
export rclone="${worker}-rclone.conf"
export deploy="id_ed25519-tobermory-github_deploy"
export branch="develop"

# Setup logging
LOG_DIR="/root/user-data-output"
mkdir -p "$LOG_DIR" || { echo "Failed to create log directory"; exit 1; }
chmod a+rwx "$LOG_DIR"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/user-data.log"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting instance initialization"

# Clean up Ubuntu motd
rm -rf /etc/update-motd.d/10-uname /etc/motd 2>/dev/null || true

# Update system packages
log "Updating system packages"
apt -y update \
    1> "$LOG_DIR/apt.update.out" \
    2> "$LOG_DIR/apt.update.err" || error_exit "Failed to update package list"

apt -y upgrade \
    1> "$LOG_DIR/apt.upgrade.out" \
    2> "$LOG_DIR/apt.upgrade.err" || error_exit "Failed to upgrade packages"

# Install required packages
log "Installing required packages"
for pkg in git gawk bc gnupg2 htop stress rclone parallel; do
    log "Installing $pkg"
    apt -y install ${pkg} \
        1> "$LOG_DIR/apt.${pkg}.out" \
        2> "$LOG_DIR/apt.${pkg}.err" || error_exit "Failed to install $pkg"
done

# Wait for admin user creation
log "Waiting for admin user"
counter=0
while ! id admin 2>/dev/null; do
    sleep 5
    counter=$(( counter+1 ))
    if [ "$counter" -ge "$MAX_WAIT" ]; then
        error_exit "Admin user not created after ${MAX_WAIT} attempts"
    fi 
done
log "Admin user found"

# Format and mount NVMe storage
log "Setting up NVMe storage"
if [ -b /dev/nvme1n1 ]; then
    mkfs.ext4 /dev/nvme1n1 || error_exit "Failed to format /dev/nvme1n1"
    mkdir -p /mnt/data || error_exit "Failed to create /mnt/data"
    mount /dev/nvme1n1 /mnt/data || error_exit "Failed to mount /dev/nvme1n1"
    # Create organized log directory structure
    mkdir -p /mnt/data/log/jobs || error_exit "Failed to create jobs log directory"
    mkdir -p /mnt/data/log/system || error_exit "Failed to create system log directory"
    mkdir -p /mnt/data/log/transfers || error_exit "Failed to create transfers log directory"
    mkdir -p /mnt/data/log/reports/daily || error_exit "Failed to create daily reports directory"
    mkdir -p /mnt/data/log/reports/failures || error_exit "Failed to create failures directory"
    mkdir -p /mnt/data/log/reports/performance || error_exit "Failed to create performance directory"
    chown --recursive admin /mnt/data || error_exit "Failed to set ownership on /mnt/data"
else
    error_exit "NVMe device /dev/nvme1n1 not found"
fi

# Create admin bin directory
mkdir -p /home/admin/bin || error_exit "Failed to create admin bin directory"
chown admin /home/admin/bin || error_exit "Failed to set ownership on admin bin"

# Run configuration as admin user
log "Configuring environment as admin user"
sudo -u admin -i \
    1> "$LOG_DIR/configure.out" \
    2> "$LOG_DIR/configure.err" << 'EOS' || error_exit "Failed to configure admin environment"
# Enable error handling in subshell
set -e
set -o pipefail

cd
pwd
whoami
export PATH="/home/admin/bin:${PATH}"
echo ${PATH}

# Cleanup any existing configuration
echo "Cleaning up existing configuration"
rm -rf ~/${rclone} ~/.ssh/${deploy} ~/.ssh/config ~/.gnupg 2>/dev/null || true

# Set up rclone access to S3
echo "Configuring rclone"
cat > ~/${rclone} << 'EOF'
[aws-sydney-std]
type = s3
provider = AWS
env_auth = true
region = ap-southeast-2
location_constraint = ap-southeast-2
acl = private
server_side_encryption = AES256
storage_class = STANDARD
EOF

# Create SSH directory if needed
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Read only deploy keys only
echo "Setting up SSH deploy key"
cat > ~/.ssh/${deploy} << 'EOF'
{{ deploy }}
EOF

# Setup ssh access
chmod 600 ~/.ssh/${deploy} || exit 1
cat > ~/.ssh/config << 'EOF'
Host github
    HostName        github.com
    User            git
    Port            22
    IdentityFile    ~/.ssh/${deploy}
EOF
chmod 600 ~/.ssh/config || exit 1

# Add GitHub to known hosts
echo "Adding GitHub to known hosts"
ssh-keyscan -H github.com >> ~/.ssh/known_hosts 2>/dev/null || exit 1

# Private key for decryption and signing
echo "Setting up GPG keys"
cat > ~/input.private.asc << 'EOF'
{{ input }}
EOF

# Public key for encryption
cat > ~/output.public.asc << 'EOF'
{{ output }}
EOF

# Load runner script
echo "Cloning Marathon repository"
mkdir -p ~/src/ || exit 1
cd ~/src/
rm -rf run
git clone -b ${branch} github:gusgw/run.git \
                1> ~/git.clone.out \
                2> ~/git.clone.err || exit 1
cd run
git submodule update --init --recursive \
                1> ~/git.sub.out \
                2> ~/git.sub.err || exit 1

# Set up transfers
echo "Setting up rclone configuration"
rm -f rclone.conf
ln -s ~/${rclone##*/} rclone.conf || exit 1

# Import keys
echo "Importing GPG keys"
cd
gpg --import *.asc 2>/dev/null || exit 1

# Install metadata script
echo "Installing EC2 metadata script"
mkdir -p bin
cd bin
wget -q http://s3.amazonaws.com/ec2metadata/ec2-metadata || exit 1
chmod u+x ./ec2-metadata || exit 1

# Link the runner for easy execution
echo "Creating runner symlink"
ln -s ../src/run/run.sh run || exit 1

# Run the job
echo "Starting Marathon job"
~/bin/run all 0 \
    1> /mnt/data/log/run.out \
    2> /mnt/data/log/run.err || {
    echo "Marathon job failed with exit code $?"
    exit 1
}
EOS

log "Instance initialization complete"