#!/bin/bash
# Kubernetes 3-Node Cluster Destruction Script
# This script automates the destruction of the 3-node Kubernetes cluster created with deploy-cluster.sh
# Run with: bash destroy-cluster.sh

set -e

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Confirm destruction
confirm_destroy() {
  print_section "Confirmation"
  
  echo "WARNING: This will destroy all VMs and data in your Kubernetes cluster."
  echo "This action cannot be undone."
  echo ""
  read -p "Are you sure you want to continue? (yes/no): " CONFIRM
  
  if [[ "$CONFIRM" != "yes" ]]; then
    echo "Cluster destruction cancelled."
    exit 0
  fi
}

# Destroy the virtual machines
destroy_cluster() {
  print_section "Destroying Kubernetes Cluster"
  
  echo "Stopping all VMs and cleaning up resources..."
  vagrant destroy -f
  
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to destroy some VMs. You may need to manually clean up."
    echo "Try using VirtualBox Manager to remove any remaining VMs."
    exit 1
  fi
  
  echo "[✓] All virtual machines successfully destroyed."
}

# Clean up leftover files
clean_leftovers() {
  print_section "Cleaning Leftover Files"
  
  echo "Removing Vagrant temporary files..."
  rm -rf .vagrant/ 2>/dev/null || true
  
  echo "[✓] Cleanup complete."
}

# Main execution
main() {
  print_section "Kubernetes 3-Node Cluster Destruction"
  
  confirm_destroy
  destroy_cluster
  clean_leftovers
  
  print_section "Destruction Complete"
  echo "Your Kubernetes cluster has been successfully destroyed."
  echo "You can deploy a new cluster by running: ./deploy-cluster.sh"
}

# Execute main function
main "$@"
