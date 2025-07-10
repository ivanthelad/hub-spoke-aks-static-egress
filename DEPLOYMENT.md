# Deployment Guide - deployoss.sh Script

This document explains the functionality and deployment process of the `deployoss.sh` script, which automates the creation of the hub-and-spoke AKS static egress infrastructure.

## 🎯 Script Overview

The `deployoss.sh` script is the main deployment automation that creates a complete hub-and-spoke network architecture with Azure Firewall and AKS static egress capabilities. It deploys approximately 20+ Azure resources in the correct order with proper dependencies.

## 🏗️ What Gets Deployed

### Resource Groups
- **Hub Resource Group**: Contains Azure Firewall and hub networking components
- **Spoke1 Resource Group**: Contains AKS cluster and spoke1 networking
- **Spoke2 Resource Group**: Contains test ACI container and spoke2 networking

### Networking Infrastructure
- **Hub VNet** (10.0.0.0/16)
  - AzureFirewallSubnet (10.0.2.0/24)
  - Azure Firewall with static public IP
- **Spoke1 VNet** (172.16.0.0/16 + 10.1.0.0/24)
  - app-subnet (172.16.1.0/24) - Regular AKS nodes
  - egress-subnet (10.1.0.0/26) - Static egress AKS nodes
- **Spoke2 VNet** (10.2.0.0/16)
  - aci-subnet-spoke2 (10.2.1.0/24) - Test ACI container

### Azure Kubernetes Service
- **AKS Cluster** with dual node pools:
  - **App Node Pool**: Nodes on app-subnet for regular workloads
  - **Egress Node Pool**: Nodes on egress-subnet for static egress workloads
- **Static Egress Gateway**: Configuration for routing annotated pods through firewall

### Test Infrastructure
- **Azure Container Instance**: Test container in spoke2 for connectivity validation
- **Network Security Groups**: Proper security rules for spoke-to-spoke communication
- **Route Tables**: Custom routing to force traffic through Azure Firewall

## 🔄 Deployment Flow

### Phase 1: Network Foundation
1. Create resource groups
2. Deploy hub VNet with Azure Firewall subnet
3. Deploy spoke VNets with appropriate subnets
4. Establish VNet peering between hub and spokes

### Phase 2: Security & Routing
1. Deploy Azure Firewall with static public IP
2. Create network security groups with required rules
3. Configure route tables for spoke-to-hub routing
4. Associate route tables with spoke subnets

### Phase 3: AKS Deployment
1. Create AKS cluster with dual node pools
2. Configure node pools on different subnets
3. Install static egress gateway operator
4. Apply static gateway configuration

### Phase 4: Test Infrastructure
1. Deploy test ACI container in spoke2
2. Configure firewall rules for spoke-to-spoke communication
3. Validate network connectivity

## 🔧 Key Configuration Elements

### Static Egress Configuration
```yaml
apiVersion: egressGateway.kubernetes.azure.com/v1alpha1
kind: StaticGatewayConfiguration
metadata:
  name: egresgw5
spec:
  defaultRoute: staticEgressGateway
  gatewayVmssProfile: 
    vmssResourceGroup: MC_spoke1-rg_aks-spoke1_eastus
    vmssName: aks-egresspool-12345678-vmss
  provisionPublicIps: false
```

### Node Pool Configuration
- **App Pool**: 
  - Subnet: app-subnet (172.16.1.0/24)
  - Purpose: Regular workloads with direct internet access
- **Egress Pool**:
  - Subnet: egress-subnet (10.1.0.0/26)
  - Purpose: Workloads requiring static egress IPs

### Firewall Rules
- **Network Rules**: Allow spoke-to-spoke communication
- **Application Rules**: Control outbound internet access
- **NAT Rules**: If needed for inbound traffic

## 📋 Prerequisites

### Azure CLI Setup
```bash
# Login to Azure
az login

# Set subscription (if multiple subscriptions)
az account set --subscription "your-subscription-id"

# Register required providers
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.ContainerInstance
```

### Required Permissions
- Contributor access to the subscription or resource groups
- Ability to create service principals (for AKS)
- Network Contributor permissions for subnet assignments

## 🚀 Running the Deployment

### Basic Execution
```bash
# Make script executable
chmod +x deployoss.sh

# Run deployment
./deployoss.sh
```

### Environment Variables (Optional)
```bash
# Customize deployment
export LOCATION="eastus"
export HUB_RG="hub-rg"
export SPOKE1_RG="spoke1-rg"
export SPOKE2_RG="spoke2-rg"

./deployoss.sh
```

## 📊 Deployment Timeline

| Phase | Duration | Components |
|-------|----------|------------|
| Network Foundation | 5-10 min | VNets, subnets, peering |
| Security & Routing | 10-15 min | Firewall, NSGs, route tables |
| AKS Deployment | 15-20 min | AKS cluster, node pools |
| Test Infrastructure | 5 min | ACI container, final config |
| **Total** | **35-50 min** | Complete infrastructure |

## 🔍 Verification Steps

### Post-Deployment Checks
```bash
# Verify AKS cluster
kubectl get nodes -o wide

# Check node pools
az aks nodepool list --cluster-name aks-spoke1 --resource-group spoke1-rg

# Verify static gateway configuration
kubectl get staticgatewayconfigurations

# Test connectivity
./test-connectivity.sh
```

### Expected Outcomes
- ✅ AKS cluster with 2 node pools on different subnets
- ✅ Azure Firewall with static public IP
- ✅ Spoke-to-spoke connectivity through firewall
- ✅ Static egress functionality for annotated pods

## 🛠️ Troubleshooting

### Common Issues
1. **Insufficient Permissions**: Ensure contributor access to subscription
2. **Resource Naming Conflicts**: Check for existing resources with same names
3. **Quota Limits**: Verify Azure subscription limits for cores/IPs
4. **Provider Registration**: Ensure required providers are registered

### Debug Commands
```bash
# Check deployment status
az deployment group list --resource-group hub-rg

# Verify firewall status
az network firewall show --name fw-hub1 --resource-group hub-rg

# Check AKS status
az aks show --name aks-spoke1 --resource-group spoke1-rg
```

## 🧹 Cleanup

### Remove All Resources
```bash
# Delete resource groups (removes all resources)
az group delete --name hub-rg --yes --no-wait
az group delete --name spoke1-rg --yes --no-wait
az group delete --name spoke2-rg --yes --no-wait
```

### Selective Cleanup
```bash
# Delete only AKS cluster
az aks delete --name aks-spoke1 --resource-group spoke1-rg

# Delete only firewall
az network firewall delete --name fw-hub1 --resource-group hub-rg
```

---

This deployment script creates a production-ready demonstration of AKS static egress capabilities using Azure's native networking and security features.
