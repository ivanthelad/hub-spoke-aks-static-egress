# Transitive Routing Implementation Test

## Overview
This document verifies that the transitive routing between spoke1 and spoke2 via Azure Firewall is properly configured in the deployment script.

## Implementation Details

### 1. Azure Firewall Network Rules
The script creates two firewall rules for inter-VNet communication:

- **Rule 1**: Allow spoke1 (10.1.0.0/16) → spoke2 (10.2.0.0/16)
- **Rule 2**: Allow spoke2 (10.2.0.0/16) → spoke1 (10.1.0.0/16)

### 2. Route Table Configuration

#### Egress Subnet (10.1.1.0/24)
- Route to firewall for internet traffic (0.0.0.0/0)
- Route to spoke2 via firewall (10.2.0.0/16)

#### App Subnet (10.1.2.0/24)
- Direct internet access (0.0.0.0/0 → Internet)
- Route to spoke2 via firewall (10.2.0.0/16)

#### Spoke2 ACI Subnet (10.2.1.0/24)
- Direct internet access (0.0.0.0/0 → Internet)
- Route to spoke1 via firewall (10.1.0.0/16)

### 3. Traffic Flow
```
spoke1 (10.1.0.0/16) ↔ Azure Firewall (10.0.2.x) ↔ spoke2 (10.2.0.0/16)
```

### 4. Verification Commands
After deployment, test connectivity:

```bash
# From spoke1 to spoke2
kubectl exec -n test-ns pod/test-app-pod -- curl http://10.2.1.x:8080

# From spoke2 to spoke1
az container exec --resource-group $RESOURCE_GROUP --name $ACI_NAME --exec-command "/bin/sh -c 'curl http://10.1.2.x:80'"
```

## Configuration Status
✅ **IMPLEMENTED**: Transitive routing is fully configured in the script
✅ **FIREWALL RULES**: Both directions configured
✅ **ROUTE TABLES**: All subnets have proper routes
✅ **DOCUMENTATION**: Architecture summary includes transitive routing
