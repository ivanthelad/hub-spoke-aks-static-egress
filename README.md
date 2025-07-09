# Azure Hub-and-Spoke AKS Architecture with Static Egress IPs

This project implements a comprehensive Azure Hub-and-Spoke network architecture featuring Azure Kubernetes Service (AKS) with **static egress IP patterns**, Azure Firewall, and transitive routing capabilities. The architecture demonstrates how to achieve predictable, consistent egress IP addresses for AKS workloads - enabling external service integrations and compliance requirements through subnet-based routing rather than dynamic pod scheduling.

## 🏗️ Architecture Concept

### Hub-and-Spoke Network Topology with Static Egress IPs

The **Hub-and-Spoke** architecture is a network design pattern that centralizes shared services in a hub virtual network while distributing workloads across multiple spoke virtual networks. This implementation specifically focuses on **static egress IP management** for AKS workloads, ensuring predictable and consistent outbound IP addresses for external service integrations and compliance requirements.

**Key Design Principles:**
- **Static Egress IPs**: Predictable, consistent egress IP addresses for external integrations
- **Subnet-Based Routing**: Network-level traffic steering rather than application-level routing
- **Dual Egress Patterns**: Demonstrates both direct and firewall-controlled internet access
- **Performance vs Security**: Balance between network performance and security requirements
- **Centralized Security**: Single point of egress control via Azure Firewall for sensitive workloads

**This architecture solves real-world challenges:**
- **External Service Integration**: Third-party APIs and services can whitelist specific IP ranges
- **Compliance Requirements**: Predictable egress IPs enable consistent audit trails and reporting
- **Network Monitoring**: Simplified egress traffic analysis with known, static IP addresses
- **Cost Management**: Shared firewall infrastructure across multiple environments
- **Security Policies**: Consistent application of security rules based on egress IP patterns

### Key Components


#### 🏢 Hub VNet (10.0.0.0/16)

- **Azure Firewall**: Central security appliance for traffic filtering and NAT
- **Firewall Subnet**: Dedicated subnet for Azure Firewall deployment
- **Management Services**: Shared infrastructure components


#### 🏭 Spoke1 VNet (10.1.0.0/16) - AKS Production

- **App Subnet**: Production AKS nodes with direct internet access
- **Egress Subnet**: AKS egress nodes routed through Azure Firewall
- **API Server Subnet**: Private AKS API server endpoints


#### 🏭 Spoke2 VNet (10.2.0.0/16) - Container Services


- **ACI Subnet**: Azure Container Instances for lightweight workloads

### Static Egress Architecture Deep Dive


#### 🎯 Static Egress Architecture Strategy


The architecture implements **subnet-based static egress** to handle different egress requirements:

```text
┌─────────────────────────────────────────────────────────────────┐
│                    AKS Cluster Architecture                     │
├─────────────────────────────────────────────────────────────────┤
│   App Subnet            │         Egress Subnet                 │
│   (10.1.1.0/24)         │         (10.1.2.0/24)                │
│                         │                                       │
│ ┌─────────────────────┐ │ ┌─────────────────────────────────────┐ │
│ │ NAT Gateway Egress  │ │ │ Azure Firewall Egress               │ │
│ │ Static Public IPs   │ │ │ Static Public IPs                   │ │
│ │ Direct Internet     │ │ │ Security-Controlled                 │ │
│ │ High Performance    │ │ │ Full Traffic Inspection             │ │
│ └─────────────────────┘ │ └─────────────────────────────────────┘ │
│                         │                                       │
│ Route: 0.0.0.0/0 →      │ Route: 0.0.0.0/0 →                    │
│        NAT Gateway      │        Azure Firewall                 │
└─────────────────────────────────────────────────────────────────┘
```


#### 🚦 Static Egress Traffic Patterns


##### 1. NAT Gateway Egress (App Subnet)


- **Target**: High-throughput applications, CDN integration, real-time services
- **Path**: App Subnet → NAT Gateway → Static Public IPs → Internet
- **Benefits**: Minimal latency, maximum throughput, cost-effective for bulk traffic
- **Static IP**: Predictable egress IPs for external service whitelisting


##### 2. Firewall Egress (Egress Subnet)


- **Target**: Financial services, healthcare, government workloads
- **Path**: Egress Subnet → Azure Firewall → Static Public IPs → Internet
- **Benefits**: Full inspection, logging, compliance, threat protection
- **Static IP**: Consistent firewall public IPs for security policies


##### 3. Route Table Control


- **Implementation**: Static routes determine egress path based on subnet placement
- **Flexibility**: Workloads can be placed in appropriate subnets based on requirements
- **Predictability**: No dynamic routing decisions - consistent egress behavior


