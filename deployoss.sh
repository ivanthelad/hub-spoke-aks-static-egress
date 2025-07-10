# ═══════════════════════════════════════════════════════════════════════════════
# 🏗️  HUB AND SPOKE AKS DEPLOYMENT SCRIPT
# ═══════════════════════════════════════════════════════════════════════════════

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading configuration from .env file..."
    source .env
else
    echo "Warning: .env file not found. Using default values..."
    # Default values (fallback if .env is missing)
    PREFIX="88"
    RESOURCE_GROUP="${PREFIX}-aks-egress"
    CLUSTER_NAME="${PREFIX}-cilium-aks-cluster-egress"
    LOCATION="swedencentral"
    NODE_SIZE="Standard_DS3_v2"
    NODE_SIZE2="Standard_DS2_v2"
    NODE_COUNT=3
    K8S_VERSION="1.31"
    IDENTITY_NAME="${CLUSTER_NAME}-identity"
    ACI_NAME="srcip-http2"
    NATGW_NAME="${PREFIX}-natgw"
    PUBLIC_IP_NAME="${PREFIX}-natgw-pip"
    FIREWALL_NAME="${PREFIX}-firewall"
    PUBLIC_ACI_NAME="srcip-http-public"
    PUBLIC_ACI_IMAGE="mendhak/http-https-echo:37"
    PUBLIC_ACI_PORT="8080"
    ENABLE_PROGRESS=true
    TOTAL_STEPS=9
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 PROGRESS TRACKING CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════
# 
# To DISABLE progress tracking, run with:
#   ENABLE_PROGRESS=false ./deployoss.sh
#
# To ENABLE progress tracking (default), run with:
#   ENABLE_PROGRESS=true ./deployoss.sh
#   or simply: ./deployoss.sh
#
# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 INDIVIDUAL STEP EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════
# 
# Run individual steps with --step parameter:
#   ./deployoss.sh --step networking
#   ./deployoss.sh --step firewall
#   ./deployoss.sh --step routes
#   ./deployoss.sh --step summary
#   ./deployoss.sh --step aks
#   ./deployoss.sh --step workloads
#   ./deployoss.sh --step egress-pool
#   ./deployoss.sh --step helm-values
#   ./deployoss.sh --step testdeploy
#   ./deployoss.sh --step all (default)
#
# ═══════════════════════════════════════════════════════════════════════════════

# Progress tracking variables
CURRENT_STEP=0
ENABLE_PROGRESS=${ENABLE_PROGRESS:-true}

# Progress tracking function
show_progress() {
  if [[ "$ENABLE_PROGRESS" == "true" ]]; then
    local step_name="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local percentage=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📋 STEP $CURRENT_STEP/$TOTAL_STEPS ($percentage%) - $step_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi
}

