# Automated Kubernetes 3-Node Cluster Setup

This folder contains scripts to automatically deploy a 3-node Kubernetes cluster using Vagrant and VirtualBox.

## Prerequisites

Before you begin, ensure you have the following software installed:

- VirtualBox: https://www.virtualbox.org/wiki/Downloads
- Vagrant: https://www.vagrantup.com/downloads
- Git Bash (if on Windows): https://git-scm.com/downloads

## Network Configuration

The cluster will be set up with the following IP addresses:

- Master Node: 192.168.0.175
- Worker Node 1: 192.168.0.176
- Worker Node 2: 192.168.0.177

## Quick Start

To deploy the cluster:

1. Open a terminal (Git Bash on Windows)
2. Navigate to this directory
3. Run: `./deploy-cluster.sh`

To destroy the cluster:

1. Run: `./destroy-cluster.sh`

## Directory Structure

- `Vagrantfile`: Defines the 3 virtual machines for the cluster
- `deploy-cluster.sh`: Script to deploy the entire cluster
- `destroy-cluster.sh`: Script to destroy the cluster
- `setup-ssh-keys.sh`: Script to generate SSH keys
- `monitor-cluster.sh`: Script to monitor cluster health and resource usage
- `deploy-demo-apps.sh`: Script to deploy sample applications to the cluster
- `backup-restore.sh`: Script to backup and restore cluster resources
- `calico.yaml`: Calico CNI plugin configuration
- `scripts/`: Directory containing individual node setup scripts
  - `k8s-master-setup.sh`: Master node setup script
  - `k8s-worker-setup.sh`: Worker node setup script
  - `k8s-fix-worker-kubelet.sh`: Script to fix kubelet issues on worker nodes

## Detailed Usage Instructions

### Step 1: Generate SSH Keys (Optional)

```bash
./setup-ssh-keys.sh
```

This generates SSH keys that allow the master node to communicate with worker nodes.

### Step 2: Deploy the Cluster

```bash
./deploy-cluster.sh
```

This will:
1. Create three Ubuntu 20.04 VMs
2. Configure the master node
3. Join worker nodes to the cluster
4. Apply network plugin (Calico)
5. Verify cluster status

The deployment takes approximately 5-10 minutes.

### Step 3: Access the Cluster

After deployment, you can access the master node:

```bash
vagrant ssh master
kubectl get nodes
```

### Step 4: Monitor the Cluster

```bash
./monitor-cluster.sh
```

This will show a menu with options to monitor node status, pod status, resource usage, and more.

### Step 5: Deploy Demo Applications

```bash
./deploy-demo-apps.sh nginx     # Deploy a simple Nginx web server
./deploy-demo-apps.sh guestbook # Deploy the Kubernetes Guestbook example
./deploy-demo-apps.sh dashboard # Deploy the Kubernetes Dashboard
./deploy-demo-apps.sh all       # Deploy all demo applications
```

### Step 6: Backup and Restore Cluster Resources

```bash
./backup-restore.sh backup [name]    # Create a backup of cluster resources
./backup-restore.sh restore <name>   # Restore cluster resources from backup
./backup-restore.sh list            # List available backups
```

### Step 7: Destroy the Cluster (When Done)

```bash
./destroy-cluster.sh
```

## Troubleshooting

### Worker Nodes in "NotReady" State

If worker nodes show "NotReady" status:

```bash
vagrant ssh worker1
sudo bash /home/vagrant/k8s-fix-worker-kubelet.sh
```

### Networking Issues

If pods can't communicate:

```bash
vagrant ssh master
kubectl delete -f /home/vagrant/calico.yaml
kubectl apply -f /home/vagrant/calico.yaml
```

### Other Issues

Check the logs:

```bash
vagrant ssh master
sudo journalctl -u kubelet
```

## Customization

Edit the Vagrantfile to change:
- Number of CPUs and RAM per node
- IP addresses
- VM names
- Ubuntu version

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

These scripts are created for educational purposes as part of a Kubernetes learning journey.