#### 🛡️ Static Egress IP Strategy


The architecture implements **static egress IP** patterns to provide:

- **Predictable Egress**: Consistent, known IP addresses for external service whitelist
- **Compliance Control**: Guaranteed egress paths for regulatory requirements
- **Network Policies**: Fine-grained control over which workloads use which egress paths
- **Audit Trail**: Complete visibility into egress traffic patterns and destinations
- **Failover Design**: Redundant egress paths for high availability scenarios


#### 📊 Static Egress Concepts


**Egress Path Determination**:

The architecture uses **subnet-based egress routing** rather than dynamic pod scheduling:

- **App Subnet (10.1.1.0/24)**: Workloads with direct internet access get predictable NAT gateway IPs
- **Egress Subnet (10.1.2.0/24)**: Security-controlled workloads get static firewall public IPs
- **Route Table Control**: Static routes determine egress path based on subnet placement

**Benefits of Static Egress**:
- **External Service Integration**: Third-party services can whitelist specific IP ranges
- **Compliance Reporting**: Simplified audit trails with known egress IPs
- **Network Monitoring**: Easier to track and analyze egress traffic patterns
- **Security Policies**: Consistent application of security rules per egress path

### Transitive Routing

**Transitive Routing** enables spoke1 ↔ spoke2 communication through the hub firewall:

- Traffic between spokes is inspected and controlled by Azure Firewall
- Firewall policies define which inter-spoke communication is allowed
- Route tables direct cross-spoke traffic through the firewall
- Full network visibility and logging for compliance

### Security Model


#### Two-Tier Internet Access


- **Direct Access**: App subnet → Internet (performance-optimized)
- **Controlled Access**: Egress subnet → Azure Firewall → Internet (security-controlled)


#### Network Segmentation


- **VNet Peering**: Controlled connectivity between hub and spokes
- **NSG Rules**: Subnet-level traffic filtering
- **Firewall Policies**: Application and network-level inspection

## 🌐 Static Egress IP Benefits

### Why Static Egress IPs Matter

**Traditional Challenge**: Dynamic pod scheduling and NAT can result in unpredictable egress IP addresses, making it difficult to:
- Whitelist IP ranges with external services
- Maintain consistent security policies
- Provide audit trails for compliance

**Static Egress Solution**: This architecture provides predictable, consistent egress IP addresses through:
- **Subnet-based routing**: Traffic egress determined by subnet placement, not pod scheduling
- **Static public IPs**: Both NAT Gateway and Azure Firewall use pre-allocated static public IPs
- **Route table control**: Explicit routing rules ensure consistent egress paths

### Business Impact

**External Service Integration**:
- SaaS providers can whitelist specific IP ranges
- Partner networks can configure firewall rules for known IPs
- API rate limiting and authentication based on source IP

**Compliance & Auditing**:
- Simplified audit trails with known egress IP addresses
- Regulatory compliance through predictable network behavior
- Consistent security policy application per egress path

**Operational Benefits**:
- Reduced troubleshooting complexity
- Clearer network monitoring and alerting
- Simplified change management processes

## 🚀 Getting Started

### Prerequisites

- Azure CLI (latest version)
- Bash shell (macOS/Linux/WSL)
- Helm 3.x (for AKS deployments)
- kubectl (for Kubernetes management)
- Azure subscription with appropriate permissions

### Quick Start

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd subnetpeeredaks
   ```

2. **Configure deployment parameters**
   ```bash
   # Edit the PREFIX and LOCATION in deployoss.sh
   vim deployoss.sh
   ```

3. **Deploy the complete architecture**
   ```bash
   ./deployoss.sh
   ```

4. **Verify deployment**
   ```bash
   ./diagnose-connectivity.sh
   ```

## 📋 Usage Instructions

### Individual Step Deployment

The deployment script supports modular execution for targeted updates:

```bash
# Deploy networking only
./deployoss.sh --step networking

# Deploy firewall rules
./deployoss.sh --step firewall

# Deploy route tables  
./deployoss.sh --step routes

# View architecture summary
./deployoss.sh --step summary

# Deploy AKS cluster
./deployoss.sh --step aks

# Create test workloads
./deployoss.sh --step workloads

# Deploy ACI containers
./deployoss.sh --step aci

# Create egress node pool
./deployoss.sh --step egress-pool

# Install kube-egress-gateway
./deployoss.sh --step helm-values

# Deploy test manifests
./deployoss.sh --step testdeploy
```

### Deployment Options


#### Full Deployment (Recommended)

```bash
# Deploy all components with progress tracking
ENABLE_PROGRESS=true ./deployoss.sh

