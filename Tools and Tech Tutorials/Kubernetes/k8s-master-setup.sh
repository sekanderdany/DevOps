#!/bin/bash
# Kubernetes 1.31 Master Node Setup Script for Ubuntu 20.04 LTS
# This script automates the setup of a Kubernetes master node
# Run with: sudo bash k8s-master-setup.sh

set -e

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" 
    exit 1
fi

# Variables
KUBERNETES_VERSION="1.31"
POD_NETWORK_CIDR="10.88.0.0/16"
USERNAME=$(logname || echo "${SUDO_USER:-$USER}")
USER_HOME=$(eval echo ~$USERNAME)

print_section "Cleaning Previous Kubernetes Installation"

# Reset kubeadm if it exists
if command -v kubeadm &> /dev/null; then
    echo "Found existing Kubernetes installation. Resetting..."
    kubeadm reset -f || true
fi

# Remove Kubernetes packages and configurations
echo "Removing Kubernetes packages and configurations..."
apt-get remove -y --purge kubeadm kubectl kubelet kubernetes-cni || true
apt-get autoremove -y || true

# Clean up directories
echo "Removing Kubernetes directories..."
rm -rf /etc/kubernetes/
rm -rf /var/lib/etcd/
rm -rf $USER_HOME/.kube/
rm -rf /root/.kube/
rm -rf /var/lib/kubelet/
rm -rf /etc/cni/
rm -rf /var/lib/cni/
rm -f /etc/apt/sources.list.d/kubernetes.list

# Stop and disable services
echo "Stopping Kubernetes services..."
systemctl stop kubelet || true
systemctl disable kubelet || true

