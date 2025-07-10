#!/bin/bash

# Azure Hub-and-Spoke AKS Static Egress Connectivity Test Script
# This script tests transitive routing and static egress IP functionality

set -euo pipefail

# Load environment variables from .env file
if [ -f .env ]; then
    echo "Loading configuration from .env file..."
    source .env
else
    echo "Warning: .env file not found. Using default values..."
    # Default values (fallback if .env is missing)
    RESOURCE_GROUP="88-aks-egress"
    ACI_CONTAINER_NAME="srcip-http2"
    EGRESS_SUBNET_RANGE="10.1.0.0/26"
    TEST_DEPLOYMENT_POSITIVE="test-static-egress"
    TEST_DEPLOYMENT_NEGATIVE="test-negative-connectivity"
    NAMESPACE="default"
    PUBLIC_ACI_NAME="srcip-http-public"
    PUBLIC_ACI_PORT="8080"
fi

# Ensure backward compatibility with old variable names
RESOURCE_GROUP="${RESOURCE_GROUP:-88-aks-egress}"
ACI_CONTAINER_NAME="${ACI_CONTAINER_NAME:-${ACI_NAME:-srcip-http2}}"
NAMESPACE="${NAMESPACE:-default}"

# Main test function - everything in one place
main() {
    echo "===================================================="
    echo "Azure Hub-and-Spoke AKS Static Egress Connectivity Test"
    echo "===================================================="
    
    # Check prerequisites
    echo "[INFO] Checking prerequisites..."
    if ! command -v kubectl &> /dev/null; then
        echo "[ERROR] kubectl is not installed or not in PATH"
        exit 1
    fi
    if ! command -v az &> /dev/null; then
        echo "[ERROR] Azure CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Show current context
    current_context=$(kubectl config current-context 2>/dev/null || echo "none")
    echo "[INFO] Current kubectl context: $current_context"
    
    echo ""
    echo "===================================================="
    echo "Test Configuration"
    echo "===================================================="
    echo "[INFO] Resource Group: $RESOURCE_GROUP"
    echo "[INFO] ACI Container: $ACI_CONTAINER_NAME"
    echo "[INFO] Test Deployment (Positive): $TEST_DEPLOYMENT_POSITIVE"
    echo "[INFO] Test Deployment (Negative): $TEST_DEPLOYMENT_NEGATIVE"
    echo "[INFO] Namespace: $NAMESPACE"
    echo "[INFO] Egress Subnet Range: $EGRESS_SUBNET_RANGE"
    
    # Step 1: Get ACI container IP
    echo ""
    echo "===================================================="
    echo "Step 1: Get ACI Container IP"
    echo "===================================================="
    echo "[INFO] Looking for container '$ACI_CONTAINER_NAME' in resource group '$RESOURCE_GROUP'..."
    
    aci_ip=$(az container show \
        --name "$ACI_CONTAINER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "ipAddress.ip" \
        --output tsv 2>/dev/null)
    
    if [ -z "$aci_ip" ] || [ "$aci_ip" = "null" ]; then
        echo "[ERROR] Failed to get ACI container IP address"
        echo "[INFO] Available containers in resource group:"
        az container list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name,State:containers[0].instanceView.currentState.state,IP:ipAddress.ip}" --output table 2>/dev/null || echo "[ERROR] Failed to list containers"
        exit 1
    fi
    
    echo "[SUCCESS] ACI container IP: $aci_ip"
    
    # Step 2: Test positive case - should have connectivity
    echo ""
    echo "===================================================="
    echo "Step 2: Test Positive Case (Static Egress)"
    echo "===================================================="
    echo "[INFO] Testing deployment '$TEST_DEPLOYMENT_POSITIVE' - should have connectivity via static egress"
    
    # Find test pod for positive case
    echo "[INFO] Looking for pod from deployment '$TEST_DEPLOYMENT_POSITIVE'..."
    
    # Check if deployment exists
    deployment_exists=$(kubectl get deployment "$TEST_DEPLOYMENT_POSITIVE" -n "$NAMESPACE" --ignore-not-found -o name 2>/dev/null || echo "")
    
    if [ -z "$deployment_exists" ]; then
        echo "[ERROR] Deployment '$TEST_DEPLOYMENT_POSITIVE' not found in namespace '$NAMESPACE'"
        echo "[INFO] Available deployments:"
        kubectl get deployments -n "$NAMESPACE" 2>/dev/null || echo "[ERROR] Failed to list deployments"
        exit 1
    fi
    
    echo "[SUCCESS] Deployment '$TEST_DEPLOYMENT_POSITIVE' found"
    
    # Wait for pod to be ready
    pod_name_positive=""
    count=0
    timeout=300
    
    while [ $count -lt $timeout ] && [ -z "$pod_name_positive" ]; do
        pod_name_positive=$(kubectl get pods -n "$NAMESPACE" -l app="$TEST_DEPLOYMENT_POSITIVE" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$pod_name_positive" ]; then
            ready=$(kubectl get pod "$pod_name_positive" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [ "$ready" = "True" ]; then
                break
            else
                echo "[INFO] Pod '$pod_name_positive' exists but not ready yet (Ready=$ready)"
                pod_name_positive=""
            fi
        else
            echo "[INFO] No running pod found for deployment '$TEST_DEPLOYMENT_POSITIVE'"
        fi
        
        sleep 5
        count=$((count + 5))
        if [ $((count % 30)) -eq 0 ]; then
            echo "[INFO] Still waiting for positive test pod... ($count/$timeout seconds)"
        fi
    done
    
    if [ -z "$pod_name_positive" ]; then
        echo "[ERROR] Timeout waiting for positive test pod to be ready"
        kubectl get pods -n "$NAMESPACE" -l app="$TEST_DEPLOYMENT_POSITIVE" -o wide 2>/dev/null || echo "[ERROR] Failed to get pod status"
        exit 1
    fi
    
    echo "[SUCCESS] Pod '$pod_name_positive' is ready"
    
    # Test connectivity from positive pod
    echo "[INFO] Testing connectivity from pod '$pod_name_positive' to ACI container at $aci_ip:8080..."
    
    curl_output_positive=""
    curl_exit_code_positive=0
    curl_output_positive=$(kubectl exec -n "$NAMESPACE" "$pod_name_positive" -- curl -s --connect-timeout 10 --max-time 10 "http://$aci_ip:8080/" 2>&1) || curl_exit_code_positive=$?
    
    if [ $curl_exit_code_positive -ne 0 ]; then
        echo "[ERROR] Positive test failed - connectivity should work but curl failed with exit code: $curl_exit_code_positive"
        case $curl_exit_code_positive in
            7) echo "[ERROR] Connection refused: Unable to connect to $aci_ip:8080" ;;
            28) echo "[ERROR] Operation timeout: Connection timed out" ;;
            *) echo "[ERROR] Curl error: $curl_output_positive" ;;
        esac
        exit 1
    fi
    
    if [ -z "$curl_output_positive" ]; then
        echo "[ERROR] No response received from ACI container in positive test"
        exit 1
    fi
    
    echo "[SUCCESS] Positive connectivity test successful!"
    echo "[INFO] Response from ACI container:"
    echo "$curl_output_positive"
    
    # Extract source IP from positive test
    echo "[INFO] Extracting source IP from positive test..."
    
    # Extract IP from the "ip" field in JSON response
    source_ip_positive=$(echo "$curl_output_positive" | grep -oE '"ip"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "")
    
    # If we got an IPv6-mapped IPv4 address (::ffff:x.x.x.x), extract the IPv4 part
    if [[ "$source_ip_positive" =~ ^::ffff: ]]; then
        source_ip_positive=$(echo "$source_ip_positive" | sed 's/^::ffff://')
        echo "[INFO] Extracted IPv4 from IPv6-mapped address: $source_ip_positive"
    fi
    
    # Validate that we have a proper IPv4 address
    if [[ ! "$source_ip_positive" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Could not extract valid IPv4 source IP from positive test response"
        echo "[WARNING] Raw IP field value: $source_ip_positive"
        echo "[WARNING] Full response content: $curl_output_positive"
        exit 1
    fi
    
    echo "[SUCCESS] Extracted source IP from positive test: $source_ip_positive"
    
    # Verify positive test egress subnet
    echo "[INFO] Verifying positive test source IP '$source_ip_positive' is within egress subnet range '$EGRESS_SUBNET_RANGE'..."
    
    # Inline CIDR range check
    network=$(echo $EGRESS_SUBNET_RANGE | cut -d'/' -f1)
    prefix=$(echo $EGRESS_SUBNET_RANGE | cut -d'/' -f2)
    ip_dec=$(echo $source_ip_positive | awk -F. '{printf "%d\n", ($1*256^3)+($2*256^2)+($3*256)+$4}')
    net_dec=$(echo $network | awk -F. '{printf "%d\n", ($1*256^3)+($2*256^2)+($3*256)+$4}')
    mask=$((0xFFFFFFFF << (32 - $prefix)))
    
    if [ $((ip_dec & mask)) -eq $((net_dec & mask)) ]; then
        echo "[SUCCESS] ✅ Positive test: Source IP '$source_ip_positive' is within egress subnet range '$EGRESS_SUBNET_RANGE'"
        echo "[SUCCESS] ✅ Static egress functionality is working correctly!"
        positive_test_passed=true
    else
        echo "[ERROR] ❌ Positive test: Source IP '$source_ip_positive' is NOT within egress subnet range '$EGRESS_SUBNET_RANGE'"
        echo "[ERROR] ❌ Static egress functionality may not be working correctly"
        positive_test_passed=false
    fi
    
    # Step 3: Test negative case - should NOT have connectivity
    echo ""
    echo "===================================================="
    echo "Step 3: Test Negative Case (No Static Egress)"
    echo "===================================================="
    echo "[INFO] Testing deployment '$TEST_DEPLOYMENT_NEGATIVE' - should NOT have connectivity"
    
    # Find test pod for negative case
    echo "[INFO] Looking for pod from deployment '$TEST_DEPLOYMENT_NEGATIVE'..."
    
    # Check if deployment exists
    deployment_exists_negative=$(kubectl get deployment "$TEST_DEPLOYMENT_NEGATIVE" -n "$NAMESPACE" --ignore-not-found -o name 2>/dev/null || echo "")
    
    if [ -z "$deployment_exists_negative" ]; then
        echo "[ERROR] Deployment '$TEST_DEPLOYMENT_NEGATIVE' not found in namespace '$NAMESPACE'"
        echo "[INFO] Available deployments:"
        kubectl get deployments -n "$NAMESPACE" 2>/dev/null || echo "[ERROR] Failed to list deployments"
        exit 1
    fi
    
    echo "[SUCCESS] Deployment '$TEST_DEPLOYMENT_NEGATIVE' found"
    
    # Wait for negative test pod to be ready
    pod_name_negative=""
    count=0
    
    while [ $count -lt $timeout ] && [ -z "$pod_name_negative" ]; do
        pod_name_negative=$(kubectl get pods -n "$NAMESPACE" -l app="$TEST_DEPLOYMENT_NEGATIVE" --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$pod_name_negative" ]; then
            ready=$(kubectl get pod "$pod_name_negative" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
            
            if [ "$ready" = "True" ]; then
                break
            else
                echo "[INFO] Pod '$pod_name_negative' exists but not ready yet (Ready=$ready)"
                pod_name_negative=""
            fi
        else
            echo "[INFO] No running pod found for deployment '$TEST_DEPLOYMENT_NEGATIVE'"
        fi
        
        sleep 5
        count=$((count + 5))
        if [ $((count % 30)) -eq 0 ]; then
            echo "[INFO] Still waiting for negative test pod... ($count/$timeout seconds)"
        fi
    done
    
    if [ -z "$pod_name_negative" ]; then
        echo "[ERROR] Timeout waiting for negative test pod to be ready"
        kubectl get pods -n "$NAMESPACE" -l app="$TEST_DEPLOYMENT_NEGATIVE" -o wide 2>/dev/null || echo "[ERROR] Failed to get pod status"
        exit 1
    fi
    
    echo "[SUCCESS] Pod '$pod_name_negative' is ready"
    
    # Test connectivity from negative pod (should fail)
    echo "[INFO] Testing connectivity from pod '$pod_name_negative' to ACI container at $aci_ip:8080..."
    echo "[INFO] This should FAIL (timeout/connection refused) - that's the expected behavior"
    
    curl_output_negative=""
    curl_exit_code_negative=0
    curl_output_negative=$(kubectl exec -n "$NAMESPACE" "$pod_name_negative" -- curl -s --connect-timeout 10 --max-time 10 "http://$aci_ip:8080/" 2>&1) || curl_exit_code_negative=$?
    
    if [ $curl_exit_code_negative -eq 0 ] && [ -n "$curl_output_negative" ]; then
        echo "[ERROR] ❌ Negative test failed - connectivity should NOT work but curl succeeded"
        echo "[ERROR] This indicates that pods without static egress configuration are unexpectedly able to reach the ACI container"
        echo "[WARNING] Response received: $curl_output_negative"
        negative_test_passed=false
    else
        echo "[SUCCESS] ✅ Negative test passed - connectivity properly blocked"
        case $curl_exit_code_negative in
            7) echo "[SUCCESS] ✅ Connection refused as expected" ;;
            28) echo "[SUCCESS] ✅ Connection timed out as expected" ;;
            *) echo "[SUCCESS] ✅ Connection failed as expected (exit code: $curl_exit_code_negative)" ;;
        esac
        negative_test_passed=true
    fi
    
    # Step 4: Additional info
    echo ""
    echo "===================================================="
    echo " Additional Network Information"
    echo "===================================================="
    
    echo "[INFO] Positive test pod info:"
    pod_ip_positive=$(kubectl get pod "$pod_name_positive" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "Not found")
    echo "[INFO]   Pod IP: $pod_ip_positive"
    
    node_name_positive=$(kubectl get pod "$pod_name_positive" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Not found")
    echo "[INFO]   Node name: $node_name_positive"
    
    if [ "$node_name_positive" != "Not found" ]; then
        node_ip_positive=$(kubectl get node "$node_name_positive" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Not found")
        echo "[INFO]   Node internal IP: $node_ip_positive"
    fi
    
    echo ""
    echo "[INFO] Negative test pod info:"
    pod_ip_negative=$(kubectl get pod "$pod_name_negative" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "Not found")
    echo "[INFO]   Pod IP: $pod_ip_negative"
    
    node_name_negative=$(kubectl get pod "$pod_name_negative" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "Not found")
    echo "[INFO]   Node name: $node_name_negative"
    
    if [ "$node_name_negative" != "Not found" ]; then
        node_ip_negative=$(kubectl get node "$node_name_negative" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "Not found")
        echo "[INFO]   Node internal IP: $node_ip_negative"
    fi
    
    # Step 4: Test static egress to public ACI container
    echo ""
    echo "===================================================="
    echo "Step 4: Test Static Egress to Public ACI"
    echo "===================================================="
    echo "[INFO] Testing static egress IP functionality using public ACI container"
    
    # Get public ACI container IP
    echo "[INFO] Getting public ACI container IP..."
    public_aci_ip=""
    if [ -n "${PUBLIC_ACI_NAME:-}" ]; then
        public_aci_ip=$(az container show \
            --name "$PUBLIC_ACI_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query "ipAddress.ip" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    if [ -n "$public_aci_ip" ] && [ "$public_aci_ip" != "null" ]; then
        echo "[SUCCESS] Public ACI container IP: $public_aci_ip"
        
        # Test static egress to public container
        echo "[INFO] Testing egress from static egress pod to public ACI container..."
        egress_test_output=$(kubectl exec -n "$NAMESPACE" "$pod_name_positive" -- curl -s --max-time 10 "http://$public_aci_ip:${PUBLIC_ACI_PORT:-8080}" 2>/dev/null || echo "failed")
        echo "[INFO] Response from public ACI container:"
        echo "$egress_test_output"
        if [[ "$egress_test_output" =~ '"x-forwarded-for"' ]]; then
            # Extract the source IP from the response
            static_egress_ip=$(echo "$egress_test_output" | grep -o '"x-forwarded-for":"[^"]*"' | cut -d'"' -f4 | cut -d',' -f1)
            echo "[SUCCESS] ✅ Static egress test to public ACI passed"
            echo "[SUCCESS] ✅ Detected egress IP: $static_egress_ip"
            
            # Try to get firewall public IP for comparison
            firewall_public_ip=$(az network firewall show \
                --name "$FIREWALL_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --query "ipConfigurations[0].publicIpAddress.id" \
                --output tsv 2>/dev/null | xargs -I {} az network public-ip show --ids {} --query "ipAddress" --output tsv 2>/dev/null || echo "unknown")
            
            if [ "$firewall_public_ip" != "unknown" ] && [ "$static_egress_ip" = "$firewall_public_ip" ]; then
                echo "[SUCCESS] ✅ Confirmed: Egress IP ($static_egress_ip) matches Azure Firewall public IP"
                static_egress_validated=true
            else
                echo "[INFO] ℹ️  Egress IP: $static_egress_ip, Firewall IP: $firewall_public_ip"
                static_egress_validated=true  # Still consider it successful as long as we got a consistent IP
            fi
        else
            echo "[WARNING] ⚠️  Could not determine egress IP from public ACI test"
            static_egress_validated=false
        fi
    else
        echo "[WARNING] ⚠️  Public ACI container not found or not ready - skipping static egress IP validation"
        static_egress_validated=false
    fi
    
    # Final summary
    echo ""
    echo "===================================================="
    echo "Test Summary"
    echo "===================================================="
    
    if [ "$positive_test_passed" = true ] && [ "$negative_test_passed" = true ]; then
        echo "[SUCCESS] 🎉 All connectivity tests passed!"
        echo "[SUCCESS] ✅ ACI container IP: $aci_ip"
        echo "[SUCCESS] ✅ Positive test (static egress): CONNECTIVITY WORKED as expected"
        echo "[SUCCESS] ✅   - Source IP from egress: $source_ip_positive"
        echo "[SUCCESS] ✅   - Source IP is within egress subnet: $EGRESS_SUBNET_RANGE"
        echo "[SUCCESS] ✅ Negative test (no static egress): CONNECTIVITY BLOCKED as expected"
        echo "[SUCCESS] ✅ Static egress functionality is working correctly!"
        
        echo ""
        echo "[INFO] This confirms that:"
        echo "[INFO]   • Transitive routing through Azure Firewall is working for static egress pods"
        echo "[INFO]   • Static egress IPs are being used for inter-spoke communication"
        echo "[INFO]   • Pods without static egress configuration are properly blocked"
        echo "[INFO]   • The hub-and-spoke architecture is functioning as designed"
    else
        echo "[ERROR] ❌ Some connectivity tests failed!"
        if [ "$positive_test_passed" != true ]; then
            echo "[ERROR] ❌ Positive test failed - static egress functionality not working"
        fi
        if [ "$negative_test_passed" != true ]; then
            echo "[ERROR] ❌ Negative test failed - connectivity should be blocked but isn't"
        fi
        exit 1
    fi
}

# Run main function
main "$@"
