#!/bin/bash
# Kubernetes Demo Application Deployment Script
# This script deploys sample applications to the Kubernetes cluster
# Run with: bash deploy-demo-apps.sh [app]
# Where [app] can be: nginx, guestbook, dashboard, all

set -e

# Print section headers
print_section() {
  echo "==================================================================="
  echo "  $1"
  echo "==================================================================="
}

# Check if cluster is running
check_cluster() {
  print_section "Checking Cluster Status"
  
  echo "Verifying cluster is running..."
  if ! vagrant status master | grep -q "running"; then
    echo "[ERROR] Master node is not running."
    echo "Please deploy the cluster first with ./deploy-cluster.sh"
    exit 1
  fi
  
  echo "[✓] Cluster appears to be running. Checking node status..."
  
  # Check if all nodes are ready
  local READY_NODES=$(vagrant ssh master -c "kubectl get nodes | grep Ready | wc -l" 2>/dev/null | tr -d '\r')
  if [ "$READY_NODES" -lt 3 ]; then
    echo "[WARN] Not all nodes are in Ready state (found $READY_NODES ready nodes)."
    echo "Some applications may not deploy properly."
    read -p "Do you want to continue anyway? (yes/no): " CONTINUE
    if [[ "$CONTINUE" != "yes" ]]; then
      echo "Deployment cancelled."
      exit 0
    fi
  else
    echo "[✓] All nodes are in Ready state."
  fi
}

# Deploy Nginx application
deploy_nginx() {
  print_section "Deploying Nginx Demo"
  
  echo "Creating Nginx deployment with 3 replicas..."
  vagrant ssh master -c "cat > nginx-demo.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
  labels:
    app: nginx-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:1.19
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
  selector:
    app: nginx-demo
EOF"

  vagrant ssh master -c "kubectl apply -f nginx-demo.yaml"
  
  echo "[✓] Nginx demo deployed successfully!"
  echo "Access Nginx at: http://192.168.0.175:30080"
}

# Deploy Guestbook application
deploy_guestbook() {
  print_section "Deploying Guestbook Demo"
  
  echo "Creating Redis master deployment..."
  vagrant ssh master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/redis-master-deployment.yaml"
  
  echo "Creating Redis master service..."
  vagrant ssh master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/redis-master-service.yaml"
  
  echo "Creating Redis slave deployment..."
  vagrant ssh master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/redis-slave-deployment.yaml"
  
  echo "Creating Redis slave service..."
  vagrant ssh master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/redis-slave-service.yaml"
  
  echo "Creating frontend deployment..."
  vagrant ssh master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/examples/master/guestbook/frontend-deployment.yaml"
  
  # Create a modified frontend service with NodePort
  vagrant ssh master -c "cat > frontend-service-nodeport.yaml << EOF
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: guestbook
    tier: frontend
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30081
  selector:
    app: guestbook
    tier: frontend
EOF"

  vagrant ssh master -c "kubectl apply -f frontend-service-nodeport.yaml"
  
  echo "[✓] Guestbook demo deployed successfully!"
  echo "Access Guestbook at: http://192.168.0.175:30081"
}

# Deploy Kubernetes Dashboard
deploy_dashboard() {
  print_section "Deploying Kubernetes Dashboard"
  
  echo "Deploying Kubernetes Dashboard..."
  vagrant ssh master -c "kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml"
  
  # Create admin user and role binding
  vagrant ssh master -c "cat > dashboard-adminuser.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF"

  vagrant ssh master -c "kubectl apply -f dashboard-adminuser.yaml"
  
  # Generate token for accessing the dashboard
  echo "Generating dashboard access token..."
  vagrant ssh master -c "kubectl -n kubernetes-dashboard create token admin-user > dashboard-token.txt"
  
  echo "[✓] Kubernetes Dashboard deployed successfully!"
  echo "To access the dashboard:"
  echo "1. Run: kubectl proxy (on master node)"
  echo "2. Access: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/"
  echo "3. Use the token from dashboard-token.txt to login"
  echo ""
  echo "For remote access, you can set up kubectl port-forward:"
  echo "vagrant ssh master -c \"kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 10443:443 --address 0.0.0.0\""
  echo "Then access: https://192.168.0.175:10443"
}

# Show available demos
show_demos() {
  print_section "Available Demo Applications"
  
  echo "Usage: $0 [option]"
  echo ""
  echo "Options:"
  echo "  nginx      - Deploy Nginx web server (accessible on port 30080)"
  echo "  guestbook  - Deploy Guestbook application (accessible on port 30081)"
  echo "  dashboard  - Deploy Kubernetes Dashboard"
  echo "  all        - Deploy all demo applications"
  echo ""
  echo "Example: $0 nginx"
}

# Main execution
main() {
  local OPTION=${1:-help}
  
  case "$OPTION" in
    nginx)
      check_cluster
      deploy_nginx
      ;;
    guestbook)
      check_cluster
      deploy_guestbook
      ;;
    dashboard)
      check_cluster
      deploy_dashboard
      ;;
    all)
      check_cluster
      deploy_nginx
      deploy_guestbook
      deploy_dashboard
      ;;
    help|*)
      show_demos
      ;;
  esac
}

# Execute main function
main "$@"
