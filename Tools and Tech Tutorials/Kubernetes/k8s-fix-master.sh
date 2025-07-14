#!/bin/bash
# Script to fix master node kubelet and API server configuration issues
# Run as: sudo bash k8s-fix-master.sh

set -e

echo "==================================================================="
echo "  Fixing Kubernetes Master Node Issues                            "
echo "==================================================================="

# Get the regular user name (not root)
REGULAR_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
if [[ -z "$REGULAR_USER" ]]; then
    read -p "Enter the regular user name: " REGULAR_USER
fi

USER_HOME=$(eval echo ~$REGULAR_USER)

echo "This script will fix common master node issues:"
echo "1. API server not starting"
echo "2. etcd data corruption"
echo "3. kubelet configuration problems"
echo "4. kubectl access issues"
echo ""
read -p "Do you want to continue? (yes/no): " CONTINUE

if [[ "$CONTINUE" != "yes" ]]; then
    echo "Exiting..."
    exit 0
fi

echo "==================================================================="
echo "  Diagnosing Issues                                                "
echo "==================================================================="

# Check current status
echo "Checking current cluster status..."
systemctl status kubelet || echo "Kubelet service issues detected"
systemctl status containerd || echo "Containerd service issues detected"

# Check if API server is running
echo "Checking API server status..."
curl -k https://localhost:6443/healthz 2>/dev/null || echo "API server not responding"

# Check etcd
echo "Checking etcd status..."
crictl ps -a | grep etcd || echo "etcd container issues detected"

echo "==================================================================="
echo "  Stopping Services                                                "
echo "==================================================================="

echo "Stopping kubelet..."
systemctl stop kubelet

echo "Stopping containerd..."
systemctl stop containerd

echo "==================================================================="
echo "  Cleaning Up Corrupted Data                                       "
echo "==================================================================="

echo "Cleaning up etcd data (this will reset your cluster)..."
read -p "WARNING: This will delete all cluster data. Continue? (yes/no): " CONFIRM_RESET

if [[ "$CONFIRM_RESET" == "yes" ]]; then
    echo "Removing etcd data..."
    rm -rf /var/lib/etcd/* || true
    
    echo "Cleaning up kubelet data..."
    rm -rf /var/lib/kubelet/* || true
    
    echo "Cleaning up network interfaces..."
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    ip link delete calico.1 2>/dev/null || true
    ip link delete tunl0 2>/dev/null || true
    ip link delete vxlan.calico 2>/dev/null || true
    
    echo "Cleaning up iptables rules..."
    iptables -F || true
    iptables -t nat -F || true
    iptables -t mangle -F || true
    iptables -X || true
    
    echo "Removing old kubernetes configuration..."
    rm -rf /etc/kubernetes/manifests/* || true
    rm -rf $USER_HOME/.kube/* || true
    rm -rf /root/.kube/* || true
fi

echo "==================================================================="
echo "  Restarting Services                                              "
echo "==================================================================="

echo "Starting containerd..."
systemctl start containerd
systemctl enable containerd

echo "Starting kubelet..."
systemctl start kubelet
systemctl enable kubelet

if [[ "$CONFIRM_RESET" == "yes" ]]; then
    echo "==================================================================="
    echo "  Reinitializing Cluster                                           "
    echo "==================================================================="
    
    # Get the master IP
    MASTER_IP=$(hostname -I | awk '{print $1}')
    
    echo "Reinitializing Kubernetes cluster..."
    kubeadm init --pod-network-cidr=10.88.0.0/16 --ignore-preflight-errors=NumCPU
    
    echo "Setting up kubectl for user ${REGULAR_USER}..."
    mkdir -p $USER_HOME/.kube
    cp -i /etc/kubernetes/admin.conf $USER_HOME/.kube/config
    chown -R ${REGULAR_USER}:${REGULAR_USER} $USER_HOME/.kube
    
    echo "Setting up kubectl for root..."
    mkdir -p /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    
    echo "Installing Calico network plugin..."
    su - ${REGULAR_USER} -c "curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.29.3/manifests/calico.yaml"
    su - ${REGULAR_USER} -c "kubectl apply -f calico.yaml"
    
    echo "==================================================================="
    echo "  Getting New Join Command                                         "
    echo "==================================================================="
    
    echo "New join command for worker nodes:"
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    echo "sudo ${JOIN_COMMAND}"
    
    # Save join command to a file
    echo "#!/bin/bash" > $USER_HOME/worker-join.sh
    echo "sudo ${JOIN_COMMAND}" >> $USER_HOME/worker-join.sh
    chmod +x $USER_HOME/worker-join.sh
    chown ${REGULAR_USER}:${REGULAR_USER} $USER_HOME/worker-join.sh
    echo "Join command saved to $USER_HOME/worker-join.sh"
    
else
    echo "==================================================================="
    echo "  Checking Cluster Status                                          "
    echo "==================================================================="
    
    echo "Waiting for services to start..."
    sleep 30
    
    echo "Checking API server..."
    if curl -k https://localhost:6443/healthz 2>/dev/null; then
        echo "API server is responding!"
    else
        echo "API server still not responding. Manual intervention may be required."
    fi
    
    echo "Checking cluster status..."
    if [[ -f "$USER_HOME/.kube/config" ]]; then
        su - ${REGULAR_USER} -c "kubectl get nodes" || echo "kubectl command failed"
    else
        echo "kubectl not configured. Setting up..."
        mkdir -p $USER_HOME/.kube
        cp -i /etc/kubernetes/admin.conf $USER_HOME/.kube/config 2>/dev/null || true
        chown -R ${REGULAR_USER}:${REGULAR_USER} $USER_HOME/.kube 2>/dev/null || true
        mkdir -p /root/.kube
        cp -i /etc/kubernetes/admin.conf /root/.kube/config 2>/dev/null || true
    fi
fi

echo "==================================================================="
echo "  Master Node Fix Complete                                         "
echo "==================================================================="

if [[ "$CONFIRM_RESET" == "yes" ]]; then
    echo "Cluster has been reset and reinitialized!"
    echo ""
    echo "Next steps:"
    echo "1. Wait 2-3 minutes for all system pods to start"
    echo "2. Check cluster status: kubectl get nodes"
    echo "3. Check system pods: kubectl get pods -n kube-system"
    echo "4. Join worker nodes using the new join command above"
else
    echo "Services have been restarted."
    echo ""
    echo "Check cluster status with:"
    echo "kubectl get nodes"
    echo "kubectl get pods -n kube-system"
    echo ""
    echo "If issues persist, re-run this script and choose 'yes' to reset the cluster."
fi

echo "==================================================================="