# Deploy all components without progress tracking
ENABLE_PROGRESS=false ./deployoss.sh
```


#### Custom Configuration

Modify variables in `deployoss.sh`:
```bash
PREFIX="87"                                    # Resource name prefix
LOCATION="swedencentral"                       # Azure region
NODE_SIZE="Standard_DS3_v2"                   # AKS node size
K8S_VERSION="1.31"                            # Kubernetes version
```

### Testing Static Egress Configuration


#### 1. Verify Static Egress IPs

```bash
# Get NAT Gateway public IP (App Subnet egress)
az network public-ip show --name 87-nat-pip --resource-group 87-aks-egress --query "ipAddress" -o tsv

# Get Azure Firewall public IP (Egress Subnet egress)
az network public-ip show --name 87-firewall-pip --resource-group 87-aks-egress --query "ipAddress" -o tsv

# Test egress from app subnet (should use NAT Gateway IP)
kubectl run test-app-egress --image=busybox --rm -it --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"agentpool":"nodepool1"}}}' \
  -- wget -qO- http://httpbin.org/ip

# Test egress from egress subnet (should use Firewall IP)
kubectl run test-egress-subnet --image=busybox --rm -it --restart=Never \
  --overrides='{"spec":{"nodeSelector":{"agentpool":"egresspool"}}}' \
  -- wget -qO- http://httpbin.org/ip
```


#### 2. Test Transitive Routing (Spoke1 ↔ Spoke2)

```bash
# Get ACI IP address
ACI_IP=$(az container show --name srcip-http2 --resource-group 87-aks-egress --query "ipAddress.ip" -o tsv)

# Test from spoke1 to spoke2 (should show firewall IP as source)
kubectl run test-transitive --image=busybox --rm -it --restart=Never \
  -- wget -qO- http://$ACI_IP:8080

# Test from spoke2 to spoke1 (requires AKS service)
az container exec --resource-group 87-aks-egress --name srcip-http2 \
  --exec-command "/bin/sh -c 'curl -I http://10.1.2.4:80'"
```


#### 3. Monitor Firewall Traffic

```bash
# View firewall logs
az monitor activity-log list --resource-group 87-aks-egress \
  --max-events 10 --query "[].{Time:eventTimestamp, Operation:operationName.value}"

# Check firewall rules
az network firewall policy rule-collection-group list \
  --policy-name 87-firewall-policy --resource-group 87-aks-egress
```

### Troubleshooting


#### Run Diagnostics

```bash
# Comprehensive connectivity diagnosis
./diagnose-connectivity.sh
```


#### Common Issues


1. **Spoke1 → Spoke2 connectivity fails**
   - Verify full VNet peering (not subnet-level)
   - Check firewall rules allow inter-spoke traffic
   - Confirm route tables point to firewall

2. **Internet access blocked from egress subnet**
   - Verify firewall rules allow outbound traffic
   - Check route table points 0.0.0.0/0 to firewall
   - Confirm firewall has public IP

3. **AKS deployment issues**
   - Verify managed identity permissions
   - Check subnet delegations for AKS
   - Confirm API server subnet configuration


#### Manual Fixes

```bash
# Fix VNet peering
./deployoss.sh --step networking

# Update firewall rules
./deployoss.sh --step firewall

# Reconfigure routing
./deployoss.sh --step routes
```

## 🔧 Customization

### Adding New Spokes

1. **Update `create_networking()` function**:
   ```bash
   # Add new spoke VNet
   az network vnet create --name spoke3 \
     --resource-group $RESOURCE_GROUP \
     --address-prefix 10.3.0.0/16
   
   # Add peering
   az network vnet peering create --name hub1_to_spoke3 \
     --resource-group $RESOURCE_GROUP \
     --vnet-name hub1 --remote-vnet spoke3 \
     --allow-forwarded-traffic --allow-vnet-access
   ```

2. **Update firewall rules** for new spoke communication

3. **Add route tables** for the new spoke subnets

### Modifying Firewall Policies

Edit the `create_firewall()` function to add custom rules:
```bash
# Example: Allow specific port from spoke1 to spoke2
az network firewall policy rule-collection-group collection add-filter-collection \
  --collection-priority 170 \
  --name "AllowSpecificPort" \
  --action Allow \
  --rule-name "AllowHTTP" \
  --rule-type NetworkRule \
  --destination-addresses "10.2.0.0/16" \
  --destination-ports "80" \
  --ip-protocols "TCP" \
  --source-addresses "10.1.0.0/16"
