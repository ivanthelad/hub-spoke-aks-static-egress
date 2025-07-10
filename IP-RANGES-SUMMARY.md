# Azure Hub-and-Spoke Architecture IP Range Summary

## 🌐 Network Architecture Overview

This document provides a comprehensive summary of all IP address ranges used in the Azure Hub-and-Spoke AKS deployment with multi-address space configuration.

## 📊 VNet and Subnet Configuration

### Hub VNet (hub1)
| **VNet** | **Address Space** | **Total IPs** |
|----------|------------------|---------------|
| hub1     | 10.0.0.0/16     | 65,536        |

#### Hub VNet Subnets
| **Subnet Name** | **CIDR** | **IPs Available** | **Purpose** | **Service Delegation** |
|-----------------|----------|-------------------|-------------|----------------------|
| subnet-1 | 10.0.1.0/24 | 251 | General hub services | None |
| AzureFirewallSubnet | 10.0.2.0/24 | 251 | Azure Firewall | None |
| AzureFirewallManagementSubnet | 10.0.3.0/24 | 251 | Firewall management | None |
| dns-inbound-subnet | 10.0.10.0/28 | 11 | DNS resolver inbound | Microsoft.Network/dnsResolvers |
| dns-outbound-subnet | 10.0.20.0/28 | 11 | DNS resolver outbound | Microsoft.Network/dnsResolvers |

### Spoke1 VNet (spoke1) - Multi-Address Space
| **VNet** | **Address Space** | **Total IPs** | **Purpose** |
|----------|------------------|---------------|-------------|
| spoke1   | 10.1.0.0/22     | 1,024         | Routable range for firewall-controlled egress |
| spoke1   | 172.16.0.0/22   | 1,024         | Non-routable private range for app workloads |

#### Spoke1 VNet Subnets
| **Subnet Name** | **CIDR** | **IPs Available** | **Purpose** | **Address Space** | **Egress Path** | **Service Delegation** |
|-----------------|----------|-------------------|-------------|-------------------|-----------------|----------------------|
| egress-subnet | 10.1.0.0/26 | 59 | AKS egress nodes | 10.1.0.0/22 | Via Azure Firewall | None |
| app-subnet | 172.16.1.0/24 | 251 | AKS app nodes | 172.16.0.0/22 | Direct Internet | None |
| apiserver-subnet | 172.16.2.0/28 | 11 | AKS API server | 172.16.0.0/22 | Private endpoint | Microsoft.ContainerService/managedClusters |
| aci-subnet | 172.16.3.0/24 | 251 | Container instances (unused) | 172.16.0.0/22 | Direct Internet | Microsoft.ContainerInstance/containerGroups |

### Spoke2 VNet (spoke2)
| **VNet** | **Address Space** | **Total IPs** |
|----------|------------------|---------------|
| spoke2   | 10.2.0.0/22     | 1,024         |

#### Spoke2 VNet Subnets
| **Subnet Name** | **CIDR** | **IPs Available** | **Purpose** | **Egress Path** | **Service Delegation** |
|-----------------|----------|-------------------|-------------|-----------------|----------------------|
| aci-subnet-spoke2 | 10.2.1.0/24 | 251 | ACI containers (active) | Direct Internet | Microsoft.ContainerInstance/containerGroups |

## 🚀 Kubernetes Configuration

### AKS Cluster IP Ranges
| **Component** | **CIDR** | **Total IPs** | **Purpose** |
|---------------|----------|---------------|-------------|
| Pod CIDR | 192.168.0.0/16 | 65,536 | Kubernetes pod IP addresses |
| Service CIDR | Default (10.0.0.0/16) | 65,536 | Kubernetes service IP addresses |

> **Note**: Service CIDR uses the default AKS range and should not conflict with VNet ranges.

## 🔗 IP Range Allocation Summary

