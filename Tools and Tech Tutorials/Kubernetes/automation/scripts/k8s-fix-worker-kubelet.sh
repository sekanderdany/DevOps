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
echo "  Worker Node Fix Applied                                          "
echo "==================================================================="
echo "Wait about 1-2 minutes, then check the node status on the master with:"
echo "kubectl get nodes"
echo ""
echo "If the node still shows NotReady, check status with:"
echo "systemctl status kubelet"
echo "==================================================================="