```

## 📁 Project Structure

```
subnetpeeredaks/
├── deployoss.sh                 # Main deployment script
├── diagnose-connectivity.sh     # Troubleshooting script  
├── testdeploy.yaml              # Kubernetes test manifest
├── test-transitive-routing.md   # Architecture verification
├── helmosss/
│   ├── values.template.yaml     # Helm values template
│   └── values.yaml             # Generated Helm values
└── README.md                   # This documentation
```

## 🎯 Use Cases for Static Egress IPs

### Enterprise Workloads

- **Third-Party API Integration**: External services can whitelist specific IP ranges
- **SaaS Connectivity**: Predictable egress IPs for cloud service integrations
- **Partner Network Access**: Consistent IP addresses for B2B network connectivity

### DevOps Scenarios

- **Multi-Environment**: Separate spokes with distinct egress IP ranges per environment
- **Microservices**: Service-to-service communication with known egress patterns
- **CI/CD Pipelines**: Consistent egress IPs for deployment pipeline integrations

### Compliance Requirements

- **Audit Trails**: Static IP addresses enable simplified compliance reporting
- **Regulatory Standards**: Predictable egress paths for financial/healthcare regulations
- **Network Segmentation**: Isolated spoke environments with distinct egress profiles

## 🔍 Monitoring and Observability

### Built-in Logging
- Azure Firewall logs all allowed/denied traffic
- Route table changes are audited
- VNet peering status is monitored

### Recommended Monitoring
```bash
# Enable Azure Monitor for containers
az aks enable-addons --resource-group 87-aks-egress \
  --name 87-cilium-aks-cluster-egress --addons monitoring

# View firewall metrics
az monitor metrics list --resource /subscriptions/<sub>/resourceGroups/87-aks-egress/providers/Microsoft.Network/azureFirewalls/87-firewall
```

## 🛡️ Security Considerations

### Network Security
- ✅ All inter-spoke traffic inspected by firewall
- ✅ NSGs provide subnet-level protection
- ✅ Private endpoints for AKS API servers
- ✅ No direct spoke-to-spoke connectivity

### Identity and Access
- ✅ Managed identities for AKS nodes
- ✅ RBAC for Kubernetes resources
- ✅ Azure AD integration available

### Compliance
- ✅ Traffic logging for audit trails
- ✅ Centralized policy enforcement
- ✅ Network segmentation controls

## 💡 Best Practices

### Deployment
1. Always test in non-production first
2. Use step-by-step deployment for troubleshooting
3. Monitor resource costs during deployment
4. Verify connectivity after each major step

### Operations
1. Regularly review firewall logs
2. Update AKS and node images monthly
3. Monitor network performance metrics
4. Backup critical configurations

### Security
1. Implement least-privilege access
2. Regularly audit firewall rules
3. Use Azure Policy for governance
4. Enable Azure Security Center

---

## 📞 Support

For issues and questions:
1. Run `./diagnose-connectivity.sh` for automated troubleshooting
2. Check Azure Activity Log for deployment errors
3. Review firewall logs for connectivity issues
4. Verify resource quotas and limits

**Architecture designed for enterprise-grade Azure workloads with security, scalability, and compliance in mind.**
```

### Deploy with AKS

To deploy the complete solution including AKS clusters:

```bash
./deploy-bicep.sh --deploy-aks
```

### Custom Deployment Options

To deploy to a custom Azure region:

```bash
./deploy-bicep.sh --location westus2
```

To deploy to a custom resource group:

```bash
./deploy-bicep.sh --resource-group my-custom-rg
```

See [network-deployment-options.md](./network-deployment-options.md) for more details.

## Network Details

### Hub Network

- Address space: 10.0.0.0/16
- Subnets:
  - AzureFirewallSubnet: 10.0.0.0/24
  - DnsResolverSubnet: 10.0.1.0/24
  - AzureBastionSubnet: 10.0.2.0/24

### Spoke Networks

- Spoke 1:
  - Address space: 10.1.0.0/16
  - Subnets:
    - Default: 10.1.0.0/24
    - Workload: 10.1.1.0/24

- Spoke 2:
## 📝 Legacy Notes and Development History

### Architecture Evolution
This project evolved from a simple subnet peering implementation to a comprehensive hub-and-spoke architecture with:
- Full VNet peering (replacing subnet-level peering)
- Transitive routing capabilities
- Azure Firewall integration
- AKS with Cilium CNI
- Container instance deployments

### Migration from Previous Versions
If upgrading from earlier versions:
1. VNet peering changed from subnet-level to full VNet peering
2. Firewall rules updated for better transitive routing
3. Route tables restructured for proper spoke-to-spoke communication

---

**This architecture represents a production-ready, enterprise-grade Azure networking solution optimized for security, performance, and scalability.** 
  