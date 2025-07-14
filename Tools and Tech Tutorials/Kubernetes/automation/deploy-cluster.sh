#!/bin/bash
# Kubernetes 3-Node Cluster Deployment Script
# This script automates the deployment of a 3-node Kubernetes cluster using Vagrant
# Run with: bash deploy-cluster.sh

set -e

# Script start time
START_TIME=$(date +%s)

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Display time elapsed
show_time_elapsed() {
  local end_time=$(date +%s)
  local elapsed=$((end_time - START_TIME))
  local mins=$((elapsed / 60))
  local secs=$((elapsed % 60))
  
  echo "Time elapsed: ${mins}m ${secs}s"
}

# Check if required tools are installed
check_prerequisites() {
  print_section "Checking Prerequisites"
  
  # Check for VirtualBox
  if ! command -v VBoxManage &> /dev/null; then
    echo "[ERROR] VirtualBox is not installed or not in PATH."
    echo "Please install VirtualBox from https://www.virtualbox.org/wiki/Downloads"
    exit 1
  fi
  echo "[✓] VirtualBox is installed."
  
  # Check for Vagrant
  if ! command -v vagrant &> /dev/null; then
    echo "[ERROR] Vagrant is not installed or not in PATH."
    echo "Please install Vagrant from https://www.vagrantup.com/downloads"
    exit 1
  fi
  echo "[✓] Vagrant is installed."
  
  # Check for SSH key setup
  if [ ! -f "./id_rsa" ] || [ ! -f "./id_rsa.pub" ]; then
    echo "[i] SSH keys not found. Running setup-ssh-keys.sh to create them..."
    bash ./setup-ssh-keys.sh
  else
    echo "[✓] SSH keys are present."
  fi
}

# Deploy the virtual machines using Vagrant
deploy_vms() {
  print_section "Deploying Virtual Machines"
  
  # Check if VMs are already running
  if vagrant status | grep -q "running"; then
    echo "[i] Some VMs are already running. Destroying them first..."
    vagrant destroy -f
  fi
  
  echo "Starting deployment of 3-node Kubernetes cluster..."
  vagrant up
  
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to deploy virtual machines."
    echo "Check Vagrant and VirtualBox logs for more details."
    exit 1
  fi
  
  echo "[✓] Virtual machines successfully deployed."
}

# Set up the master node
setup_master() {
  print_section "Setting Up Kubernetes Master Node"
  
  echo "Setting up master node (192.168.0.175)..."
  vagrant ssh master -c "sudo bash /home/vagrant/k8s-master-setup.sh"
  
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to set up master node."
    exit 1
  fi
  
  echo "[✓] Master node setup complete."
  echo "Retrieving join command for worker nodes..."
  JOIN_COMMAND=$(vagrant ssh master -c "sudo kubeadm token create --print-join-command" | tr -d '\r')
  
  echo "[✓] Retrieved join command: $JOIN_COMMAND"
}

# Set up the worker nodes
setup_workers() {
  print_section "Setting Up Kubernetes Worker Nodes"
  
  # Setup worker1
  echo "Setting up worker1 node (192.168.0.176)..."
  vagrant ssh worker1 -c "sudo bash /home/vagrant/k8s-worker-setup.sh << EOF
yes
$JOIN_COMMAND
192.168.0.175
vagrant
EOF"
  
  if [ $? -ne 0 ]; then
    echo "[WARN] Worker1 setup may have had issues. Check manually."
  else
    echo "[✓] Worker1 node joined the cluster."
  fi
  
  # Fix worker1 kubelet if needed
  echo "Applying kubelet fix to worker1 node if needed..."
  vagrant ssh worker1 -c "sudo bash /home/vagrant/k8s-fix-worker-kubelet.sh << EOF
$JOIN_COMMAND
EOF"
  
  # Setup worker2
  echo "Setting up worker2 node (192.168.0.177)..."
  vagrant ssh worker2 -c "sudo bash /home/vagrant/k8s-worker-setup.sh << EOF
yes
$JOIN_COMMAND
192.168.0.175
vagrant
EOF"
  
  if [ $? -ne 0 ]; then
    echo "[WARN] Worker2 setup may have had issues. Check manually."
  else
    echo "[✓] Worker2 node joined the cluster."
  fi
  
  # Fix worker2 kubelet if needed
  echo "Applying kubelet fix to worker2 node if needed..."
  vagrant ssh worker2 -c "sudo bash /home/vagrant/k8s-fix-worker-kubelet.sh << EOF
$JOIN_COMMAND
EOF"
}

# Verify cluster status
verify_cluster() {
  print_section "Verifying Cluster Status"
  
  echo "Waiting for all nodes to be ready (this may take a few minutes)..."
  sleep 60  # Give some time for nodes to register and become ready
  
  echo "Checking node status:"
  vagrant ssh master -c "kubectl get nodes"
  
  echo "Checking pod status:"
  vagrant ssh master -c "kubectl get pods --all-namespaces"
  
  echo -e "\n[✓] Cluster verification complete."
}

# Main execution
main() {
  print_section "Kubernetes 3-Node Cluster Deployment"
  
  check_prerequisites
  deploy_vms
  setup_master
  setup_workers
  verify_cluster
  
  print_section "Deployment Complete"
  
  # Show final results with color
  echo -e "\e[32m✓ Your 3-node Kubernetes cluster is now set up and ready to use!\e[0m"
  echo ""
  echo -e "Master Node: \e[1m192.168.0.175\e[0m"
  echo -e "Worker Node 1: \e[1m192.168.0.176\e[0m"
  echo -e "Worker Node 2: \e[1m192.168.0.177\e[0m"
  echo ""
  echo "To access the cluster:"
  echo -e "  \e[1mvagrant ssh master\e[0m"
  echo -e "  \e[1mkubectl get nodes\e[0m"
  echo ""
  echo "To monitor the cluster:"
  echo -e "  \e[1m./monitor-cluster.sh\e[0m"
  echo ""
  echo "To destroy the cluster:"
  echo -e "  \e[1m./destroy-cluster.sh\e[0m"
  
  # Display total time taken for deployment
  show_time_elapsed
}

# Execute main function
main "$@"