# Function to complete a step
complete_step() {
  if [[ "$ENABLE_PROGRESS" == "true" ]]; then
    local step_name="$1"
    echo ""
    echo "✅ COMPLETED: $step_name"
    echo ""
  fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════
##https://learn.microsoft.com/en-us/azure/virtual-network/how-to-configure-subnet-peering
## Use az network vnet create to create two virtual networks hub1 and spoke1.
create_natGW() {
  # Create a public IP for NAT Gateway (Standard SKU, Zone 1)
  az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name $PUBLIC_IP_NAME \
    --location $LOCATION \
    --sku Standard \
    --zone 1 \
    --allocation-method static

  # Create the NAT Gateway in zone 1
  az network nat gateway create \
    --resource-group $RESOURCE_GROUP \
    --name $NATGW_NAME \
    --location $LOCATION \
    --public-ip-addresses $PUBLIC_IP_NAME \
    --zone 1

  # Attach the NAT Gateway to the egress subnet
  az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --name egress-subnet \
    --nat-gateway $NATGW_NAME

  echo "NAT Gateway $NATGW_NAME created in zone 1 and attached to $VNET_NAME/$SUBNET_NAME."
  echo "NAT Gateway setup complete."
}
create_app_subnet_nsg() {
  # Create NSG
  az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name denyoutbound \
    --location $LOCATION

  # Add deny all outbound rule
  az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name denyoutbound \
    --name DenyAllOutbound \
    --priority 100 \
    --direction Outbound \
    --access Deny \
    --protocol '*' \
    --source-address-prefix '*' \
    --source-port-range '*' \
    --destination-address-prefix '*' \
    --destination-port-range '*'

  # Associate NSG with the app subnet
  az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --name app-subnet \
    --network-security-group denyoutbound

  echo "NSG denyoutbound created and associated with spoke1/app-subnet."
}

create_networking() {
  # Create VNets
  echo "Creating VNets and subnets..."
  # Create hub1 and spoke1 VNets
  echo "Creating hub1 and spoke1 VNets..."
  az network vnet create \
    --name hub1 \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --address-prefix 10.0.0.0/16 >/dev/null

  az network vnet create \
    --name spoke1 \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --address-prefix 10.1.0.0/22 172.16.0.0/22 >/dev/null

  az network vnet create \
    --name spoke2 \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --address-prefix 10.2.0.0/22 >/dev/null

  # Create subnets and export their IDs
  echo "Creating subnets in hub1, spoke1, and spoke2 VNets..."
  az network vnet subnet create \
    --name subnet-1 \
    --resource-group $RESOURCE_GROUP \
    --vnet-name hub1 \
    --address-prefix 10.0.1.0/24 >/dev/null
  az network vnet subnet create \
    --name AzureFirewallSubnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name hub1 \
    --address-prefix 10.0.2.0/24 >/dev/null
    
  az network vnet subnet create \
    --name AzureFirewallManagementSubnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name hub1 \
    --address-prefix 10.0.3.0/24 >/dev/null
  ## Dns resolver subnets
  # Create inbound and outbound subnets in hub1 VNet
  az network vnet subnet create \
    --name dns-inbound-subnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name hub1 \
    --address-prefix 10.0.10.0/28 \
    --delegations Microsoft.Network/dnsResolvers

  az network vnet subnet create \
    --name dns-outbound-subnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name hub1 \
    --address-prefix 10.0.20.0/28 \
    --delegations Microsoft.Network/dnsResolvers

  az network vnet subnet create \
    --name egress-subnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --address-prefix 10.1.0.0/26 >/dev/null
  export EGRESS_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name egress-subnet --query id -o tsv)

  az network vnet subnet create \
    --name app-subnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --address-prefix 172.16.1.0/24 >/dev/null
  export APP_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name app-subnet --query id -o tsv)

  az network vnet subnet create --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --name apiserver-subnet \
    --delegations Microsoft.ContainerService/managedClusters \
    --address-prefix 172.16.2.0/28 >/dev/null
  export APISERVER_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name apiserver-subnet --query id -o tsv)

  az network vnet subnet create --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --name aci-subnet \
    --delegations Microsoft.ContainerInstance/containerGroups \
    --address-prefix 172.16.3.0/24 >/dev/null
  export ACI_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name aci-subnet --query id -o tsv)

  # Create subnets in spoke2 VNet
  az network vnet subnet create \
    --name aci-subnet-spoke2 \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke2 \
    --delegations Microsoft.ContainerInstance/containerGroups \
    --address-prefix 10.2.1.0/24 >/dev/null
  export ACI_SUBNET_SPOKE2_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke2 --name aci-subnet-spoke2 --query id -o tsv)

  # VNet peering - Hub and Spoke model
  echo "Creating VNet peering for hub and spoke model..."
  
  # Hub to Spoke peering (hub1 -> spoke1)


  # VNet peering
  az network vnet peering create --name hub1_to_spoke1 \
                                 --resource-group $RESOURCE_GROUP \
                                 --vnet-name hub1 \
                                 --remote-vnet spoke1 \
                                 --allow-forwarded-traffic  \
                                 --allow-gateway-transit  \
                                 --allow-vnet-access  \
                                 --peer-complete-vnet false \
                                 --local-subnet-names AzureFirewallSubnet \
                                 --remote-subnet-names egress-subnet

  # Spoke to Hub peering (spoke1 -> hub1)


  az network vnet peering create --name spoke1_to_hub1 \
                                 --resource-group $RESOURCE_GROUP \
                                 --vnet-name spoke1 \
                                 --remote-vnet hub1 \
                                 --allow-forwarded-traffic \
                                 --allow-gateway-transit \
                                 --allow-vnet-access \
                                 --peer-complete-vnet false \
                                 --local-subnet-names egress-subnet \
                                 --remote-subnet-names AzureFirewallSubnet

  echo "VNet peering configured for hub and spoke topology (including spoke2)."
  az network vnet peering sync --name hub1_to_spoke1 \
                               --resource-group $RESOURCE_GROUP \
                               --vnet-name hub1
  az network vnet peering sync --name spoke1_to_hub1 \
                               --resource-group $RESOURCE_GROUP \
                               --vnet-name spoke1

  # Hub to Spoke2 peering (hub1 -> spoke2) - FULL VNet peering for transitive routing
  echo "Creating full VNet peering between hub1 and spoke2 for transitive routing..."
  az network vnet peering create --name hub1_to_spoke2 \
                                 --resource-group $RESOURCE_GROUP \
                                 --vnet-name hub1 \
                                 --remote-vnet spoke2 \
                                 --allow-forwarded-traffic  \
                                 --allow-gateway-transit  \
                                 --allow-vnet-access

  # Spoke2 to Hub peering (spoke2 -> hub1) - FULL VNet peering for transitive routing
  az network vnet peering create --name spoke2_to_hub1 \
                                 --resource-group $RESOURCE_GROUP \
                                 --vnet-name spoke2 \
                                 --remote-vnet hub1 \
                                 --allow-forwarded-traffic \
                                 --allow-gateway-transit \
                                 --allow-vnet-access

  az network vnet peering sync --name hub1_to_spoke2 \
                               --resource-group $RESOURCE_GROUP \
                               --vnet-name hub1
  az network vnet peering sync --name spoke2_to_hub1 \
                               --resource-group $RESOURCE_GROUP \
                               --vnet-name spoke2
                               
  echo "Networking setup complete."
}
create_firewall() {
  echo "Creating Azure Firewall with modern policy-based approach..."
  
  # Create firewall policy first (modern approach)
  echo "Creating Azure Firewall Policy..."
  az network firewall policy create \
    --name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard \
    --threat-intel-mode Alert \
    --enable-dns-proxy true >/dev/null

  echo "Firewall policy created successfully."

  # Create public IP for firewall
  echo "Creating public IP for firewall..."
  az network public-ip create \
    --name "${FIREWALL_NAME}-pip" \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --allocation-method static \
    --sku standard >/dev/null

  # Create Azure Firewall with policy
  echo "Creating Azure Firewall with policy..."
  az network firewall create \
    --name $FIREWALL_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --firewall-policy "${FIREWALL_NAME}-policy" \
    --sku AZFW_VNet \
    --tier Standard >/dev/null

  # Configure firewall IP configuration
  echo "Configuring firewall IP configuration..."
  az network firewall ip-config create \
    --firewall-name $FIREWALL_NAME \
    --name "FW-config" \
    --public-ip-address "${FIREWALL_NAME}-pip" \
    --resource-group $RESOURCE_GROUP \
    --vnet-name hub1 >/dev/null

  # Note: Management IP configuration for forced tunneling would be configured
  # during firewall creation if needed, but is not required for this deployment
  echo "Firewall configuration completed (management IP config not required for this setup)"

  # Get firewall private IP
  echo "Retrieving firewall private IP..."
  fwprivaddr="$(az network firewall ip-config list -g $RESOURCE_GROUP -f $FIREWALL_NAME --query "[?name=='FW-config'].privateIpAddress" --output tsv)"
  echo "Firewall private IP: $fwprivaddr"

  # Create rule collection group for network rules
  echo "Creating network rule collection group..."
  az network firewall policy rule-collection-group create \
    --name "NetworkRuleCollectionGroup" \
    --policy-name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --priority 100 >/dev/null

  # Create network rule collection to allow all outbound traffic from egress subnet
  echo "Creating network rule collection for egress subnet..."
  az network firewall policy rule-collection-group collection add-filter-collection \
    --collection-priority 100 \
    --name "AllowEgressSubnetOutbound" \
    --action Allow \
    --rule-name "AllowAllOutboundFromEgress" \
    --rule-type NetworkRule \
    --description "Allow all outbound traffic from egress subnet" \
    --destination-addresses "*" \
    --destination-ports "*" \
    --ip-protocols "Any" \
    --source-addresses "10.1.0.0/26" \
    --policy-name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --rule-collection-group-name "NetworkRuleCollectionGroup" >/dev/null

  # Create network rule collection for inter-VNet communication (transitive routing)
  echo "Creating network rule collection for inter-VNet (spoke-to-spoke) communication..."
  az network firewall policy rule-collection-group collection add-filter-collection \
    --collection-priority 150 \
    --name "AllowInterVNetCommunication" \
    --action Allow \
    --rule-name "AllowSpoke1ToSpoke2" \
    --rule-type NetworkRule \
    --description "Allow communication from spoke1 to spoke2" \
    --destination-addresses "10.2.0.0/22" \
    --destination-ports "*" \
    --ip-protocols "Any" \
    --source-addresses "10.1.0.0/22" "172.16.0.0/22" \
    --policy-name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --rule-collection-group-name "NetworkRuleCollectionGroup" >/dev/null

  # Add reverse rule for spoke2 to spoke1 communication  
  echo "Adding reverse rule for spoke2 to spoke1 communication..."
  az network firewall policy rule-collection-group collection add-filter-collection \
    --collection-priority 160 \
    --name "AllowSpoke2ToSpoke1" \
    --action Allow \
    --rule-name "AllowSpoke2ToSpoke1" \
    --rule-type NetworkRule \
    --description "Allow communication from spoke2 to spoke1" \
    --destination-addresses "10.1.0.0/22" "172.16.0.0/22" \
    --destination-ports "*" \
    --ip-protocols "Any" \
    --source-addresses "10.2.0.0/22" \
    --policy-name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --rule-collection-group-name "NetworkRuleCollectionGroup" >/dev/null

  # Create rule collection group for application rules
  echo "Creating application rule collection group..."
  az network firewall policy rule-collection-group create \
    --name "ApplicationRuleCollectionGroup" \
    --policy-name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --priority 200 >/dev/null

  # Create application rule collection for HTTP/HTTPS traffic from egress subnet
  echo "Creating application rule collection for web traffic..."
  az network firewall policy rule-collection-group collection add-filter-collection \
    --collection-priority 100 \
    --name "AllowEgressSubnetWeb" \
    --action Allow \
    --rule-name "AllowWebTrafficFromEgress" \
    --rule-type ApplicationRule \
    --description "Allow HTTP/HTTPS traffic from egress subnet" \
    --source-addresses "10.1.0.0/26" \
    --protocols "Http=80" "Https=443" \
    --target-fqdns "*" \
    --policy-name "${FIREWALL_NAME}-policy" \
    --resource-group $RESOURCE_GROUP \
    --rule-collection-group-name "ApplicationRuleCollectionGroup" >/dev/null

  # Display firewall information
  echo "Azure Firewall created successfully with the following configuration:"
  echo "  - Firewall Name: $FIREWALL_NAME"
  echo "  - Policy Name: ${FIREWALL_NAME}-policy"
  echo "  - Private IP: $fwprivaddr"
  echo "  - Public IP: $(az network public-ip show --name "${FIREWALL_NAME}-pip" --resource-group $RESOURCE_GROUP --query ipAddress -o tsv)"
  echo ""
  echo "🔥 Firewall Policy Rules (Hub and Spoke Model with Transitive Routing):"
  echo "  - Network Rules: Allow ALL outbound traffic ONLY from egress subnet (10.1.0.0/26)"
  echo "  - Application Rules: Allow HTTP/HTTPS traffic ONLY from egress subnet to any FQDN"
  echo "  - Inter-VNet Rules: Allow spoke1 (10.1.0.0/22 + 172.16.0.0/22) ↔ spoke2 (10.2.0.0/22) communication"
  echo "  - App subnet (172.16.1.0/24): BLOCKED by NSG - no firewall rules needed"
  echo "  - DNS Proxy: Enabled for DNS resolution"
  echo "  - Threat Intelligence: Enabled in Alert mode"
  echo ""
  echo "Firewall setup complete - ready to act as internet proxy AND transitive router for spoke-to-spoke communication."
}
function create_route_table() {
  # Create route table for egress subnet (routable through hub firewall)
  echo "Creating route table for egress subnet..."
  az network route-table create --name egress-route-table \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION >/dev/null

  # Wait for firewall to be fully provisioned and get the firewall private IP
  echo "Waiting for firewall to be fully provisioned..."
  FIREWALL_PRIVATE_IP=""
  retry_count=0
  max_retries=30
  
  while [ -z "$FIREWALL_PRIVATE_IP" ] && [ $retry_count -lt $max_retries ]; do
    echo "Attempting to retrieve firewall private IP (attempt $((retry_count + 1))/$max_retries)..."
    FIREWALL_PRIVATE_IP=$(az network firewall show --name $FIREWALL_NAME --resource-group $RESOURCE_GROUP --query "ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null)
    if [ -z "$FIREWALL_PRIVATE_IP" ] || [ "$FIREWALL_PRIVATE_IP" = "null" ]; then
      echo "Firewall not ready yet, waiting 10 seconds..."
      sleep 10
      retry_count=$((retry_count + 1))
      FIREWALL_PRIVATE_IP=""
    fi
  done
  
  if [ -z "$FIREWALL_PRIVATE_IP" ] || [ "$FIREWALL_PRIVATE_IP" = "null" ]; then
    echo "ERROR: Could not retrieve firewall private IP after $max_retries attempts"
    exit 1
  fi
  
  echo "Using firewall private IP: $FIREWALL_PRIVATE_IP"

  # Create a route to the firewall for internet traffic (egress subnet only)
  echo "Creating route to firewall for egress subnet..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name egress-route-table \
    --name to-firewall \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_PRIVATE_IP >/dev/null

  # Add route for spoke1 to spoke2 communication via firewall (transitive routing)
  echo "Creating route for spoke1 to spoke2 via firewall..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name egress-route-table \
    --name to-spoke2 \
    --address-prefix 10.2.0.0/22 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_PRIVATE_IP >/dev/null

  # Associate route table ONLY with egress subnet (making it routable through firewall)
  echo "Associating route table with egress subnet..."
  az network vnet subnet update --name egress-subnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --route-table egress-route-table >/dev/null

  # Create route table for app subnet (direct internet access + spoke2 via firewall)
  echo "Creating route table for app subnet (direct internet access + spoke2 via firewall)..."
  az network route-table create --name app-route-table \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION >/dev/null

  # Create route for app subnet to go directly to internet (no firewall)
  echo "Creating direct internet route for app subnet..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name app-route-table \
    --name to-internet \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type Internet >/dev/null

  # Add route for app subnet to spoke2 via firewall (transitive routing)
  echo "Creating route for app subnet to spoke2 via firewall..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name app-route-table \
    --name to-spoke2 \
    --address-prefix 10.2.0.0/22 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_PRIVATE_IP >/dev/null

  # Associate route table with app subnet for direct internet access + spoke2 routing
  echo "Associating direct internet route table with app subnet..."
  az network vnet subnet update --name app-subnet \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke1 \
    --route-table app-route-table >/dev/null

  # Create route table for spoke2 (for transitive routing back to spoke1)
  echo "Creating route table for spoke2 (transitive routing to spoke1)..."
  az network route-table create --name spoke2-route-table \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION >/dev/null

  # Add route for spoke2 to spoke1 via firewall (transitive routing)
  echo "Creating route for spoke2 to spoke1 via firewall..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name spoke2-route-table \
    --name to-spoke1-10x \
    --address-prefix 10.1.0.0/22 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_PRIVATE_IP >/dev/null

  # Add route for spoke2 to spoke1 172.16.x.x range via firewall (transitive routing)
  echo "Creating route for spoke2 to spoke1 172.16.x.x range via firewall..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name spoke2-route-table \
    --name to-spoke1-172x \
    --address-prefix 172.16.0.0/22 \
    --next-hop-type VirtualAppliance \
    --next-hop-ip-address $FIREWALL_PRIVATE_IP >/dev/null

  # Add route for spoke2 internet traffic directly (no firewall for internet)
  echo "Creating direct internet route for spoke2..."
  az network route-table route create --resource-group $RESOURCE_GROUP \
    --route-table-name spoke2-route-table \
    --name to-internet \
    --address-prefix 0.0.0.0/0 \
    --next-hop-type Internet >/dev/null

  # Associate route table with spoke2 subnet
  echo "Associating route table with spoke2 ACI subnet..."
  az network vnet subnet update --name aci-subnet-spoke2 \
    --resource-group $RESOURCE_GROUP \
    --vnet-name spoke2 \
    --route-table spoke2-route-table >/dev/null

  echo "Route table setup complete:"
  echo "  - Egress subnet: Routable through Azure Firewall (controlled access + spoke2 via firewall)"
  echo "  - App subnet: Direct internet access + spoke2 via firewall"
  echo "  - spoke2 subnet: Direct internet access + spoke1 via firewall"
  echo "  - Transitive routing enabled: spoke1 ↔ spoke2 via Azure Firewall"
}
## Create aks cluster with Cilium as the network dataplane
# Function to create the AKS cluster with Cilium as the network dataplane

create_aks_cluster() {
  echo "Creating AKS cluster with Cilium as the network dataplane..."
  az identity create --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --location $LOCATION

  # Get the identity resource ID
  IDENTITY_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
  echo "Managed Identity created successfully."
  principalId=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query principalId -o tsv)
  echo "Managed Identity Principal ID: $principalId"
  echo "Managed Identity Name: $IDENTITY_NAME"
  echo "Managed Identity ID: $IDENTITY_ID"
  sleep 30
  networkRGID=$(az group show --name $RESOURCE_GROUP --query id -o tsv)
  az role assignment create --role "Contributor" --assignee-object-id $principalId --scope $networkRGID --assignee-principal-type ServicePrincipal
  az role assignment create --role "Network Contributor" --assignee-object-id $principalId --scope $networkRGID --assignee-principal-type ServicePrincipal

  # Create the AKS cluster with no CNI
  az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --kubernetes-version $K8S_VERSION \
    --enable-managed-identity \
    --assign-identity $IDENTITY_ID \
    --assign-kubelet-identity $IDENTITY_ID \
    --node-vm-size $NODE_SIZE \
    --node-count $NODE_COUNT \
    --pod-cidr 192.168.0.0/16 \
    --generate-ssh-keys \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --vnet-subnet-id $APP_SUBNET_ID --enable-apiserver-vnet-integration \
    --apiserver-subnet-id $APISERVER_SUBNET_ID
  # assign Network Contributor role on scope networkResourceGroup and vmssResourceGroup to the identity
  echo "AKS cluster created successfully without CNI."
  vmssRGID=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query nodeResourceGroup -o tsv)
  rgid2=$(az group show --name $vmssRGID --query id -o tsv)
  echo "VMSS Resource Group ID: $vmssRGID"
  # Assign Network Contributor role to the managed identity
  ##  az role assignment create --role "Network Contributor" --assignee
  az role assignment create --role "Contributor" --assignee-object-id $principalId --scope $rgid2 --assignee-principal-type ServicePrincipal
  echo "Network Contributor role assigned to the managed identity."
  echo "AKS cluster with Cilium as the network dataplane created successfully."

}

