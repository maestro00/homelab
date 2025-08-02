#!/bin/bash

set -euo pipefail

# Configuration
KEYCLOAK_HOST="" # Set this to your Keycloak host, e.g., keycloak.yukselcloud.com
MASTER_USERNAME="" # Set this to your Keycloak master username, e.g., admin
MASTER_PASSWORD="" # Set this to your Keycloak master password, e.g., password
HOMELAB_ADMIN_USERNAME="" # Set this to your desired homelab admin username, e.g., homelab-admin
HOMELAB_ADMIN_PASSWORD="" # Set this to your desired homelab admin password, e.g., password
CLIENT_NAME="nextcloud" # This is an initial demo client name
CLIENT_DOMAIN="nextcloud.yukselcloud.com"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

print_status "Starting Keycloak homelab realm setup..."

# Step 1: Get master realm access token
print_status "Getting master realm access token..."
ACCESS_TOKEN=$(curl -s -X POST \
 "http://$KEYCLOAK_HOST/realms/master/protocol/openid-connect/token" \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "username=$MASTER_USERNAME" \
 -d "password=$MASTER_PASSWORD" \
 -d 'grant_type=password' \
 -d 'client_id=admin-cli' | jq -r .access_token)

if [ "$ACCESS_TOKEN" = "null" ] || [ -z "$ACCESS_TOKEN" ]; then
    print_error "Failed to get access token. Please check your master credentials."
    exit 1
fi
print_status "Access token obtained successfully"

# Step 2: Create homelab realm (if it doesn't exist)
print_status "Creating homelab realm..."
REALM_RESPONSE=$(curl -s -X POST "http://$KEYCLOAK_HOST/admin/realms" \
 -H "Authorization: Bearer $ACCESS_TOKEN" \
 -H "Content-Type: application/json" \
 -d '{
   "realm": "homelab",
   "enabled": true,
   "displayName": "Homelab Services",
   "registrationAllowed": false,
   "loginWithEmailAllowed": true,
   "duplicateEmailsAllowed": false,
   "verifyEmail": false,
   "requiredActions": []
 }')

# Check if realm creation was successful or if it already exists
if echo "$REALM_RESPONSE" | grep -q "Conflict detected"; then
    print_warning "Homelab realm already exists"
else
    print_status "Homelab realm created successfully"
fi

# Step 2.1: Remove verify profile required action from the realm
print_status "Removing verify profile required action..."
curl -s -X DELETE "http://$KEYCLOAK_HOST/admin/realms/homelab/authentication/required-actions/UPDATE_PROFILE" \
 -H "Authorization: Bearer $ACCESS_TOKEN"

# Step 2.2: Update realm settings to disable profile verification
print_status "Updating realm settings to disable profile verification requirements..."
curl -s -X PUT "http://$KEYCLOAK_HOST/admin/realms/homelab" \
 -H "Authorization: Bearer $ACCESS_TOKEN" \
 -H "Content-Type: application/json" \
 -d '{
   "realm": "homelab",
   "enabled": true,
   "displayName": "Homelab Services",
   "registrationAllowed": false,
   "loginWithEmailAllowed": true,
   "duplicateEmailsAllowed": false,
   "verifyEmail": false,
   "requiredActions": [],
   "defaultRequiredActions": []
 }'

# Step 3: Create admin user in homelab realm
print_status "Creating admin user '$HOMELAB_ADMIN_USERNAME' in homelab realm..."
USER_RESPONSE=$(curl -s -X POST "http://$KEYCLOAK_HOST/admin/realms/homelab/users" \
 -H "Authorization: Bearer $ACCESS_TOKEN" \
 -H "Content-Type: application/json" \
 -d "{
   \"username\": \"$HOMELAB_ADMIN_USERNAME\",
   \"enabled\": true,
   \"emailVerified\": true,
   \"firstName\": \"Homelab\",
   \"lastName\": \"Administrator\",
   \"email\": \"admin@homelab.local\",
   \"requiredActions\": [],
   \"credentials\": [{
     \"type\": \"password\",
     \"value\": \"$HOMELAB_ADMIN_PASSWORD\",
     \"temporary\": false
   }]
 }")

if echo "$USER_RESPONSE" | grep -q "User exists"; then
    print_warning "User '$HOMELAB_ADMIN_USERNAME' already exists"
else
    print_status "User '$HOMELAB_ADMIN_USERNAME' created successfully"
fi

