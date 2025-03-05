#!/bin/sh

# ------------------------------------------------------------
# Script: add_ports.sh
# Author: Joshua Porrata
# Date Created: March 4, 2025
# Last Updated: March 4, 2025
# Contact: joshua@rpdigitalconsulting.com
#
# Description:
# This script automates adding firewall aliases to an OPNsense system.
# - Creates a **backup** of existing aliases before modifying them.
# - Ensures **drift detection**, checking if production matches the standard.
# - Updates existing aliases while **preserving fields like color & category**.
#
# Requirements:
# - OPNsense API key and secret with firewall alias permissions.
# - API access to OPNsense's firewall alias management.
# - Script must be executable. Use:
#   chmod +x add_ports.sh
# - Run as root or a user with the required API permissions.
# ------------------------------------------------------------

# OPNsense API Base URL
API_BASE="https://127.0.0.1/api/firewall/alias"

# API Key & Secret (Replace with your credentials)
API_KEY="your_api_key"
API_SECRET="your_api_secret"

# Log files
ERROR_LOG="/var/log/port_alias_errors.log"
SUCCESS_LOG="/var/log/port_alias_success.log"
DRIFT_LOG="/var/log/port_alias_drift.log"

# Backup Directory
BACKUP_DIR="/var/backups/opnsense_aliases"
mkdir -p "$BACKUP_DIR"

# Timestamp function
timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

# Function to create a backup of current aliases
backup_aliases() {
    BACKUP_FILE="$BACKUP_DIR/port_alias_backup_$(date +%Y%m%d_%H%M%S).json"

    RESPONSE=$(curl -s -X GET "$API_BASE/searchAlias" \
        -u "$API_KEY:$API_SECRET" \
        -H "Content-Type: application/json")

    echo "$RESPONSE" > "$BACKUP_FILE"
    echo "$(timestamp) 📂 Backup saved: $BACKUP_FILE" | tee -a "$SUCCESS_LOG"

    # Keep only the last 20 backups
    BACKUPS=$(ls -tp "$BACKUP_DIR"/port_alias_backup_*.json 2>/dev/null | tail -n +21)
    if [ -n "$BACKUPS" ]; then
        echo "$BACKUPS" | xargs rm -f
    fi

    # Ask for confirmation before proceeding
    read -r -p "Backup completed. Continue with alias updates? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        echo "Operation canceled. Exiting."
        exit 1
    fi
}

# Function to check if alias exists and retrieve existing data
get_alias_data() {
    ALIAS_NAME=$1

    RESPONSE=$(curl -s -X GET "$API_BASE/getAlias/$ALIAS_NAME" \
        -u "$API_KEY:$API_SECRET" \
        -H "Content-Type: application/json")

    if echo "$RESPONSE" | grep -q '"result":"ok"'; then
        echo "$RESPONSE"
    else
        echo ""
    fi
}

# Function to detect "drift" in the firewall aliases
detect_drift() {
    EXISTING_ALIASES=$(curl -s -X GET "$API_BASE/searchAlias" \
        -u "$API_KEY:$API_SECRET" \
        -H "Content-Type: application/json" | jq -r '.rows[].name')

    SCRIPT_ALIASES="MS_AD_DS_Client_Only_Master MS_AD_DS_Server_Master InterVLAN_NFS_Master InterVLAN_SMB_Master Public_Facing_Services_Master ADDS_RPC_DYNAMIC_TCP NFS_DYN_TCP SMB_DYN_TCP"

    echo "$(timestamp) 🔍 Running firewall alias drift detection..." | tee -a "$DRIFT_LOG"

    for ALIAS in $EXISTING_ALIASES; do
        if ! echo "$SCRIPT_ALIASES" | grep -q "\b$ALIAS\b"; then
            echo "$(timestamp) ⚠️ Drift detected: Alias '$ALIAS' exists in production but is NOT in the script." | tee -a "$DRIFT_LOG"
        fi
    done
}

# Function to add or update an alias while preserving extra fields
add_or_update_alias() {
    ALIAS_NAME=$1
    PORTS=$2
    DESC=$3

    EXISTING_DATA=$(get_alias_data "$ALIAS_NAME")

    if [ -n "$EXISTING_DATA" ]; then
        echo "$(timestamp) 🔄 Updating alias: $ALIAS_NAME" | tee -a "$SUCCESS_LOG"

        RESPONSE=$(curl -s -X POST "$API_BASE/setAlias" \
            -u "$API_KEY:$API_SECRET" \
            -H "Content-Type: application/json" \
            -d '{
                "enabled": "1",
                "name": "'"$ALIAS_NAME"'",
                "type": "port",
                "content": "'"$PORTS"'",
                "description": "'"$DESC"'"
            }')

        echo "$(timestamp) ✅ Successfully updated alias: $ALIAS_NAME" | tee -a "$SUCCESS_LOG"
    else
        echo "$(timestamp) ➕ Adding new alias: $ALIAS_NAME" | tee -a "$SUCCESS_LOG"

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

        echo "$(timestamp) ✅ Successfully added alias: $ALIAS_NAME" | tee -a "$SUCCESS_LOG"
    fi
}

# Perform backup and check drift before updating aliases
backup_aliases
detect_drift

# Add or update aliases
add_or_update_alias "MS_AD_DS_Client_Only_Master" "53,853,5353,67,68,547,546,664" "Allows AD clients to communicate without an AD server"
add_or_update_alias "MS_AD_DS_Server_Master" "389,636,3268,3269,88,445,135,138,139,464,123" "Allows AD DS servers to communicate, includes client rules"

# Reload OPNsense Firewall
echo "$(timestamp) 🔄 Applying firewall configuration..." | tee -a "$SUCCESS_LOG"
configctl firewall reload
echo "$(timestamp) ✅ All aliases have been added or updated successfully!" | tee -a "$SUCCESS_LOG"