display_architecture_summary() {
  echo ""
  echo "=============================================="
  echo "HUB AND SPOKE ARCHITECTURE SUMMARY"
  echo "=============================================="
  echo ""
  echo "🏢 HUB VNET (hub1 - 10.0.0.0/16):"
  echo "   ├── AzureFirewallSubnet (10.0.2.0/24) - Internet gateway"
  echo "   ├── AzureFirewallManagementSubnet (10.0.3.0/24) - Firewall management"
  echo "   ├── subnet-1 (10.0.1.0/24) - General hub subnet"
  echo "   ├── dns-inbound-subnet (10.0.10.0/28) - DNS resolver inbound"
  echo "   └── dns-outbound-subnet (10.0.20.0/28) - DNS resolver outbound"
  echo ""
  echo "🏭 SPOKE VNET (spoke1 - MULTI-ADDRESS SPACE):"
  echo "   ├── Address Space 1: 10.1.0.0/22 (Routable through firewall)"
  echo "   │   └── egress-subnet (10.1.0.0/26) - AKS egress nodes (FIREWALL ROUTED)"
  echo "   │       └── Routes traffic through Azure Firewall for controlled access"
  echo "   ├── Address Space 2: 172.16.0.0/22 (Non-routable private range)"
  echo "   │   ├── app-subnet (172.16.1.0/24) - AKS app nodes (DIRECT INTERNET ACCESS)"
  echo "   │   │   └── Routes traffic directly to internet (no firewall filtering)"
  echo "   │   ├── apiserver-subnet (172.16.2.0/28) - AKS API server"
  echo "   │   └── aci-subnet (172.16.3.0/24) - Container instances (unused)"
  echo ""
  echo "🏭 SPOKE VNET (spoke2 - 10.2.0.0/22):"
  echo "   └── aci-subnet-spoke2 (10.2.1.0/24) - ACI containers (ACTIVE DEPLOYMENT)"
  echo "       └── Full VNet peering with hub1 (transitive routing enabled)"
  echo ""
  echo "🔥 AZURE FIREWALL:"
  echo "   ├── Name: $FIREWALL_NAME"
  echo "   ├── Private IP: $(az network firewall show --name $FIREWALL_NAME --resource-group $RESOURCE_GROUP --query "ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null || echo 'Not available')"
  echo "   ├── Policy: Modern policy-based rules"
  echo "   └── Rules: Allow all outbound from egress subnet (10.1.0.0/26)"
  echo ""
  echo "🌐 CONNECTIVITY MODEL:"
  echo "   ├── App subnet (172.16.1.0/24) → DIRECT to Internet (no filtering)"
  echo "   ├── App subnet → spoke2 via Azure Firewall (transitive routing)"
  echo "   ├── Egress subnet (10.1.0.0/26) → Hub Firewall → Internet (controlled access)"
  echo "   ├── Egress subnet → spoke2 via Azure Firewall (transitive routing)"
  echo "   ├── spoke2 → spoke1 via Azure Firewall (transitive routing)"
  echo "   ├── spoke2 → Internet DIRECT (no filtering)"
  echo "   ├── Hub ↔ Spoke1: Full VNet peering"
  echo "   ├── Hub ↔ Spoke2: Full VNet peering (enables transitive routing)"
  echo "   └── **TRANSITIVE ROUTING ENABLED**: spoke1 ↔ spoke2 via Azure Firewall"
  echo ""
  echo "🚀 AKS CLUSTER:"
  echo "   ├── App nodes: Deploy in app-subnet (172.16.1.0/24) - direct internet access"
  echo "   ├── Egress nodes: Deploy in egress-subnet (10.1.0.0/26) - controlled via firewall"
  echo "   └── API server: Private endpoint in apiserver-subnet (172.16.2.0/28)"
  echo ""
  echo "🔗 MULTI-ADDRESS SPACE ARCHITECTURE:"
  echo "   ├── Purpose: Demonstrate routable vs non-routable address spaces"
  echo "   ├── 10.1.0.0/22: Routable range for egress traffic through firewall"
  echo "   ├── 172.16.0.0/22: Non-routable private range for app workloads"
  echo "   ├── Benefit: App workloads use private addressing while maintaining"
  echo "   │            controlled egress capability via dedicated subnet"
  echo "   └── Use Case: Segregate egress traffic from internal app communication"
  echo ""
  echo "🐳 ACI DEPLOYMENT:"
  echo "   ├── Private ACI: spoke2/aci-subnet-spoke2 (10.2.1.0/24)"
  echo "   │   ├── Container: $ACI_NAME (mendhak/http-https-echo:37)"
  echo "   │   └── Access: Via VNet peering through hub1"
  echo "   └── Public ACI: Internet-facing"
  echo "       ├── Container: $PUBLIC_ACI_NAME ($PUBLIC_ACI_IMAGE)"
  echo "       └── Access: Direct public internet access"
  echo ""
  echo "=============================================="
}

