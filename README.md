# Azure AKS Static Egress Demo

This project demonstrates how to achieve **static egress IPs** for Azure Kubernetes Service (AKS) workloads using a hub-and-spoke network architecture with Azure Firewall.

## 🏗️ Architecture Overview

![Hub-and-Spoke Architecture](assets/arch.png)
*Hub-and-spoke network topology with Azure Firewall providing centralized egress control and static IP addressing for AKS workloads.*

## 🌊 Traffic Flow

![Traffic Flow Diagram](assets/flow.png)
*Traffic routing patterns showing how pods with static egress annotations flow through Azure Firewall while regular pods use direct internet access.*

## 🎯 What This Demo Shows

**Problem**: By default, AKS pods get random egress IP addresses, making it difficult to whitelist IPs with external services.

**Solution**: Use subnet-based routing to force specific pods through Azure Firewall with static public IPs.

### Key Demo Components

- **AKS with Static Egress**: Pods can be configured to use static egress IPs via Azure Firewall
- **Hub-and-Spoke Network**: Centralized firewall for egress control
- **Transitive Routing**: Spoke-to-spoke communication through the firewall
- **Test Validation**: Scripts to verify static egress functionality

## �️ Architecture

```text
┌───────────────────────────────────────────────────────────────────────────────────┐
│                             Hub-and-Spoke Architecture                            │
├───────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│ ╔═══════════════════════╗   ╔═══════════════════╗   ╔═══════════════════════╗     │
│ ║ Spoke1 VNet           ║   ║ Hub VNet          ║   ║ Spoke2 VNet           ║     │
│ ║ 10.1.0.0/16           ║   ║ 10.0.0.0/16       ║   ║ 10.2.0.0/16           ║     │
│ ║                       ║   ║                   ║   ║                       ║     │
│ ║ ┌───────────────────┐ ║   ║ ┌───────────────┐ ║   ║ ┌───────────────────┐ ║     │
│ ║ │ App Subnet        │ ║   ║ │ Azure         │ ║   ║ │ ACI Subnet        │ ║     │
│ ║ │ 172.16.1.0/24     │ ║   ║ │ Firewall      │ ║◄──╫►║ │ 10.2.1.0/24     │ ║     │
│ ║ │ (Non-routable)    │ ║   ║ │ 10.0.2.0/24   │ ║   ║ │                   │ ║     │
│ ║ └───────────────────┘ ║   ║ └───────────────┘ ║   ║ └───────────────────┘ ║     │
│ ║                       ║   ║         │         ║   ║                       ║     │
│ ║ ┌───────────────────┐ ║   ║         │         ║   ║                       ║     │
│ ║ │ Egress Subnet     │ ║   ║         │         ║   ║                       ║     │
│ ║ │ 10.1.0.0/26       │◄╫───╫─────────┘         ║   ║                       ║     │
│ ║ │ (Static Egress)   │ ║   ║                   ║   ║                       ║     │
│ ║ └───────────────────┘ ║   ║ Static Public IP  ║   ║                       ║     │
│ ║                       ║   ║ 20.240.x.x        ║   ║                       ║     │
│ ╚═══════════════════════╝   ╚═══════════════════╝   ╚═══════════════════════╝     │
│                                                                                   │
│ Legend:                                                                           │
│ ═══ VNet Boundary    ◄──► Routed Connection                                       │
│ ─── Subnet Boundary   (X) No Connection                                          │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Traffic Flow

1. **Pod with Static Egress**: Pod gets annotation → Routes to egress subnet → Azure Firewall → Static Public IP
2. **Regular Pod**: Pod without annotation → Direct internet access (dynamic IP)
3. **Spoke-to-Spoke**: Spoke1 → Hub Firewall → Spoke2 (for testing)

## 🚀 Quick Start

### Prerequisites
- Azure CLI
- kubectl
- Bash shell

### Configuration
Copy and customize the environment variables:
```bash
# Copy the example configuration
cp .env.example .env

# Edit the configuration to match your requirements
nano .env
```

Key configuration variables in `.env`:
- `PREFIX`: Resource naming prefix (default: "88")
- `LOCATION`: Azure region (default: "swedencentral")
- `NODE_COUNT`: AKS node count (default: 3)
- `PUBLIC_ACI_NAME`: Name for public ACI container for testing

### Deploy Everything
```bash
# Clone and deploy
git clone <repository-url>
cd hub-spoke-aks-static-egress
./deployoss.sh
```

### Test Static Egress
```bash
# Deploy test pods
kubectl apply -f testdeploy.yaml

