# Kubernetes Setup and Troubleshooting Scripts

This repository contains a collection of bash scripts for setting up and troubleshooting Kubernetes clusters on Ubuntu 20.04 LTS. The scripts are designed to automate common tasks and resolve frequent issues encountered when working with Kubernetes.

## 📋 Table of Contents

- [Scripts Overview](#scripts-overview)
- [Setup Scripts](#setup-scripts)
- [Troubleshooting Scripts](#troubleshooting-scripts)
- [Prerequisites](#prerequisites)
- [Usage Instructions](#usage-instructions)
- [Common Issues and Solutions](#common-issues-and-solutions)
- [Network Configuration](#network-configuration)
- [Security Considerations](#security-considerations)

## 🛠️ Scripts Overview

### Setup Scripts
- **`k8s-master-setup.sh`** - Complete master node setup and initialization
- **`k8s-worker-setup.sh`** - Complete worker node setup and cluster joining

### Troubleshooting Scripts
- **`k8s-fix-master.sh`** - Fix master node issues (API server, etcd, kubelet)
- **`k8s-fix-worker-kubelet.sh`** - Fix worker node issues (kubelet, kubectl configuration)

## 🚀 Setup Scripts

### k8s-master-setup.sh

**Purpose**: Complete automated setup of a Kubernetes master node

**What it does**:
1. Cleans up any previous Kubernetes installation
2. Configures system prerequisites (swap, kernel modules, sysctl)
3. Installs and configures containerd container runtime
4. Installs Kubernetes components (kubelet, kubeadm, kubectl)
5. Initializes the Kubernetes control plane
6. Installs Calico CNI network plugin
7. Configures kubectl for the current user
8. Generates join commands for worker nodes
9. Creates helper scripts for worker node management

**Usage**:
```bash
sudo bash k8s-master-setup.sh
```

**Features**:
- Handles held packages automatically
- Creates kubectl shortcuts and aliases
- Generates worker join commands
- Creates scripts for copying kubeconfig to worker nodes
- Comprehensive error handling

### k8s-worker-setup.sh

**Purpose**: Complete automated setup of a Kubernetes worker node

**What it does**:
1. Cleans up any previous Kubernetes installation
2. Configures system prerequisites (swap, kernel modules, sysctl)
3. Installs and configures containerd container runtime
4. Installs Kubernetes components (kubelet, kubeadm, kubectl)
5. Joins the worker node to the cluster
6. Configures kubectl access to the master node
7. Sets up kubectl shortcuts and aliases

**Usage**:
```bash
sudo bash k8s-worker-setup.sh
```

**Features**:
- Interactive cluster joining process
- Automatic and manual kubectl configuration options
- Handles held packages automatically
- Multiple methods for kubeconfig setup (SCP, manual paste)

## 🔧 Troubleshooting Scripts

### k8s-fix-master.sh

**Purpose**: Fix common master node issues and restore cluster functionality

**When to use**:
- API server won't start (connection refused errors)
- etcd data corruption
- kubelet problems on master node
- kubectl access issues on master
- Need to reset and reinitialize the cluster

**What it does**:
1. Diagnoses current cluster issues
2. Stops problematic services
3. Cleans up corrupted data (etcd, kubelet)
4. Resets network interfaces and iptables
5. Reinitializes the cluster (optional)
6. Reinstalls CNI network plugin
7. Generates new join commands for worker nodes

**Usage**:
```bash
sudo bash k8s-fix-master.sh
```

**Features**:
- Interactive diagnostic process
- Option to reset cluster data or just restart services
- Automatic cluster reinitialization
- New join command generation

### k8s-fix-worker-kubelet.sh

**Purpose**: Fix worker node issues and configure kubectl access

**When to use**:
- Worker node can't join cluster
- kubelet issues on worker nodes
- kubectl access issues on worker nodes
- Need to reset worker node configuration
- "Port 10250 is in use" errors
- "FileAvailable" preflight errors

**What it does**:
1. Resets kubeadm configuration
2. Cleans up network interfaces
3. Creates proper kubelet configuration
4. Joins the node to the cluster
5. Configures kubectl access
6. Sets up kubeconfig for both regular user and root

**Usage**:
```bash
sudo bash k8s-fix-worker-kubelet.sh
```

**Features**:
- Complete kubelet configuration reset
- Interactive join command input
- Automatic kubectl configuration via SCP
- Fallback manual configuration instructions

## 📋 Prerequisites

### System Requirements
- Ubuntu 20.04 LTS
- Minimum 2 CPU cores
- Minimum 2GB RAM
- Network connectivity between nodes
- Sudo privileges

### Network Requirements
- Master node: Port 6443 (API server)
- Worker nodes: Port 10250 (kubelet)
- All nodes: Ports 30000-32767 (NodePort services)

### Before Running Scripts
1. Ensure all nodes have static IP addresses
2. Configure hostname resolution between nodes
3. Set up SSH key-based authentication (recommended)
4. Ensure internet connectivity for package downloads

## 📖 Usage Instructions

### Initial Cluster Setup

1. **Set up the master node**:
   ```bash
   # On the master node
   sudo bash k8s-master-setup.sh
   ```

2. **Note the join command** displayed at the end of master setup

3. **Set up worker nodes**:
   ```bash
   # On each worker node
   sudo bash k8s-worker-setup.sh
   ```

4. **Verify cluster status**:
   ```bash
   # On the master node
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

### Troubleshooting Workflow

#### Master Node Issues
```bash
# If API server won't start or etcd is corrupted
sudo bash k8s-fix-master.sh
```

#### Worker Node Issues
```bash
# If worker can't join or kubelet has issues
sudo bash k8s-fix-worker-kubelet.sh
```

## 🔍 Common Issues and Solutions

### Master Node Issues

**Issue**: API server connection refused
```
The connection to the server 192.168.0.175:6443 was refused
```
**Solution**: Run `k8s-fix-master.sh` to reset etcd and restart services

**Issue**: etcd data corruption
```
panic: failed to recover v3 backend from snapshot
```
**Solution**: Run `k8s-fix-master.sh` and choose to reset cluster data

### Worker Node Issues

**Issue**: Join command fails with preflight errors
```
[ERROR FileAvailable--etc-kubernetes-kubelet.conf]: /etc/kubernetes/kubelet.conf already exists
```
**Solution**: Run `k8s-fix-worker-kubelet.sh` to clean up and rejoin

**Issue**: kubectl connection refused on worker
```
The connection to the server localhost:8080 was refused
```
**Solution**: Run `k8s-fix-worker-kubelet.sh` to configure kubectl properly

### Package Issues

**Issue**: Held packages error
```
E: Held packages were changed and -y was used without --allow-change-held-packages
```
**Solution**: All scripts now handle this automatically with proper flags

## 🌐 Network Configuration

### Default Network Settings
- **Pod Network CIDR**: 10.88.0.0/16
- **Service Network CIDR**: 10.96.0.0/12
- **CNI Plugin**: Calico v3.29.3

### Firewall Ports
Ensure these ports are open:

**Master Node**:
- 6443/tcp (Kubernetes API server)
- 2379-2380/tcp (etcd server client API)
- 10250/tcp (kubelet API)
- 10259/tcp (kube-scheduler)
- 10257/tcp (kube-controller-manager)

**Worker Nodes**:
- 10250/tcp (kubelet API)
- 30000-32767/tcp (NodePort Services)

## 🔒 Security Considerations

### Best Practices
1. **Use SSH keys** instead of passwords for inter-node communication
2. **Limit kubectl access** - Don't configure kubectl on all worker nodes
3. **Regular updates** - Keep Kubernetes components updated
4. **Network policies** - Implement proper network segmentation
5. **RBAC** - Use Role-Based Access Control for cluster access

### Production Recommendations
- Use dedicated service accounts instead of admin.conf
- Implement proper backup strategies for etcd
- Use external load balancers for API server high availability
- Regular security audits and vulnerability scanning

## 🛡️ Backup and Recovery

### Important Files to Backup
- `/etc/kubernetes/admin.conf` - Cluster admin credentials
- `/etc/kubernetes/pki/` - Kubernetes certificates
- etcd data (handled by cluster backup strategies)

### Recovery Process
1. Use `k8s-fix-master.sh` for master node recovery
2. Use `k8s-fix-worker-kubelet.sh` for worker node recovery
3. Re-run setup scripts for complete cluster reconstruction

## 📝 Script Features

### Error Handling
- All scripts use `set -e` for immediate error exit
- Comprehensive error checking and reporting
- Fallback options for failed operations

### User Experience
- Interactive prompts for user input
- Clear progress indicators
- Detailed success/failure messages
- Comprehensive help text

### Automation
- Automatic package management
- Service management and restart
- Network configuration cleanup
- Certificate and key management

## 🤝 Contributing

Feel free to submit issues and enhancement requests. When contributing:

1. Test scripts on clean Ubuntu 20.04 installations
2. Follow existing code style and commenting
3. Add appropriate error handling
4. Update documentation for new features

## 📞 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review script output for error messages
3. Verify system requirements are met
4. Check network connectivity between nodes

---

**Note**: These scripts are designed for learning and development environments. For production use, additional security hardening and customization may be required.