create_aci_container() {
  # Deploy container instance into spoke2 subnet with full VNet peering
  echo "Deploying ACI container to spoke2 subnet with full VNet peering to hub..."
  az container create \
    --name $ACI_NAME \
    --resource-group $RESOURCE_GROUP \
    --image mendhak/http-https-echo:37 \
    --vnet spoke2 \
    --subnet $ACI_SUBNET_SPOKE2_ID \
    --ports 8080 \
    --protocol TCP \
    --restart-policy OnFailure \
    --location $LOCATION \
    --ip-address Private --os-type linux --memory 1.5 --cpu 1

  az container show \
    --name $ACI_NAME \
    --resource-group $RESOURCE_GROUP \
    --query "ipAddress.ip" \
    --output tsv
  echo "Container instance $ACI_NAME created successfully in the spoke2 ACI subnet."
  echo "Container IP Address: $(az container show --name $ACI_NAME --resource-group $RESOURCE_GROUP --query "ipAddress.ip" --output tsv)"
  ## set the ip to a variable
  export ACI_IP=$(az container show --name $ACI_NAME --resource-group $RESOURCE_GROUP --query "ipAddress.ip" --output tsv)
  echo "ACI IP Address: $ACI_IP"
  echo "Container instance created successfully in the spoke2 ACI subnet with full VNet peering."

  # Deploy public ACI container for external testing
  echo ""
  echo "Deploying public ACI container for external connectivity testing..."
  az container create \
    --name $PUBLIC_ACI_NAME \
    --resource-group $RESOURCE_GROUP \
    --image $PUBLIC_ACI_IMAGE \
    --ports $PUBLIC_ACI_PORT \
    --protocol TCP \
    --restart-policy OnFailure \
    --location $LOCATION \
    --ip-address Public \
    --os-type linux \
    --memory 1.5 \
    --cpu 1

  # Get and display public ACI container details
  export PUBLIC_ACI_IP=$(az container show --name $PUBLIC_ACI_NAME --resource-group $RESOURCE_GROUP --query "ipAddress.ip" --output tsv)
  echo "Public ACI container $PUBLIC_ACI_NAME created successfully."
  echo "Public ACI IP Address: $PUBLIC_ACI_IP"
  echo "Public ACI endpoint: http://$PUBLIC_ACI_IP:$PUBLIC_ACI_PORT"
  echo ""
  echo "ACI Deployment Summary:"
  echo "  Private ACI (spoke2): $ACI_NAME @ $ACI_IP"
  echo "  Public ACI (internet): $PUBLIC_ACI_NAME @ $PUBLIC_ACI_IP:$PUBLIC_ACI_PORT"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 COMMAND LINE PARAMETER PARSING AND USAGE
# ═══════════════════════════════════════════════════════════════════════════════

# Default execution mode
EXECUTION_MODE="all"

# Usage function
show_usage() {
  echo ""
  echo "🏗️  HUB AND SPOKE AKS DEPLOYMENT SCRIPT"
  echo "═══════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "OPTIONS:"
  echo "  --step <step_name>    Execute a specific deployment step"
  echo "  --help, -h           Show this help message"
  echo ""
  echo "AVAILABLE STEPS:"
  echo "  networking           Create VNets, subnets, and VNet peering"
  echo "  firewall             Create Azure Firewall with policy rules"
  echo "  routes               Create route tables for traffic routing"
  echo "  summary              Display architecture summary"
  echo "  aks                  Create AKS cluster with Cilium CNI"
  echo "  workloads            Configure AKS access and create test workloads"
  echo "  aci                  Create ACI container instance in spoke2 with full VNet peering"
  echo "  egress-pool          Create egress node pool with gateway configuration"
  echo "  helm-values          Generate Helm values and install kube-egress-gateway"
  echo "  testdeploy            Template and install testdeploy.yaml for egress VMSS testing"
  echo "  all                  Execute all steps (default)"
  echo ""
  echo "EXAMPLES:"
  echo "  $0                           # Run all steps"
  echo "  $0 --step networking        # Run only networking step"
  echo "  $0 --step firewall          # Run only firewall step"
  echo "  $0 --step all               # Run all steps (explicit)"
  echo ""
  echo "ENVIRONMENT VARIABLES:"
  echo "  ENABLE_PROGRESS=true|false   Enable/disable progress tracking (default: true)"
  echo ""
  echo "RESOURCE CONFIGURATION:"
  echo "  PREFIX='$PREFIX'"
  echo "  RESOURCE_GROUP='$RESOURCE_GROUP'"
  echo "  CLUSTER_NAME='$CLUSTER_NAME'"
  echo "  LOCATION='$LOCATION'"
  echo ""
}

# Function to validate step name
validate_step() {
  local step="$1"
  case $step in
    networking|firewall|routes|summary|aks|workloads|aci|egress-pool|helm-values|testdeploy|all)
      return 0
      ;;
    *)
      echo "❌ ERROR: Invalid step '$step'"
      echo "Valid steps: networking, firewall, routes, summary, aks, workloads, aci, egress-pool, helm-values, testdeploy, all"
      exit 1
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 INDIVIDUAL STEP EXECUTION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Step 1: Create networking resources
execute_networking() {
  echo "🌐 Executing Step 1: Networking"
  az group create --name $RESOURCE_GROUP --location $LOCATION
  show_progress "Creating VNets, Subnets and VNet Peering"
  create_networking
  complete_step "Network Infrastructure Created"
}

