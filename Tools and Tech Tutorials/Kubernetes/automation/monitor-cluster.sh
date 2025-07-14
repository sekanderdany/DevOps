#!/bin/bash
# Kubernetes Cluster Monitoring Script
# This script provides monitoring capabilities for the 3-node Kubernetes cluster
# Run with: bash monitor-cluster.sh

set -e

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Check if user is connected to any VM
check_connection() {
  if ! vagrant status | grep -q "running"; then
    echo "[ERROR] No VMs are currently running."
    echo "Please deploy the cluster first with ./deploy-cluster.sh"
    exit 1
  fi
}

# Display cluster node status
show_nodes() {
  print_section "Cluster Nodes Status"
  
  echo "Retrieving node status..."
  vagrant ssh master -c "kubectl get nodes -o wide" || {
    echo "[ERROR] Failed to retrieve node status."
    echo "Make sure the master node is running and properly set up."
    exit 1
  }
}

# Display pod status across all namespaces
show_pods() {
  print_section "Pods Status"
  
  echo "Retrieving pods from all namespaces..."
  vagrant ssh master -c "kubectl get pods --all-namespaces -o wide" || {
    echo "[ERROR] Failed to retrieve pod status."
    return 1
  }
}

# Display system resource usage
show_resources() {
  print_section "Node Resource Usage"
  
  echo "Master Node (192.168.0.175):"
  vagrant ssh master -c "top -n 1 -b | head -n 12" || echo "[ERROR] Failed to get master resources."
  
  echo -e "\nWorker Node 1 (192.168.0.176):"
  vagrant ssh worker1 -c "top -n 1 -b | head -n 12" || echo "[ERROR] Failed to get worker1 resources."
  
  echo -e "\nWorker Node 2 (192.168.0.177):"
  vagrant ssh worker2 -c "top -n 1 -b | head -n 12" || echo "[ERROR] Failed to get worker2 resources."
}

# Show cluster services
show_services() {
  print_section "Cluster Services"
  
  echo "Retrieving services from all namespaces..."
  vagrant ssh master -c "kubectl get services --all-namespaces" || {
    echo "[ERROR] Failed to retrieve services."
    return 1
  }
}

# Check network connectivity between nodes
check_network() {
  print_section "Network Connectivity Check"
  
  echo "Testing connectivity from master to worker nodes..."
  vagrant ssh master -c "ping -c 2 192.168.0.176 && ping -c 2 192.168.0.177" || {
    echo "[ERROR] Network connectivity issues detected from master node."
  }
  
  echo -e "\nTesting DNS resolution within the cluster..."
  vagrant ssh master -c "kubectl run -i --rm --restart=Never dns-test --image=busybox:1.28 -- nslookup kubernetes.default" || {
    echo "[ERROR] DNS resolution issues detected."
  }
}

# View kubelet logs
show_kubelet_logs() {
  print_section "Kubelet Logs"
  
  local node=$1
  echo "${node^} Node Kubelet Logs (last 20 lines):"
  vagrant ssh $node -c "sudo journalctl -u kubelet --no-pager -n 20" || {
    echo "[ERROR] Failed to retrieve kubelet logs from $node node."
    return 1
  }
}

# Live monitoring mode (updates every 5 seconds)
live_monitor() {
  print_section "Live Monitoring Mode (Ctrl+C to exit)"
  
  trap "echo -e '\nExiting live monitoring mode...'; exit 0" INT
  
  while true; do
    clear
    echo "Kubernetes Cluster Live Monitoring - $(date)"
    echo "Press Ctrl+C to exit"
    echo ""
    
    vagrant ssh master -c "kubectl get nodes -o wide"
    echo ""
    vagrant ssh master -c "kubectl get pods --all-namespaces | head -n 15"
    
    sleep 5
  done
}

# Display menu
show_menu() {
  print_section "Kubernetes Cluster Monitoring"
  
  echo "Select a monitoring option:"
  echo "1. Show cluster node status"
  echo "2. Show pod status"
  echo "3. Show node resource usage"
  echo "4. Show cluster services"
  echo "5. Check network connectivity"
  echo "6. View master kubelet logs"
  echo "7. View worker1 kubelet logs"
  echo "8. View worker2 kubelet logs" 
  echo "9. Live monitoring mode"
  echo "0. Exit"
  
  read -p "Enter your choice: " choice
  
  case "$choice" in
    1) show_nodes ;;
    2) show_pods ;;
    3) show_resources ;;
    4) show_services ;;
    5) check_network ;;
    6) show_kubelet_logs "master" ;;
    7) show_kubelet_logs "worker1" ;;
    8) show_kubelet_logs "worker2" ;;
    9) live_monitor ;;
    0) exit 0 ;;
    *) echo "Invalid option. Please try again." ;;
  esac
  
  echo ""
  read -p "Press Enter to return to menu..."
  show_menu
}

# Main execution
main() {
  check_connection
  show_menu
}

# Execute main function
main "$@"