# Clean containerd if present
if command -v containerd &> /dev/null; then
    echo "Resetting containerd..."
    systemctl stop containerd || true
    apt-get remove -y --purge containerd || true
    rm -rf /etc/containerd/* || true
fi

echo "Previous Kubernetes installation cleaned up."

print_section "System Preparation"

# Disable swap
echo "[1/13] Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure kernel modules
echo "[2/13] Configuring kernel modules..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

# Load kernel modules
modprobe overlay
modprobe br_netfilter

# Configure sysctl parameters
cat > /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl parameters
sysctl --system

print_section "Installing containerd (Container Runtime)"

# Install containerd dependencies
echo "[3/13] Installing containerd dependencies..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Install containerd
echo "[4/13] Installing containerd..."
apt-get install -y containerd

# Create default configuration
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

# Configure containerd to use systemd cgroup driver
echo "[5/13] Configuring containerd to use systemd cgroup driver..."
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd
systemctl enable containerd

print_section "Installing Kubernetes Components"

# Add Kubernetes repository
echo "[6/13] Adding Kubernetes repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Handle held packages first
echo "[6.5/13] Handling held packages..."
apt-mark unhold kubelet kubeadm kubectl || true

# Install Kubernetes components
echo "[7/13] Installing Kubernetes components..."
apt-get update
apt-get install -y --allow-change-held-packages kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

print_section "Initializing Kubernetes Control Plane"

# Pull Kubernetes images
echo "[8/13] Pulling Kubernetes images..."
kubeadm config images pull

# Initialize Kubernetes cluster
echo "[9/13] Initializing Kubernetes cluster..."
kubeadm init --pod-network-cidr=${POD_NETWORK_CIDR} --ignore-preflight-errors=NumCPU

# Setup kubectl for the current user
echo "[10/13] Setting up kubectl for user ${USERNAME}..."
mkdir -p $USER_HOME/.kube
cp -i /etc/kubernetes/admin.conf $USER_HOME/.kube/config
chown -R ${USERNAME}:${USERNAME} $USER_HOME/.kube
export KUBECONFIG=$USER_HOME/.kube/config

# Setup kubectl for root
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

print_section "Installing Calico Network Plugin"

# Install Calico CNI
echo "[11/13] Installing Calico network plugin..."
su - ${USERNAME} -c "curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml"
su - ${USERNAME} -c "kubectl apply -f calico.yaml"

print_section "Configuring kubectl aliases and completions"

# Configure kubectl aliases and completions
echo "[12/13] Configuring kubectl aliases and completions..."
cat >> $USER_HOME/.bashrc <<EOF
export KUBECONFIG=~/.kube/config
alias k='kubectl'
source <(kubectl completion bash)
complete -F __start_kubectl k
EOF

# Create system-wide shortcut for all users
echo "Creating system-wide kubectl shortcut..."
cat > /etc/profile.d/k8s-shortcuts.sh <<EOF
#!/bin/bash
alias k='kubectl'
EOF
chmod +x /etc/profile.d/k8s-shortcuts.sh

# Create an executable symlink for even quicker access
ln -sf /usr/bin/kubectl /usr/local/bin/k

print_section "Getting Join Command for Worker Nodes"

# Get join command
echo "[13/13] Creating token for worker nodes to join:"
JOIN_COMMAND=$(kubeadm token create --print-join-command)
echo -e "\n=== Worker Node Join Command ==="
echo "Run the following command on your worker nodes:"
echo "sudo ${JOIN_COMMAND}"
echo -e "===============================\n"

# Save join command to a file for easy access later
echo "#!/bin/bash" > $USER_HOME/worker-join.sh
echo "sudo ${JOIN_COMMAND}" >> $USER_HOME/worker-join.sh
chmod +x $USER_HOME/worker-join.sh
chown ${USERNAME}:${USERNAME} $USER_HOME/worker-join.sh
echo "Join command saved to $USER_HOME/worker-join.sh"

# Create a script to copy configuration to worker nodes
cat > $USER_HOME/copy-kubeconfig-to-worker.sh <<EOF
#!/bin/bash
# Script to securely copy kubeconfig to a worker node
# Usage: ./copy-kubeconfig-to-worker.sh <worker-ip> <worker-username>

if [ \$# -lt 2 ]; then
    echo "Usage: \$0 <worker-ip> <worker-username>"
    echo "Example: \$0 192.168.0.176 dany"
    exit 1
fi

WORKER_IP=\$1
WORKER_USER=\$2

echo "Copying kubeconfig to \$WORKER_USER@\$WORKER_IP..."
# Create a temporary copy with proper permissions
sudo cp /etc/kubernetes/admin.conf /tmp/admin.conf
sudo chmod 644 /tmp/admin.conf

# Copy to the worker node
scp /tmp/admin.conf \$WORKER_USER@\$WORKER_IP:/tmp/admin.conf

# Execute remote commands to set up kubectl
ssh \$WORKER_USER@\$WORKER_IP "sudo mkdir -p \\\$HOME/.kube /root/.kube && \\
                               sudo mv /tmp/admin.conf \\\$HOME/.kube/config && \\
                               sudo cp \\\$HOME/.kube/config /root/.kube/config && \\
                               sudo chown \$(id -u):\$(id -g) \\\$HOME/.kube/config && \\
                               sudo chmod 600 \\\$HOME/.kube/config /root/.kube/config"

# Clean up temporary file
sudo rm -f /tmp/admin.conf

echo "kubectl configuration copied successfully to \$WORKER_IP"
echo "The worker node should now be able to use kubectl to access the cluster"
EOF

chmod +x $USER_HOME/copy-kubeconfig-to-worker.sh
chown ${USERNAME}:${USERNAME} $USER_HOME/copy-kubeconfig-to-worker.sh
echo "Worker kubeconfig copy script saved to $USER_HOME/copy-kubeconfig-to-worker.sh"

# Create a worker node configuration script
MASTER_IP=$(hostname -I | awk '{print $1}')
cat > $USER_HOME/configure-worker-kubectl.sh <<EOF
#!/bin/bash
# This script must be run with sudo privileges
# Script to configure kubectl on worker nodes to connect to this master
# Run this script on worker nodes after joining the cluster

# Variables
WORKER_USERNAME=\$(logname || echo "\${SUDO_USER:-\$USER}")
WORKER_HOME=\$(eval echo ~\$WORKER_USERNAME)

# Create directories
mkdir -p \$WORKER_HOME/.kube
mkdir -p /root/.kube

# Copy the kubeconfig content
cat > \$WORKER_HOME/.kube/config <<'KUBECONFIG_END'
$(cat /etc/kubernetes/admin.conf)
KUBECONFIG_END

# Set proper ownership and permissions
chown \$WORKER_USERNAME:\$WORKER_USERNAME \$WORKER_HOME/.kube/config
chmod 600 \$WORKER_HOME/.kube/config

# Also set up for root
cp \$WORKER_HOME/.kube/config /root/.kube/config
chmod 600 /root/.kube/config

echo "kubectl is now configured to access the cluster at ${MASTER_IP}!"
EOF

chmod +x $USER_HOME/configure-worker-kubectl.sh
chown ${USERNAME}:${USERNAME} $USER_HOME/configure-worker-kubectl.sh
echo "Worker kubectl configuration script saved to $USER_HOME/configure-worker-kubectl.sh"

print_section "Kubernetes Master Setup Complete!"

echo "The Kubernetes control plane has been initialized successfully!"
echo ""
echo "To start using the cluster as the regular user:"
echo "  su - ${USERNAME}"
echo "  kubectl get nodes"
echo ""
echo "To add worker nodes to this cluster, run the displayed join command on each worker node."
echo ""
echo "Note: Please wait a few minutes for all system pods to start up before using the cluster."
echo "      You can check the status with: kubectl get pods --all-namespaces"