# Step 2: Create firewall
execute_firewall() {
  echo "🔥 Executing Step 2: Azure Firewall"
  show_progress "Creating Azure Firewall with Policy-Based Rules"
  create_firewall
  complete_step "Azure Firewall Configured"
}

# Step 3: Create route tables
execute_routes() {
  echo "🛣️  Executing Step 3: Route Tables"
  show_progress "Retrieving Subnet IDs and Creating Route Tables"
  EGRESS_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name egress-subnet --query id -o tsv)
  APP_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name app-subnet --query id -o tsv)
  echo "Egress Subnet ID: $EGRESS_SUBNET_ID"
  echo "App Subnet ID: $APP_SUBNET_ID"
  
  # Create route table to direct traffic through firewall
  create_route_table
  complete_step "Route Tables Configured"
}

# Step 4: Display architecture summary
execute_summary() {
  echo "📋 Executing Step 4: Architecture Summary"
  show_progress "Displaying Architecture Summary"
  display_architecture_summary
  complete_step "Architecture Summary Displayed"
}

# Step 5: Create AKS cluster
execute_aks() {
  echo "☸️  Executing Step 5: AKS Cluster"
  # Ensure subnet IDs are available
  EGRESS_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name egress-subnet --query id -o tsv)
  APP_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name app-subnet --query id -o tsv)
  APISERVER_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name apiserver-subnet --query id -o tsv)
  
  show_progress "Creating AKS Cluster with Cilium CNI"
  create_aks_cluster
  complete_step "AKS Cluster Created"
}

