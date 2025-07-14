#!/bin/bash
# Kubernetes 1.31 Worker Node Setup Script for Ubuntu 20.04 LTS
# This script automates the setup of a Kubernetes worker node
# Run with: sudo bash k8s-worker-setup.sh

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
echo "[1/8] Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure kernel modules
echo "[2/8] Configuring kernel modules..."
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
echo "[3/8] Installing containerd dependencies..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Install containerd
echo "[4/8] Installing containerd..."
apt-get install -y containerd

# Create default configuration
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null

# Configure containerd to use systemd cgroup driver
echo "[5/8] Configuring containerd to use systemd cgroup driver..."
sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

# Restart containerd
systemctl restart containerd
systemctl enable containerd

print_section "Installing Kubernetes Components"

# Add Kubernetes repository
echo "[6/8] Adding Kubernetes repository..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components
echo "[7/9] Installing Kubernetes components..."
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "[8/9] Starting kubelet service..."
systemctl enable kubelet
systemctl restart kubelet

print_section "Configuring kubectl shortcuts"

# Add kubectl alias to bashrc for the current user
USERNAME=$(logname || echo "${SUDO_USER:-$USER}")
USER_HOME=$(eval echo ~$USERNAME)

# Add to current user's bashrc
echo "Adding kubectl shortcuts for user ${USERNAME}..."
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

print_section "Join Cluster and Configure kubectl"

echo "[9/11] Setting up cluster membership and kubectl configuration..."
echo "This worker node needs to join the Kubernetes cluster and configure kubectl access."
echo ""
read -p "Has this node already joined the cluster? (yes/no): " JOINED_CLUSTER

if [[ "$JOINED_CLUSTER" != "yes" ]]; then
    echo "You need to join this node to the cluster first."
    echo "On the master node, run: sudo kubeadm token create --print-join-command"
    echo "Then paste the output below:"
    echo ""
    read -p "Paste the 'kubeadm join' command here: " JOIN_COMMAND
    
    # Execute the join command
    echo "Executing join command..."
    eval "sudo $JOIN_COMMAND"
    
    if [ $? -ne 0 ]; then
        echo "Failed to join the cluster. Please check the join command and try again."
        exit 1
    else
        echo "Successfully joined the cluster!"
        JOINED_CLUSTER="yes"
    fi
fi

if [[ "$JOINED_CLUSTER" == "yes" ]]; then
    echo "[10/11] Configuring kubectl access to master node..."
    read -p "Enter Kubernetes master node IP address: " MASTER_IP
    
    # Try to copy admin.conf in a few different ways
    echo "Attempting to copy kubeconfig from master node..."
    echo "Option 1: Enter master node username to copy via scp"
    read -p "Enter username on master node (or press Enter to skip): " MASTER_USER
    
    if [[ -n "$MASTER_USER" ]]; then
        # Try scp if user provided a username
        echo "Copying kubeconfig via scp..."
        mkdir -p $USER_HOME/.kube
        mkdir -p /root/.kube
        echo "Note: You may be asked for the password of user '${MASTER_USER}' on the master node"
        if ssh ${MASTER_USER}@${MASTER_IP} "sudo cp /etc/kubernetes/admin.conf /tmp/admin.conf && sudo chmod 644 /tmp/admin.conf" && \
           scp ${MASTER_USER}@${MASTER_IP}:/tmp/admin.conf $USER_HOME/.kube/config && \
           ssh ${MASTER_USER}@${MASTER_IP} "sudo rm /tmp/admin.conf"; then
            echo "Successfully copied kubeconfig via scp!"
            chown ${USERNAME}:${USERNAME} $USER_HOME/.kube/config
            chmod 600 $USER_HOME/.kube/config
            cp $USER_HOME/.kube/config /root/.kube/config
            chmod 600 /root/.kube/config
            KUBECTL_CONFIGURED=true
        else
            echo "Failed to copy via scp. Let's try another method."
        fi
    else
        echo "Skipping scp method."
    fi
    
    # If we couldn't get the kubeconfig via scp, provide instructions
    if [[ "$KUBECTL_CONFIGURED" != "true" ]]; then
        echo "Option 2: On the master node, run this command to get the kubeconfig:"
        echo "sudo cat /etc/kubernetes/admin.conf"
        echo ""
        echo "Then copy the output and paste it below:"
        echo "Paste kubeconfig content below and press Ctrl+D when done:"
        mkdir -p $USER_HOME/.kube
        mkdir -p /root/.kube
        cat > $USER_HOME/.kube/config
        if [[ -s "$USER_HOME/.kube/config" ]]; then
            echo "Kubeconfig file created from pasted content!"
            chown ${USERNAME}:${USERNAME} $USER_HOME/.kube/config
            chmod 600 $USER_HOME/.kube/config
            cp $USER_HOME/.kube/config /root/.kube/config
            chmod 600 /root/.kube/config
        else
            echo "No content pasted or an error occurred."
            echo ""
            echo "You'll need to configure kubectl manually after this script completes."
            echo "On the master node, run:"
            echo "  sudo cat /etc/kubernetes/admin.conf"
            echo ""
            echo "Then on this worker node, run:"
            echo "  mkdir -p ~/.kube"
            echo "  sudo mkdir -p /root/.kube"
            echo "  # Paste the content into ~/.kube/config and /root/.kube/config"
        fi
    fi
else
    echo "There was an issue with the configuration. Please try running the script again."
    echo "Make sure you have joined the cluster successfully before configuring kubectl."
fi

print_section "Kubernetes Worker Node Setup Complete!"

echo "[11/11] Worker node setup completed!"
echo ""
if [[ "$KUBECTL_CONFIGURED" == "true" ]]; then
    echo "This node has successfully:"
    echo "1. Joined the Kubernetes cluster"
    echo "2. Configured kubectl to access the cluster"
    echo ""
    echo "You can verify this by running: kubectl get nodes"
    echo "or the shorter version: k get nodes"
else
    echo "This node is now ready to use with kubectl!"
    echo "Try running: kubectl get nodes"
    echo ""
    echo "If kubectl still doesn't work, check your kubeconfig file at ~/.kube/config"
fi
