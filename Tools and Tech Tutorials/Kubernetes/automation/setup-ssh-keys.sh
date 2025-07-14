#!/bin/bash
# Kubernetes SSH Keys Setup Script
# This script creates SSH keys for the automatic deployment of the Kubernetes cluster
# Run with: bash setup-ssh-keys.sh

set -e

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Generate SSH keys
generate_keys() {
  print_section "Generating SSH Keys"
  
  # Check if keys already exist
  if [ -f "./id_rsa" ] && [ -f "./id_rsa.pub" ]; then
    echo "SSH keys already exist in the current directory."
    read -p "Do you want to overwrite them? (yes/no): " OVERWRITE
    
    if [[ "$OVERWRITE" != "yes" ]]; then
      echo "Keeping existing keys."
      return
    fi
    
    echo "Removing existing keys..."
    rm -f ./id_rsa ./id_rsa.pub
  fi
  
  echo "Generating new SSH key pair without passphrase..."
  ssh-keygen -t rsa -b 4096 -f ./id_rsa -N ""
  
  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to generate SSH keys."
    exit 1
  fi
  
  chmod 600 ./id_rsa
  echo "[✓] SSH keys generated successfully."
  echo "  Private key: $(pwd)/id_rsa"
  echo "  Public key:  $(pwd)/id_rsa.pub"
}

# Main execution
main() {
  print_section "Kubernetes SSH Keys Setup"
  
  generate_keys
  
  print_section "Setup Complete"
  echo "SSH keys have been set up for use with the Kubernetes cluster deployment."
  echo "You can now proceed with: ./deploy-cluster.sh"
}

# Execute main function
main "$@"
