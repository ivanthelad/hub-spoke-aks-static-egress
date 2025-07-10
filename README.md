# Azure AKS Static Egress Demo

This project demonstrates how to achieve **static egress IPs** for Azure Kubernetes Service (AKS) workloads using a hub-and-spoke network architecture with Azure Firewall.

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
┌─────────────────────────────────────────────────────────────────┐
│                    Hub-and-Spoke Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Spoke1 (AKS)              Hub                 Spoke2 (ACI)     │
│  ┌─────────────────┐      ┌─────────────┐      ┌─────────────┐  │
│  │ App Subnet      │      │ Azure       │      │ ACI         │  │
│  │ 172.16.1.0/24   │◄────►│ Firewall    │◄────►│ Container   │  │
│  │                 │      │ 10.0.2.0/24 │      │ 10.2.1.0/24 │  │
│  └─────────────────┘      └─────────────┘      └─────────────┘  │
│  ┌─────────────────┐              │                             │
│  │ Egress Subnet   │              │                             │
│  │ 10.1.0.0/26     │◄─────────────┘                             │
│  │ (Static Egress) │               Static Public IP             │
│  └─────────────────┘               20.240.x.x                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
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

# Run connectivity test
./test-connectivity.sh
```

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

```bash
./test-connectivity.sh
```

### diagnose-connectivity.sh
Network diagnostics for troubleshooting:
```bash
./diagnose-connectivity.sh
```

## 🔧 Configuration

### Key Components

**testdeploy.yaml** contains two test deployments:
- `test-static-egress`: Has static gateway annotation (should work)
- `test-negative-connectivity`: No annotation (should be blocked)

**Static Gateway Configuration**:
```yaml
apiVersion: egressgateway.kubernetes.azure.com/v1alpha1
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

```
hub-spoke-aks-static-egress/
├── deployoss.sh                 # Main deployment script
├── test-connectivity.sh         # End-to-end connectivity test
├── diagnose-connectivity.sh     # Network troubleshooting
├── testdeploy.yaml              # Test pod deployments
├── testdeploy.generated.yaml    # Generated test deployments
└── README.md                   # This documentation
```

## � Use Cases

**When you need static egress IPs:**
- External APIs that require IP whitelisting
- Compliance requirements for audit trails
- Consistent egress behavior for specific workloads
- Integration with legacy systems that filter by IP

**Example**: A financial application needs to call a third-party API that only allows specific IP addresses. By using the static egress configuration, the pod's outbound traffic will always come from the firewall's static public IP.

## 🔍 Validation

After deployment, verify static egress is working:

1. **Check static IP**: Get the firewall's public IP
2. **Test positive case**: Pod with annotation reaches external service via static IP
3. **Test negative case**: Pod without annotation is blocked or uses different IP
4. **Verify routing**: Traffic flows through firewall as expected

The test scripts automate this validation process.

---

This demo shows how to implement predictable, static egress IP addresses for AKS workloads using Azure's native networking capabilities.



---

This demo shows how to implement predictable, static egress IP addresses for AKS workloads using Azure's native networking capabilities. 
  