### Address Space Utilization
| **Range Type** | **Network** | **Size** | **Utilization** | **Growth Capacity** |
|----------------|-------------|----------|-----------------|-------------------|
| **Hub Infrastructure** | 10.0.0.0/16 | /16 | ~1,300 IPs used | High |
| **Spoke1 Routable** | 10.1.0.0/22 | /22 | ~60 IPs used | Medium |
| **Spoke1 Private** | 172.16.0.0/22 | /22 | ~260 IPs used | Medium |
| **Spoke2** | 10.2.0.0/22 | /22 | ~250 IPs used | Medium |
| **Pod Network** | 192.168.0.0/16 | /16 | Variable | High |

### Reserved IP Calculations
> Azure reserves the first 4 IPs and last 1 IP in each subnet:
> - **x.x.x.0**: Network address
> - **x.x.x.1**: Default gateway
> - **x.x.x.2**: Azure DNS mapping
> - **x.x.x.3**: Azure DNS mapping  
> - **x.x.x.255**: Network broadcast address

## 🌍 Internet Egress Configuration

### Static IP Egress Patterns
| **Subnet** | **Egress Method** | **Static IP Source** | **Security Level** |
|------------|-------------------|---------------------|-------------------|
| egress-subnet (10.1.0.0/26) | Azure Firewall | Firewall Public IP | High - Full inspection |
| app-subnet (172.16.1.0/24) | Direct Internet | NAT Gateway Public IP | Medium - Network level |
| aci-subnet-spoke2 (10.2.1.0/24) | Direct Internet | Default Azure egress | Low - Outbound only |

## 🔄 Inter-VNet Routing

### Transitive Routing Configuration
| **Source** | **Destination** | **Next Hop** | **Route Type** |
|------------|-----------------|--------------|----------------|
| 10.1.0.0/22 | 10.2.0.0/22 | Azure Firewall | User-defined |
| 172.16.0.0/22 | 10.2.0.0/22 | Azure Firewall | User-defined |
| 10.2.0.0/22 | 10.1.0.0/22 | Azure Firewall | User-defined |
| 10.2.0.0/22 | 172.16.0.0/22 | Azure Firewall | User-defined |

## 🛡️ Security Boundaries

### Network Segmentation
| **Security Zone** | **IP Ranges** | **Access Control** | **Inspection Level** |
|-------------------|---------------|-------------------|---------------------|
| **Hub Services** | 10.0.0.0/16 | Azure Firewall + NSGs | Full |
| **Controlled Egress** | 10.1.0.0/26 | Azure Firewall + NSGs | Full |
| **Direct Egress** | 172.16.1.0/24 | NSGs only | Network level |
| **Private Endpoints** | 172.16.2.0/28 | NSGs + Private Link | Full |
| **Container Services** | 10.2.1.0/24, 172.16.3.0/24 | NSGs only | Network level |

## 📈 Scalability Considerations

### Growth Potential
| **Component** | **Current Allocation** | **Maximum Capacity** | **Expansion Strategy** |
|---------------|----------------------|---------------------|----------------------|
| **Hub VNet** | ~1,300/65,536 IPs | 65,536 | Add subnets within existing /16 |
| **Spoke1 Egress** | ~60/1,024 IPs | 1,024 | Expand subnet or add new spoke |
| **Spoke1 Apps** | ~260/1,024 IPs | 1,024 | Expand subnet or add new spoke |
| **Spoke2** | ~250/1,024 IPs | 1,024 | Expand subnet or add new spoke |
| **Pod Network** | Variable/65,536 IPs | 65,536 | Use cluster autoscaler |

## 🏗️ Architecture Benefits

### Multi-Address Space Advantages
1. **Segregated Traffic Control**: Separate egress policies for different workload types
2. **Network Efficiency**: Smaller subnets reduce broadcast domains
3. **Security Isolation**: Non-routable ranges for sensitive workloads
4. **Compliance Ready**: Predictable egress IPs for external service whitelisting
5. **Cost Optimization**: Direct internet access for high-throughput workloads

### RFC 1918 Private Address Usage
- **10.0.0.0/8**: Hub and primary spoke infrastructure
- **172.16.0.0/12**: Private app workloads and API servers
- **192.168.0.0/16**: Kubernetes pod network overlay

---

**Generated for Azure Hub-and-Spoke AKS Architecture with Multi-Address Space Configuration**  
*Last Updated: July 2025*