# Step 6: Configure AKS access and create test workloads
execute_workloads() {
  echo "🚀 Executing Step 6: AKS Workloads"
  show_progress "Configuring AKS Access and Creating Test Workloads"
  az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing
  
  # Confirm nodes are running
  kubectl get nodes
  # Create NGINX deployment
  kubectl create deployment nginx-demo --image=nginx:latest --namespace=default
  kubectl scale deployment/nginx-demo --replicas=2 --namespace=default
  complete_step "AKS Access Configured and Test Workloads Deployed"
}

# Step 6a: Create ACI container instance for testing
execute_aci() {
  echo "🐳 Executing Step 6a: ACI Container Instance"
  # Ensure subnet ID is available for spoke2
  ACI_SUBNET_SPOKE2_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke2 --name aci-subnet-spoke2 --query id -o tsv)
  echo "ACI Subnet (spoke2) ID: $ACI_SUBNET_SPOKE2_ID"
  
  show_progress "Creating ACI Container Instance in spoke2 with full VNet peering"
  create_aci_container
  complete_step "ACI Container Instance Created in spoke2"
}
# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 HELM VALUES GENERATOR FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════
generate_helm_values() {
  # Purpose: Automatically generates helmosss/values.yaml from template with
  #          deployment-specific Azure configuration values
  #
  # Template: helmosss/values.template.yaml (with {{PLACEHOLDER}} tokens)
  # Output:   helmosss/values.yaml (with actual Azure values)
  #
  # Values Retrieved:
  #   - tenantId: Azure AD tenant from current CLI login
  #   - subscriptionId: Azure subscription from current CLI login  
  #   - userAssignedIdentityID: Managed identity client ID used by AKS node pools
  #   - resourceGroup: Resource group where AKS cluster is deployed
  #   - location: Azure region where resources are deployed
  #   - loadBalancerResourceGroup: AKS node resource group (where VMSS are deployed)
  #   - vnetName: VNet name (spoke1) containing the egress subnet
  #   - vnetResourceGroup: Resource group where VNet is deployed
  #
  # Usage: Called automatically during deployment after AKS cluster creation
  
  echo "Generating Helm values.yaml from template..."
  
  # ──────────────────────────────────────────────────────────────────────────────
  # 🔐 RETRIEVE AZURE CLI CONTEXT
  # ──────────────────────────────────────────────────────────────────────────────
  # Get tenant and subscription from current Azure CLI session
  TENANT_ID=$(az account show --query tenantId -o tsv)
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  
  # ──────────────────────────────────────────────────────────────────────────────
  # 🆔 RETRIEVE MANAGED IDENTITY INFORMATION
  # ──────────────────────────────────────────────────────────────────────────────
  # Get the client ID of the managed identity used by AKS node pools
  # This identity is used by the egress gateway to manage Azure resources
  MANAGED_IDENTITY_CLIENT_ID=$(az identity show --name $IDENTITY_NAME --resource-group $RESOURCE_GROUP --query clientId -o tsv)
  
  # ──────────────────────────────────────────────────────────────────────────────
  # 🏗️ RETRIEVE DEPLOYMENT RESOURCE INFORMATION
  # ──────────────────────────────────────────────────────────────────────────────
  # Get AKS node resource group where VMSS and load balancers are deployed
  VMSS_RESOURCE_GROUP=$(az aks show --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --query nodeResourceGroup -o tsv)
  
  # VNet configuration for egress gateway
  VNET_NAME="spoke1"                    # Spoke VNet containing egress subnet
  VNET_RESOURCE_GROUP="$RESOURCE_GROUP" # Resource group containing the VNet
  
  # ──────────────────────────────────────────────────────────────────────────────
  # 📋 DISPLAY RETRIEVED CONFIGURATION
  # ──────────────────────────────────────────────────────────────────────────────
  echo "Retrieved Azure configuration:"
  echo "  - Tenant ID: $TENANT_ID"
  echo "  - Subscription ID: $SUBSCRIPTION_ID"
  echo "  - Managed Identity Client ID: $MANAGED_IDENTITY_CLIENT_ID"
  echo "  - Resource Group: $RESOURCE_GROUP"
  echo "  - Location: $LOCATION"
  echo "  - VMSS Resource Group: $VMSS_RESOURCE_GROUP"
  echo "  - VNet Name: $VNET_NAME"
  echo "  - VNet Resource Group: $VNET_RESOURCE_GROUP"
  
  # ──────────────────────────────────────────────────────────────────────────────
  # 📝 GENERATE VALUES.YAML FROM TEMPLATE
  # ──────────────────────────────────────────────────────────────────────────────
  # Check if template file exists
  if [ -f "helmosss/values.template.yaml" ]; then
    # Copy template to working values.yaml file
    cp helmosss/values.template.yaml helmosss/values.yaml
    
    # Replace all template placeholders with actual values
    # Note: Using .bak extension for macOS compatibility with sed -i
    sed -i.bak "s/{{TENANT_ID}}/$TENANT_ID/g" helmosss/values.yaml
    sed -i.bak "s/{{SUBSCRIPTION_ID}}/$SUBSCRIPTION_ID/g" helmosss/values.yaml
    sed -i.bak "s/{{USER_ASSIGNED_IDENTITY_ID}}/$MANAGED_IDENTITY_CLIENT_ID/g" helmosss/values.yaml
    sed -i.bak "s/{{RESOURCE_GROUP}}/$RESOURCE_GROUP/g" helmosss/values.yaml
    sed -i.bak "s/{{LOCATION}}/$LOCATION/g" helmosss/values.yaml
    sed -i.bak "s/{{LOADBALANCER_RESOURCE_GROUP}}/$VMSS_RESOURCE_GROUP/g" helmosss/values.yaml
    sed -i.bak "s/{{VNET_NAME}}/$VNET_NAME/g" helmosss/values.yaml
    sed -i.bak "s/{{VNET_RESOURCE_GROUP}}/$VNET_RESOURCE_GROUP/g" helmosss/values.yaml
    
    # Clean up backup file created by sed
    rm helmosss/values.yaml.bak
    
    # ──────────────────────────────────────────────────────────────────────────────
    # ✅ SUCCESS CONFIRMATION
    # ──────────────────────────────────────────────────────────────────────────────
    echo "✅ Generated helmosss/values.yaml with current deployment values"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  - Azure Tenant: $TENANT_ID"
    echo "  - Subscription: $SUBSCRIPTION_ID"
    echo "  - Managed Identity: $MANAGED_IDENTITY_CLIENT_ID"
    echo "  - AKS Resource Group: $RESOURCE_GROUP"
    echo "  - VMSS Resource Group: $VMSS_RESOURCE_GROUP"
    echo "  - VNet: $VNET_NAME in $VNET_RESOURCE_GROUP"
    echo "  - Location: $LOCATION"
  else
    # ──────────────────────────────────────────────────────────────────────────────
    # ❌ ERROR HANDLING
    # ──────────────────────────────────────────────────────────────────────────────
    echo "❌ ERROR: Template file helmosss/values.template.yaml not found"
    echo "   Please ensure the template file exists before running this function"
    exit 1
  fi
}

