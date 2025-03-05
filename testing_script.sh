#!/bin/sh

# ------------------------------------------------------------
# Test Script: test_opnsense_aliases.sh
# Author: Joshua Porrata
# Date Created: March 4, 2025
# Last Updated: March 4, 2025
# Contact: joshua@rpdigitalconsulting.com
#
# Description:
# This script tests OPNsense firewall alias functionality.
# - Verifies alias creation & deletion using API calls.
# - Checks if production aliases match the expected list.
# - Reloads firewall rules to ensure changes take effect.
#
# Requirements:
# - OPNsense API key and secret with firewall alias permissions.
# - API access to OPNsense's firewall alias management.
# - Script must be executable: chmod +x test_opnsense_aliases.sh
# - Run as root or a user with the required API permissions.
# ------------------------------------------------------------

# OPNsense API Base URL
API_BASE="https://127.0.0.1/api/firewall/alias"

# API Key & Secret (Replace with your credentials)
API_KEY="your_api_key"
API_SECRET="your_api_secret"

# Log file
TEST_LOG="/var/log/opnsense_alias_test.log"

# Expected Aliases List
EXPECTED_ALIASES="Test_Alias_One Test_Alias_Two"

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

log_entry() {
    echo "$(timestamp) $1" | tee -a "$TEST_LOG"
}

# Function to create a test alias
create_test_alias() {
    ALIAS_NAME=$1
    PORTS=$2
    DESC=$3

    log_entry "➕ Creating test alias: $ALIAS_NAME"

    RESPONSE=$(curl -s -X POST "$API_BASE/addAlias" \
        -u "$API_KEY:$API_SECRET" \
        -H "Content-Type: application/json" \
        -d '{
            "enabled": "1",
            "name": "'"$ALIAS_NAME"'",
            "type": "port",
            "content": "'"$PORTS"'",
            "description": "'"$DESC"'"
        }')

    if echo "$RESPONSE" | grep -q '"result":"saved"'; then
        log_entry "✅ Successfully created alias: $ALIAS_NAME"
    else
        log_entry "❌ Error creating alias: $ALIAS_NAME"
        log_entry "Response: $RESPONSE"
    fi
}

# Function to delete a test alias
delete_test_alias() {
    ALIAS_NAME=$1

    log_entry "🗑️ Deleting test alias: $ALIAS_NAME"

    RESPONSE=$(curl -s -X POST "$API_BASE/delAlias" \
        -u "$API_KEY:$API_SECRET" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'"$ALIAS_NAME"'"
        }')

    if echo "$RESPONSE" | grep -q '"result":"deleted"'; then
        log_entry "✅ Successfully deleted alias: $ALIAS_NAME"
    else
        log_entry "❌ Error deleting alias: $ALIAS_NAME"
        log_entry "Response: $RESPONSE"
    fi
}

# Function to check if all expected aliases exist
check_aliases() {
    log_entry "🔍 Checking if expected aliases exist in production..."

    EXISTING_ALIASES=$(curl -s -X GET "$API_BASE/searchAlias" \
        -u "$API_KEY:$API_SECRET" \
        -H "Content-Type: application/json" | jq -r '.rows[].name')

    for ALIAS in $EXPECTED_ALIASES; do
        if echo "$EXISTING_ALIASES" | grep -q "\b$ALIAS\b"; then
            log_entry "✅ Alias '$ALIAS' exists as expected."
        else
            log_entry "⚠️ Alias '$ALIAS' is missing from production!"
        fi
    done
}

# Function to reload OPNsense firewall rules
reload_firewall() {
    log_entry "🔄 Reloading firewall rules..."
    configctl firewall reload
    log_entry "✅ Firewall rules reloaded successfully."
}

# Run Tests
log_entry "🚀 Starting OPNsense alias test..."

# Step 1: Create test aliases
create_test_alias "Test_Alias_One" "8080,8443" "Test alias for HTTP/S services"
create_test_alias "Test_Alias_Two" "22,2222" "Test alias for SSH"

# Step 2: Check if aliases exist
check_aliases

# Step 3: Reload firewall rules
reload_firewall

# Step 4: Delete test aliases
delete_test_alias "Test_Alias_One"
delete_test_alias "Test_Alias_Two"

# Step 5: Check again to verify deletion
check_aliases

log_entry "🏁 OPNsense alias test completed."
