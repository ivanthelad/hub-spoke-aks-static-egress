#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 SPOKE1 TO SPOKE2 CONNECTIVITY TROUBLESHOOTING SCRIPT
# ═══════════════════════════════════════════════════════════════════════════════

PREFIX="87"
RESOURCE_GROUP="${PREFIX}-aks-egress"
CLUSTER_NAME="${PREFIX}-cilium-aks-cluster-egress"
FIREWALL_NAME="${PREFIX}-firewall"
ACI_NAME="srcip-http2"

echo "🔍 DIAGNOSING SPOKE1 TO SPOKE2 CONNECTIVITY ISSUES"
echo "════════════════════════════════════════════════════"

# Function to check if resource exists
check_resource() {
    local resource_name="$1"
    local check_command="$2"
    
    echo -n "Checking $resource_name... "
    if eval "$check_command" >/dev/null 2>&1; then
        echo "✅ EXISTS"
        return 0
    else
        echo "❌ NOT FOUND"
        return 1
    fi
}

# 1. Check basic resources
echo ""
echo "1️⃣ CHECKING BASIC RESOURCES"
echo "─────────────────────────────"

check_resource "Resource Group" "az group show --name $RESOURCE_GROUP"
check_resource "Hub VNet" "az network vnet show --name hub1 --resource-group $RESOURCE_GROUP"
check_resource "Spoke1 VNet" "az network vnet show --name spoke1 --resource-group $RESOURCE_GROUP"  
check_resource "Spoke2 VNet" "az network vnet show --name spoke2 --resource-group $RESOURCE_GROUP"
check_resource "Azure Firewall" "az network firewall show --name $FIREWALL_NAME --resource-group $RESOURCE_GROUP"
check_resource "ACI Container" "az container show --name $ACI_NAME --resource-group $RESOURCE_GROUP"

# 2. Check VNet Peering
echo ""
echo "2️⃣ CHECKING VNET PEERING STATUS"
echo "─────────────────────────────────"

echo "Hub1 Peering Connections:"
az network vnet peering list --resource-group $RESOURCE_GROUP --vnet-name hub1 \
  --query "[].{Name:name, State:peeringState, AllowForwarding:allowForwardedTraffic}" -o table

echo ""
echo "Spoke1 Peering Connections:"
az network vnet peering list --resource-group $RESOURCE_GROUP --vnet-name spoke1 \
  --query "[].{Name:name, State:peeringState, AllowForwarding:allowForwardedTraffic}" -o table

echo ""
echo "Spoke2 Peering Connections:"
az network vnet peering list --resource-group $RESOURCE_GROUP --vnet-name spoke2 \
  --query "[].{Name:name, State:peeringState, AllowForwarding:allowForwardedTraffic}" -o table

# 3. Check Firewall Rules
echo ""
echo "3️⃣ CHECKING FIREWALL RULES"
echo "────────────────────────────"

echo "Firewall Policy Rule Collection Groups:"
az network firewall policy rule-collection-group list \
  --policy-name "${FIREWALL_NAME}-policy" \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name, Priority:priority}" -o table

echo ""
echo "Network Rules in NetworkRuleCollectionGroup:"
az network firewall policy rule-collection-group collection list \
  --rule-collection-group-name "NetworkRuleCollectionGroup" \
  --policy-name "${FIREWALL_NAME}-policy" \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name, Priority:priority, Action:action.type}" -o table

# 4. Check Route Tables
echo ""
echo "4️⃣ CHECKING ROUTE TABLES"
echo "──────────────────────────"

echo "Route Tables in Resource Group:"
az network route-table list --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name, Location:location}" -o table

echo ""
echo "Routes in egress-route-table:"
az network route-table route list --resource-group $RESOURCE_GROUP --route-table-name egress-route-table \
  --query "[].{Name:name, AddressPrefix:addressPrefix, NextHopType:nextHopType, NextHopIP:nextHopIpAddress}" -o table 2>/dev/null || echo "❌ egress-route-table not found"