# Run comprehensive connectivity test
./test-connectivity.sh
```

## 📖 Detailed Deployment Guide

For comprehensive deployment instructions and troubleshooting, see [DEPLOYMENT.md](DEPLOYMENT.md)

## 🧪 How Static Egress Works

### 1. Pod Annotation
Pods that need static egress get this annotation:
```yaml
metadata:
  annotations:
    kubernetes.azure.com/static-gateway-configuration: egresgw5
```

### 2. Subnet Routing
- **Annotated pods**: Scheduled on egress subnet (10.1.0.0/26) → Route through firewall
- **Regular pods**: Scheduled on app subnet (172.16.1.0/24) → Direct internet access

### 3. Static IP Result
- **With annotation**: Egress traffic shows firewall's static public IP
- **Without annotation**: Egress traffic shows dynamic IP from NAT gateway

## 📋 Test Scripts

### test-connectivity.sh
Comprehensive test that validates:
- **Positive Test**: Pod with static egress annotation can reach spoke2 via firewall
- **Negative Test**: Pod without annotation cannot reach spoke2 (blocked)
- **Static Egress Validation**: Tests actual egress IP using public ACI container

```bash
./test-connectivity.sh
```

### diagnose-connectivity.sh
Network diagnostics for troubleshooting:
```bash
./diagnose-connectivity.sh
```

## 🔧 Configuration

### Environment Configuration

All deployment and test scripts use a centralized `.env` file for configuration. Key settings include:

```bash
# Resource naming and location
PREFIX="88"                    # Prefix for all Azure resources
LOCATION="swedencentral"       # Azure region for deployment

# AKS cluster settings
NODE_COUNT=3                   # Number of AKS nodes
K8S_VERSION="1.31"            # Kubernetes version

# Container instances
ACI_NAME="srcip-http2"         # Private ACI in spoke2
PUBLIC_ACI_NAME="srcip-http-public"  # Public ACI for testing
```

### Key Components

**testdeploy.yaml** contains two test deployments:
- `test-static-egress`: Has static gateway annotation (should work)
- `test-negative-connectivity`: No annotation (should be blocked)

**Static Gateway Configuration**:
```yaml
apiVersion: egressGateway.kubernetes.azure.com/v1alpha1
kind: StaticGatewayConfiguration
metadata:
  name: egresgw5
spec:
  defaultRoute: staticEgressGateway
  gatewayVmssProfile: 
    vmssResourceGroup: {{VMSS_RESOURCE_GROUP}}
    vmssName: {{VMSS_NAME}}
  provisionPublicIps: false
```

## 🌐 Network Details

### VNets and Subnets
| VNet | Subnet | CIDR | Purpose |
|------|--------|------|---------|
| hub1 | AzureFirewallSubnet | 10.0.2.0/24 | Azure Firewall |
| spoke1 | egress-subnet | 10.1.0.0/26 | AKS nodes with static egress |
| spoke1 | app-subnet | 172.16.1.0/24 | AKS nodes with direct egress |
| spoke2 | aci-subnet-spoke2 | 10.2.1.0/24 | Test ACI container |

### Egress Paths
- **Static Egress**: egress-subnet → Azure Firewall → Static Public IP
- **Direct Egress**: app-subnet → NAT Gateway → Dynamic Public IP

## 📁 Project Files

```text
hub-spoke-aks-static-egress/
├── .env                         # Environment configuration file
├── .env.example                 # Example configuration file
├── deployoss.sh                 # Main deployment script
├── test-connectivity.sh         # End-to-end connectivity test
├── diagnose-connectivity.sh     # Network troubleshooting
├── testdeploy.yaml              # Test pod deployments
├── testdeploy.generated.yaml    # Generated test deployments
└── README.md                    # This documentation
```





## 🔍 Validation

After deployment, verify static egress is working:

1. **Check static IP**: Get the firewall's public IP
2. **Test positive case**: Pod with annotation reaches external service via static IP
3. **Test negative case**: Pod without annotation is blocked or uses different IP
4. **Verify routing**: Traffic flows through firewall as expected
5. **Validate egress IP**: Confirm static IP consistency using public ACI container

The test scripts automate this validation process and provide comprehensive testing of:
- **Internal routing**: spoke-to-spoke communication through firewall
- **External egress**: static IP validation via public internet endpoints
- **Access control**: verification that non-annotated pods are properly restricted

---

This demo shows how to implement predictable, static egress IP addresses for AKS workloads using Azure's native networking capabilities.



---

This demo shows how to implement predictable, static egress IP addresses for AKS workloads using Azure's native networking capabilities.
