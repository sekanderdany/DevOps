#!/bin/bash
# Script to fix worker node kubelet configuration issues
# Run as: sudo bash fix-worker-kubelet.sh

set -e

echo "==================================================================="
echo "  Fixing Kubernetes Worker Node kubelet configuration              "
echo "==================================================================="

# Reset kubeadm to start clean
echo "Resetting kubeadm..."
kubeadm reset -f

# Clean up any stale network configurations
echo "Cleaning up network interfaces..."
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true
ip link delete calico.1 2>/dev/null || true
ip link delete tunl0 2>/dev/null || true
ip link delete vxlan.calico 2>/dev/null || true

echo "Creating kubelet configuration directory..."
mkdir -p /var/lib/kubelet

# Create basic kubelet config.yaml
echo "Creating kubelet configuration file..."
cat > /var/lib/kubelet/config.yaml <<EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 0s
    cacheUnauthorizedTTL: 0s
cgroupDriver: systemd
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
cpuManagerReconcilePeriod: 0s
evictionPressureTransitionPeriod: 0s
fileCheckFrequency: 0s
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 0s
imageMinimumGCAge: 0s
logging:
  flushFrequency: 0
  options:
    json:
      infoBufferSize: "0"
  verbosity: 0
memorySwap: {}
nodeStatusReportFrequency: 0s
nodeStatusUpdateFrequency: 0s
rotateCertificates: true
runtimeRequestTimeout: 0s
shutdownGracePeriod: 0s
shutdownGracePeriodCriticalPods: 0s
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 0s
syncFrequency: 0s
volumeStatsAggPeriod: 0s
EOF

echo "Getting new join command from master..."
echo "You need to run 'sudo kubeadm token create --print-join-command' on your master node"
echo "and paste the output below:"
read -p "Paste the 'kubeadm join' command: " JOIN_COMMAND

echo "Executing join command..."
eval "$JOIN_COMMAND"

echo "Restarting kubelet..."
systemctl daemon-reload
systemctl restart kubelet

echo "==================================================================="
echo "  Configuring kubectl on Worker Node                              "
echo "==================================================================="

# Get the regular user name (not root)
REGULAR_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-}")
if [[ -z "$REGULAR_USER" ]]; then
    read -p "Enter the regular user name for kubectl setup: " REGULAR_USER
fi

USER_HOME=$(eval echo ~$REGULAR_USER)

echo "Setting up kubectl configuration..."
echo "Please provide the master node details:"
read -p "Master node IP: " MASTER_IP
read -p "Master node username: " MASTER_USER

# Try to copy kubeconfig via scp
echo "Attempting to copy kubeconfig from master..."
if ssh ${MASTER_USER}@${MASTER_IP} "sudo cp /etc/kubernetes/admin.conf /tmp/admin.conf && sudo chmod 644 /tmp/admin.conf"; then
    if scp ${MASTER_USER}@${MASTER_IP}:/tmp/admin.conf /tmp/admin.conf; then
        # Set up kubectl for regular user
        mkdir -p $USER_HOME/.kube
        cp /tmp/admin.conf $USER_HOME/.kube/config
        chown $REGULAR_USER:$REGULAR_USER $USER_HOME/.kube/config
        chmod 600 $USER_HOME/.kube/config
        
        # Set up kubectl for root
        mkdir -p /root/.kube
        cp /tmp/admin.conf /root/.kube/config
        chmod 600 /root/.kube/config
        
        # Clean up
        rm -f /tmp/admin.conf
        ssh ${MASTER_USER}@${MASTER_IP} "sudo rm -f /tmp/admin.conf"
        
        echo "kubectl configured successfully!"
        echo "Test with: kubectl get nodes"
        KUBECTL_CONFIGURED=true
    else
        echo "Failed to copy kubeconfig via scp."
        KUBECTL_CONFIGURED=false
    fi
else
    echo "Could not connect to master node."
    KUBECTL_CONFIGURED=false
fi

# If automatic configuration failed, provide manual instructions
if [[ "$KUBECTL_CONFIGURED" != "true" ]]; then
    echo ""
    echo "Manual kubectl setup required:"
    echo "1. On master node, run: sudo cat /etc/kubernetes/admin.conf"
    echo "2. Copy the output"
    echo "3. On this worker node, run:"
    echo "   mkdir -p ~/.kube"
    echo "   sudo mkdir -p /root/.kube"
    echo "   # Paste the content into ~/.kube/config"
    echo "   sudo chown \$(id -u):\$(id -g) ~/.kube/config"
    echo "   chmod 600 ~/.kube/config"
    echo "   sudo cp ~/.kube/config /root/.kube/config"
    echo ""
    echo "Alternative: Run kubectl commands from the master node instead."
fi

echo "==================================================================="
echo "  Worker Node Fix Applied                                          "
echo "==================================================================="
echo "Wait about 1-2 minutes, then check the node status with:"
if [[ "$KUBECTL_CONFIGURED" == "true" ]]; then
    echo "kubectl get nodes (from this worker node)"
else
    echo "kubectl get nodes (from the master node)"
fi
echo ""
echo "If the node still shows NotReady, check status with:"
echo "systemctl status kubelet"
echo "==================================================================="