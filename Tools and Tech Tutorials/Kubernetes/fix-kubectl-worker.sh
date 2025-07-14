#!/bin/bash
# Fix kubectl on worker nodes script
# Run this script to fix kubectl configuration on worker nodes after joining a cluster
# Run with: sudo bash fix-kubectl-worker.sh

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
USERNAME=$(logname || echo "${SUDO_USER:-$USER}")
USER_HOME=$(eval echo ~$USERNAME)

print_section "Fixing kubectl Configuration"

echo "This script will configure kubectl on this worker node to connect to your Kubernetes master."
echo ""

# Ask for master node details
read -p "Enter Kubernetes master node IP address: " MASTER_IP

# Try different methods to get the kubeconfig
echo "Choose a method to get kubeconfig from master:"
echo "1. Copy via scp (requires SSH access to master)"
echo "2. Manual paste (requires viewing admin.conf on master)"
read -p "Choose method [1/2]: " METHOD

if [[ "$METHOD" == "1" ]]; then
    read -p "Enter username on master node: " MASTER_USER
    
    echo "Copying kubeconfig from master node..."
    # Create directories
    mkdir -p $USER_HOME/.kube
    mkdir -p /root/.kube
    
    # Try to copy using scp
    echo "Note: You may be asked for the password of user '${MASTER_USER}' on the master node"
    if ssh ${MASTER_USER}@${MASTER_IP} "sudo cp /etc/kubernetes/admin.conf /tmp/admin.conf && sudo chmod 644 /tmp/admin.conf" && \
       scp ${MASTER_USER}@${MASTER_IP}:/tmp/admin.conf $USER_HOME/.kube/config && \
       ssh ${MASTER_USER}@${MASTER_IP} "sudo rm /tmp/admin.conf"; then
        echo "Successfully copied kubeconfig from master!"
    else
        echo "Failed to copy kubeconfig via scp."
        echo "Let's try the manual method..."
        METHOD="2"
    fi
fi

if [[ "$METHOD" == "2" ]]; then
    echo "On the master node, run: sudo cat /etc/kubernetes/admin.conf"
    echo "Copy the entire output and paste it below."
    echo "Press Ctrl+D on a new line when done."
    echo ""
    echo "Paste kubeconfig content now:"
    
    # Create directories
    mkdir -p $USER_HOME/.kube
    mkdir -p /root/.kube
    
    # Capture pasted content
    cat > $USER_HOME/.kube/config
    
    # Check if content was pasted
    if [[ ! -s "$USER_HOME/.kube/config" ]]; then
        echo "No content was pasted or an error occurred!"
        exit 1
    fi
fi

# Set proper ownership and permissions
chown ${USERNAME}:${USERNAME} $USER_HOME/.kube/config
chmod 600 $USER_HOME/.kube/config

# Also setup for root
cp $USER_HOME/.kube/config /root/.kube/config
chmod 600 /root/.kube/config

print_section "Configuring kubectl shortcuts"

# Add kubectl alias to bashrc for the current user
echo "Adding kubectl shortcuts for user ${USERNAME}..."
if ! grep -q "alias k='kubectl'" $USER_HOME/.bashrc; then
    cat >> $USER_HOME/.bashrc <<EOF
export KUBECONFIG=~/.kube/config
alias k='kubectl'
source <(kubectl completion bash)
complete -F __start_kubectl k
EOF
fi

# Create system-wide shortcut for all users
echo "Creating system-wide kubectl shortcut..."
cat > /etc/profile.d/k8s-shortcuts.sh <<EOF
#!/bin/bash
alias k='kubectl'
EOF
chmod +x /etc/profile.d/k8s-shortcuts.sh

# Create an executable symlink for even quicker access
ln -sf /usr/bin/kubectl /usr/local/bin/k

print_section "Testing kubectl Configuration"

echo "Testing kubectl connection to the cluster..."
if kubectl get nodes; then
    echo "Success! kubectl is properly configured."
else
    echo "There seems to be an issue with the kubectl configuration."
    echo "Please check your network connection to the master node at ${MASTER_IP}."
    echo "Also verify that the master node's API server is running."
fi

print_section "kubectl Configuration Complete"

echo "You can now use kubectl and k commands to interact with your cluster."
echo "For example:"
echo "  kubectl get nodes"
echo "  k get pods --all-namespaces"
echo ""
echo "If you see any errors, please ensure:"
echo "1. The master node is up and running"
echo "2. Network connectivity exists between this worker and the master"
echo "3. The worker node has successfully joined the cluster"