echo ""
echo "Routes in app-route-table:"
az network route-table route list --resource-group $RESOURCE_GROUP --route-table-name app-route-table \
  --query "[].{Name:name, AddressPrefix:addressPrefix, NextHopType:nextHopType, NextHopIP:nextHopIpAddress}" -o table 2>/dev/null || echo "❌ app-route-table not found"

echo ""
echo "Routes in spoke2-route-table:"
az network route-table route list --resource-group $RESOURCE_GROUP --route-table-name spoke2-route-table \
  --query "[].{Name:name, AddressPrefix:addressPrefix, NextHopType:nextHopType, NextHopIP:nextHopIpAddress}" -o table 2>/dev/null || echo "❌ spoke2-route-table not found"

# 5. Check Subnet Associations
echo ""
echo "5️⃣ CHECKING SUBNET ROUTE TABLE ASSOCIATIONS"
echo "──────────────────────────────────────────────"

echo "Spoke1 egress-subnet route table:"
az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name egress-subnet \
  --query "routeTable.id" -o tsv

echo "Spoke1 app-subnet route table:"
az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name app-subnet \
  --query "routeTable.id" -o tsv

echo "Spoke2 aci-subnet-spoke2 route table:"
az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke2 --name aci-subnet-spoke2 \
  --query "routeTable.id" -o tsv

# 6. Get IP Addresses
echo ""
echo "6️⃣ IP ADDRESS INFORMATION"
echo "───────────────────────────"

FIREWALL_IP=$(az network firewall show --name $FIREWALL_NAME --resource-group $RESOURCE_GROUP \
  --query "ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null)
echo "Firewall Private IP: ${FIREWALL_IP:-'Not available'}"

ACI_IP=$(az container show --name $ACI_NAME --resource-group $RESOURCE_GROUP \
  --query "ipAddress.ip" -o tsv 2>/dev/null)
echo "ACI Container IP (spoke2): ${ACI_IP:-'Not available'}"

# 7. Test Commands
echo ""
echo "7️⃣ CONNECTIVITY TEST COMMANDS"
echo "───────────────────────────────"

echo "To test connectivity from AKS pods in spoke1 to ACI in spoke2:"
echo "kubectl run test-pod --image=busybox --rm -it --restart=Never -- /bin/sh"
echo "# Inside the pod, run:"
echo "wget -O- http://${ACI_IP:-'<ACI_IP>'}:8080"
echo ""

echo "To test from ACI container to spoke1:"
if [ ! -z "$ACI_IP" ]; then
    echo "az container exec --resource-group $RESOURCE_GROUP --name $ACI_NAME --exec-command \"/bin/sh -c 'curl -I http://10.1.2.4:80 || echo Connection failed'\""
else
    echo "az container exec --resource-group $RESOURCE_GROUP --name $ACI_NAME --exec-command \"/bin/sh -c 'curl -I http://10.1.2.4:80'\""
fi

# 8. Recommendations
echo ""
echo "8️⃣ TROUBLESHOOTING RECOMMENDATIONS"
echo "────────────────────────────────────"

if [ -z "$FIREWALL_IP" ]; then
    echo "❌ Firewall IP not available - firewall may not be deployed"
    echo "   → Run: ./deployoss.sh --step firewall"
fi

if [ -z "$ACI_IP" ]; then
    echo "❌ ACI Container IP not available - container may not be deployed"
    echo "   → Run: ./deployoss.sh --step aci"
fi

echo ""
echo "🔧 To fix spoke1→spoke2 connectivity issues:"
echo "1. Ensure full VNet peering between hub1↔spoke2 (not subnet-level)"
echo "2. Verify firewall rules allow spoke1→spoke2 traffic"
echo "3. Check route tables point spoke2 traffic to firewall"
echo "4. Test with: ./deployoss.sh --step firewall && ./deployoss.sh --step routes"

echo ""
echo "✅ DIAGNOSIS COMPLETE"