# Step 4: Get the user ID
print_status "Getting user ID for '$HOMELAB_ADMIN_USERNAME'..."
HOMELAB_USER_ID=$(curl -s -X GET "http://$KEYCLOAK_HOST/admin/realms/homelab/users?username=$HOMELAB_ADMIN_USERNAME" \
 -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.[0].id')

if [ "$HOMELAB_USER_ID" = "null" ] || [ -z "$HOMELAB_USER_ID" ]; then
    print_error "Failed to get user ID for '$HOMELAB_ADMIN_USERNAME'"
    exit 1
fi
print_status "User ID obtained: $HOMELAB_USER_ID"

# Step 5: Get realm-management client ID from homelab realm
print_status "Getting realm-management client ID..."
REALM_MGMT_CLIENT_ID=$(curl -s -X GET "http://$KEYCLOAK_HOST/admin/realms/homelab/clients?clientId=realm-management" \
 -H "Authorization: Bearer $ACCESS_TOKEN" | jq -r '.[0].id')

if [ "$REALM_MGMT_CLIENT_ID" = "null" ] || [ -z "$REALM_MGMT_CLIENT_ID" ]; then
    print_error "Failed to get realm-management client ID"
    exit 1
fi
print_status "Realm-management client ID: $REALM_MGMT_CLIENT_ID"

# Step 6: Get realm-admin role
print_status "Getting realm-admin role..."
REALM_ADMIN_ROLE=$(curl -s -X GET "http://$KEYCLOAK_HOST/admin/realms/homelab/clients/$REALM_MGMT_CLIENT_ID/roles/realm-admin" \
 -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$REALM_ADMIN_ROLE" | grep -q "error"; then
    print_error "Failed to get realm-admin role"
    exit 1
fi
print_status "Realm-admin role obtained"

# Step 7: Assign realm-admin role to user
print_status "Assigning realm-admin role to user '$HOMELAB_ADMIN_USERNAME'..."
ROLE_ASSIGNMENT=$(curl -s -X POST "http://$KEYCLOAK_HOST/admin/realms/homelab/users/$HOMELAB_USER_ID/role-mappings/clients/$REALM_MGMT_CLIENT_ID" \
 -H "Authorization: Bearer $ACCESS_TOKEN" \
 -H "Content-Type: application/json" \
 -d "[$REALM_ADMIN_ROLE]")

print_status "Realm-admin role assigned successfully"

# Step 8: Get access token for the new homelab admin user
print_status "Getting access token for homelab admin user..."
HOMELAB_ACCESS_TOKEN=$(curl -s -X POST \
 "http://$KEYCLOAK_HOST/realms/homelab/protocol/openid-connect/token" \
 -H "Content-Type: application/x-www-form-urlencoded" \
 -d "username=$HOMELAB_ADMIN_USERNAME" \
 -d "password=$HOMELAB_ADMIN_PASSWORD" \
 -d 'grant_type=password' \
 -d 'client_id=admin-cli' | jq -r .access_token)

if [ "$HOMELAB_ACCESS_TOKEN" = "null" ] || [ -z "$HOMELAB_ACCESS_TOKEN" ]; then
    print_error "Failed to get access token for homelab admin user"
    exit 1
fi
print_status "Homelab admin access token obtained"

# Step 9: Display summary
echo ""
echo "=========================================="
echo "           SETUP COMPLETE"
echo "=========================================="
echo ""
print_status "Homelab realm setup completed successfully!"
echo ""
echo "Realm Details:"
echo "  - Realm Name: homelab"
echo "  - Realm URL: http://$KEYCLOAK_HOST/realms/homelab"
echo ""
echo "Admin User Details:"
echo "  - Username: $HOMELAB_ADMIN_USERNAME"
echo "  - Password: $HOMELAB_ADMIN_PASSWORD"
echo "  - Admin Console: http://$KEYCLOAK_HOST/admin/homelab/console/"
echo ""
echo "OpenID Connect Endpoints:"
echo "  - Authorization: http://$KEYCLOAK_HOST/realms/homelab/protocol/openid-connect/auth"
echo "  - Token: http://$KEYCLOAK_HOST/realms/homelab/protocol/openid-connect/token"
echo "  - UserInfo: http://$KEYCLOAK_HOST/realms/homelab/protocol/openid-connect/userinfo"
echo "  - Well-known: http://$KEYCLOAK_HOST/realms/homelab/.well-known/openid_configuration"
echo ""
print_status "You can now configure your applications to use this Keycloak setup!"
