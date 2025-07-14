#!/bin/bash
# Kubernetes Cluster Backup and Restore Script
# This script performs backup and restore operations for the Kubernetes cluster
# Run with: bash backup-restore.sh backup|restore [backup_name]

set -e

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Variables
BACKUP_DIR="./backups"
mkdir -p $BACKUP_DIR

# Check if cluster is running
check_cluster() {
  if ! vagrant status master | grep -q "running"; then
    echo "[ERROR] Master node is not running."
    echo "Please deploy the cluster first with ./deploy-cluster.sh"
    exit 1
  fi
}

# Backup the cluster state
backup_cluster() {
  print_section "Backing up Kubernetes Cluster"
  
  local backup_name=${1:-"backup-$(date +%Y%m%d-%H%M%S)"}
  local backup_path="${BACKUP_DIR}/${backup_name}"
  mkdir -p "${backup_path}"
  
  echo "Creating backup in: ${backup_path}"
  
  # Backup all resource definitions
  echo "Backing up cluster resources..."
  for resource in namespaces deployments statefulsets daemonsets replicasets services configmaps secrets persistentvolumes persistentvolumeclaims roles rolebindings clusterroles clusterrolebindings serviceaccounts ingresses; do
    echo "  - Backing up $resource"
    vagrant ssh master -c "kubectl get $resource --all-namespaces -o yaml > /tmp/$resource.yaml" && \
    vagrant scp master:/tmp/$resource.yaml "${backup_path}/$resource.yaml"
  done
  
  # Backup etcd data (requires additional setup normally)
  echo "Note: For a complete backup, etcd data should also be backed up."
  echo "This script does not include etcd backup as it would require special privileges."
  
  echo "[✓] Backup completed successfully to: ${backup_path}"
  echo "Total resources backed up: $(ls -1 ${backup_path} | wc -l)"
}

# Restore the cluster state
restore_cluster() {
  print_section "Restoring Kubernetes Cluster"
  
  local backup_name=$1
  local backup_path="${BACKUP_DIR}/${backup_name}"
  
  if [ -z "$backup_name" ]; then
    echo "[ERROR] Backup name is required."
    echo "Available backups:"
    ls -1 $BACKUP_DIR
    echo "Usage: $0 restore <backup_name>"
    exit 1
  fi
  
  if [ ! -d "$backup_path" ]; then
    echo "[ERROR] Backup not found: $backup_path"
    echo "Available backups:"
    ls -1 $BACKUP_DIR
    exit 1
  fi
  
  echo "Restoring from backup: $backup_path"
  
  # Copy backup files to master node
  vagrant ssh master -c "mkdir -p /tmp/k8s-restore"
  for file in $backup_path/*.yaml; do
    resource=$(basename $file .yaml)
    echo "  - Restoring $resource"
    vagrant scp $file master:/tmp/k8s-restore/
    vagrant ssh master -c "kubectl apply -f /tmp/k8s-restore/$(basename $file)" || echo "  [WARN] Some resources in $resource could not be applied."
  done
  
  # Clean up temporary files
  vagrant ssh master -c "rm -rf /tmp/k8s-restore"
  
  echo "[✓] Restore completed."
  echo "Note: Some resources may not have been restored if they depend on resources that don't exist anymore."
}

# List available backups
list_backups() {
  print_section "Available Backups"
  
  if [ ! "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
    echo "No backups available."
    exit 0
  fi
  
  echo "Available backups:"
  for backup in $(ls -1d $BACKUP_DIR/*); do
    backup_name=$(basename $backup)
    backup_date=$(stat -c "%y" "$backup" 2>/dev/null || stat -f "%Sm" "$backup" 2>/dev/null)
    backup_size=$(du -sh "$backup" | cut -f1)
    echo "  - $backup_name ($backup_size, created on $backup_date)"
  done
}

# Display usage
show_usage() {
  print_section "Kubernetes Backup and Restore"
  
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  backup [name]     - Backup the cluster state (optional name)"
  echo "  restore <name>    - Restore the cluster from a backup"
  echo "  list              - List available backups"
  echo ""
  echo "Examples:"
  echo "  $0 backup my-backup      # Create a backup named 'my-backup'"
  echo "  $0 backup               # Create a backup with timestamp"
  echo "  $0 restore my-backup    # Restore from backup named 'my-backup'"
  echo "  $0 list                 # List all available backups"
}

# Main execution
main() {
  local COMMAND=${1:-"usage"}
  local BACKUP_NAME=$2
  
  case "$COMMAND" in
    backup)
      check_cluster
      backup_cluster "$BACKUP_NAME"
      ;;
    restore)
      check_cluster
      restore_cluster "$BACKUP_NAME"
      ;;
    list)
      list_backups
      ;;
    *)
      show_usage
      ;;
  esac
}

# Execute main function
main "$@"