# Step 7: Create egress node pool
execute_egress_pool() {
  echo "🏊 Executing Step 7: Egress Node Pool"
  # Ensure subnet ID is available
  EGRESS_SUBNET_ID=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name spoke1 --name egress-subnet --query id -o tsv)
  
  show_progress "Creating Egress Node Pool with Gateway Configuration"
  echo "Creating egress node pool..."
  az aks nodepool add --cluster-name $CLUSTER_NAME \
    --name egresspool2 \
    --zone 1 \
    --mode User \
    --resource-group $RESOURCE_GROUP \
    --node-vm-size $NODE_SIZE2 \
    --node-count 2 \
    --vnet-subnet-id $EGRESS_SUBNET_ID
  echo "Egress node pool created successfully."
  
  az aks nodepool update \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $CLUSTER_NAME \
    --name egresspool2 \
    --labels kubeegressgateway.azure.com/mode=true
  
  echo "Egress node pool updated with labels."
  az aks nodepool update \
    --resource-group $RESOURCE_GROUP \
    --cluster-name $CLUSTER_NAME \
    --name egresspool2 \
    --node-taints "kubeegressgateway.azure.com/mode=true:NoSchedule" \
    --no-wait
  complete_step "Egress Node Pool Created and Configured"
}

# Step 8: Generate Helm values and install kube-egress-gateway
execute_helm_values() {
  echo "⚙️  Executing Step 8: Helm Values and Chart Installation"
  
  # Step 8a: Generate Helm values
  show_progress "Generating Helm Values Configuration"
  generate_helm_values
  echo "✅ Helm values.yaml generated successfully"
  
  # Step 8b: Install the kube-egress-gateway Helm chart
  echo ""
  echo "🚀 Installing kube-egress-gateway Helm chart..."
  
  # Ensure kubectl context is set
  echo "Setting kubectl context..."
  az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --overwrite-existing >/dev/null
  
  # Install the Helm chart using the generated values file
  echo "Installing kube-egress-gateway from Azure repository..."
  
  helm install \
    --repo https://raw.githubusercontent.com/Azure/kube-egress-gateway/main/helm/repo \
    kube-egress-gateway --generate-name \
    --namespace kube-egress-gateway-system \
    --create-namespace \
    --set common.imageRepository=mcr.microsoft.com/aks \
    --set common.imageTag=v0.0.21 \
    -f helmosss/values.yaml
  
  # Check installation status
  if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Helm chart installed successfully!"
    echo ""
    echo "📋 Verifying installation..."
    
    # Wait a moment for pods to start
    sleep 10
    
    # Show pod status
    echo "🔍 Checking pod status in kube-egress-gateway-system namespace:"
    kubectl get pods -n kube-egress-gateway-system
    
    echo ""
    echo "🔍 Checking services in kube-egress-gateway-system namespace:"
    kubectl get svc -n kube-egress-gateway-system
    
    echo ""
    echo "📝 To check logs, use:"
    echo "   kubectl logs -n kube-egress-gateway-system -l app.kubernetes.io/name=kube-egress-gateway"
    
  else
    echo "❌ ERROR: Helm chart installation failed"
    echo "Please check the error messages above and verify:"
    echo "  - Helm is installed and available"
    echo "  - kubectl context is correctly set"
    echo "  - values.yaml file was generated correctly"
    exit 1
  fi
  
  complete_step "Helm Values Generated and Chart Installed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 TESTDEPLOY YAML TEMPLATING AND INSTALL FUNCTION
# ═══════════════════════════════════════════════════════════════════════════════
install_testdeploy_yaml() {
  # Purpose: Fill in VMSS resource group and name in testdeploy.yaml and apply to Kubernetes
  #
  # Template: testdeploy.yaml (with {{VMSS_RESOURCE_GROUP}} and {{VMSS_NAME}})
  # Output:   testdeploy.generated.yaml
  #
  # 1. Get VMSS resource group and name from AKS
  # 2. Replace placeholders in template
  # 3. Apply to Kubernetes

  echo "Generating and applying testdeploy.yaml with current VMSS values..."

  # Get AKS node resource group (where VMSS is deployed)
  VMSS_RESOURCE_GROUP=$(az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --query nodeResourceGroup -o tsv)

  # Find the egress VMSS name (assumes name contains 'egresspool2')
  VMSS_NAME=$(az vmss list -g "$VMSS_RESOURCE_GROUP" --query "[?contains(name, 'egresspool2')].name | [0]" -o tsv)

  if [[ -z "$VMSS_NAME" ]]; then
    echo "❌ ERROR: Could not find egress VMSS in resource group $VMSS_RESOURCE_GROUP"
    exit 1
  fi

  # Copy template to working file
  cp testdeploy.yaml testdeploy.generated.yaml

  # Replace placeholders
  sed -i.bak "s/{{VMSS_RESOURCE_GROUP}}/$VMSS_RESOURCE_GROUP/g" testdeploy.generated.yaml
  sed -i.bak "s/{{VMSS_NAME}}/$VMSS_NAME/g" testdeploy.generated.yaml
  rm testdeploy.generated.yaml.bak

  echo "Applying testdeploy.generated.yaml to Kubernetes..."
  kubectl apply -f testdeploy.generated.yaml
  if [[ $? -eq 0 ]]; then
    echo "✅ testdeploy.yaml applied successfully!"
    echo "  - VMSS Resource Group: $VMSS_RESOURCE_GROUP"
    echo "  - VMSS Name: $VMSS_NAME"
  else
    echo "❌ ERROR: Failed to apply testdeploy.yaml"
    exit 1
  fi
}
# Step 9: Template and install testdeploy.yaml
execute_testdeploy() {
  echo "🧪 Executing Step: Testdeploy YAML"
  show_progress "Templating and Installing testdeploy.yaml"
  install_testdeploy_yaml
  complete_step "testdeploy.yaml Installed"
}
# Execute all steps
execute_all() {
  echo "🎯 Executing All Steps"
  execute_networking
  execute_firewall
  execute_routes
  execute_summary
  execute_aks
  execute_workloads
  execute_aci
  execute_egress_pool
  execute_helm_values
  execute_testdeploy
  
  show_progress "Deployment Complete - Final Summary"
  echo ""
  echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY! 🎉"
  echo ""
  echo "📊 Summary:"
  echo "   ✅ Hub and Spoke VNets created"
  echo "   ✅ Azure Firewall configured with policy-based rules"
  echo "   ✅ Route tables configured for two-tier access"
  echo "   ✅ AKS cluster deployed with Cilium CNI"
  echo "   ✅ ACI container deployed to spoke2 with subnet-level peering"
  echo "   ✅ Egress node pool configured"
  echo "   ✅ Test workloads deployed"
  echo "   ✅ Kube-egress-gateway Helm chart installed"
  echo "   ✅ testdeploy.yaml templated and applied"
  echo ""
  echo "🌐 Access Information:"
  echo "   • Resource Group: $RESOURCE_GROUP"
  echo "   • AKS Cluster: $CLUSTER_NAME"
  echo "   • Firewall: $FIREWALL_NAME"
  echo "   • Location: $LOCATION"
  echo ""
  echo "🔗 Network Configuration:"
  echo "   • Spoke1 VNet: Multi-address space (10.1.0.0/22 + 172.16.0.0/22)"
  echo "   • Egress Subnet: 10.1.0.0/26 (routable through firewall)"
  echo "   • App Subnet: 172.16.1.0/24 (non-routable, direct internet)"
  echo "   • API Server: 172.16.2.0/28 (private endpoint)"
  echo "   • Spoke2 VNet: 10.2.0.0/22 (transitive routing enabled)"
  echo ""
  echo "💡 Next Steps:"
  echo "   1. Test connectivity from both node pools"
  echo "   2. Deploy your applications to appropriate subnets"
  echo "   3. Monitor firewall logs for egress traffic"
  echo "   4. Use helmosss/values.yaml for Helm deployment"
  echo ""
  complete_step "Hub and Spoke AKS Architecture Deployment"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 COMMAND LINE ARGUMENT PARSING
# ═══════════════════════════════════════════════════════════════════════════════

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --step)
      EXECUTION_MODE="$2"
      shift 2
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Validate the execution mode
validate_step "$EXECUTION_MODE"

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN EXECUTION LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

# Reset progress tracking for individual steps
if [[ "$EXECUTION_MODE" != "all" ]]; then
  TOTAL_STEPS=1
  CURRENT_STEP=0
fi

# Execute the requested step(s)
case $EXECUTION_MODE in
  networking)
    execute_networking
    ;;
  firewall)
    execute_firewall
    ;;
  routes)
    execute_routes
    ;;
  summary)
    execute_summary
    ;;
  aks)
    execute_aks
    ;;
  workloads)
    execute_workloads
    ;;
  aci)
    execute_aci
    ;;
  egress-pool)
    execute_egress_pool
    ;;
  helm-values)
    execute_helm_values
    ;;
  testdeploy)
    execute_testdeploy
    ;;
  all)
    execute_all
    ;;
  *)
    echo "❌ ERROR: Invalid execution mode '$EXECUTION_MODE'"
    show_usage
    exit 1
    ;;
esac


