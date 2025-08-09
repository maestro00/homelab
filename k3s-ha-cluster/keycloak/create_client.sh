#!/bin/bash

set -euo pipefail

# Configuration
KEYCLOAK_HOST="" # Set this to your Keycloak host, e.g., keycloak.yukselcloud.com
HOMELAB_ADMIN_USERNAME="" # Set this to your desired homelab admin username, e.g., homelab-admin
HOMELAB_ADMIN_PASSWORD="" # Set this to your desired homelab admin password, e.g., password
CLIENT_NAME="" # This is an initial demo client name e.g., nextcloud
CLIENT_DOMAIN="" # Set this to your client domain, e.g., nextcloud.yukselcloud.com
# For nextcloud set custom oidc domainname/index.php/apps/sociallogin/custom_oidc/keycloak
CLIENT_REDICT_URI="https://$CLIENT_DOMAIN/oauth/callback"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

print_status "Getting access token for homelab admin user..."
HOMELAB_ACCESS_TOKEN=$(curl -s -X POST \
 "https://$KEYCLOAK_HOST/realms/homelab/protocol/openid-connect/token" \
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

print_status "Creating client '$CLIENT_NAME' in homelab realm..."
CLIENT_RESPONSE=$(curl -s -X POST "https://$KEYCLOAK_HOST/admin/realms/homelab/clients" \
 -H "Authorization: Bearer $HOMELAB_ACCESS_TOKEN" \
 -H "Content-Type: application/json" \
 -d "{
   \"clientId\": \"$CLIENT_NAME\",
   \"name\": \"$CLIENT_NAME\",
   \"enabled\": true,
   \"publicClient\": false,
   \"protocol\": \"openid-connect\",
   \"redirectUris\": [\"$CLIENT_REDICT_URI\"],
   \"baseUrl\": \"https://$CLIENT_DOMAIN\",
   \"adminUrl\": \"https://$CLIENT_DOMAIN\",
   \"standardFlowEnabled\": true,
   \"implicitFlowEnabled\": false,
   \"directAccessGrantsEnabled\": true,
   \"serviceAccountsEnabled\": false,
   \"authorizationServicesEnabled\": false
 }")

if echo "$CLIENT_RESPONSE" | grep -q "Client .* already exists"; then
    print_warning "Client '$CLIENT_NAME' already exists"
else
    print_status "Client '$CLIENT_NAME' created successfully"
fi

print_status "Getting client secret for '$CLIENT_NAME'..."
CLIENT_UUID=$(curl -s -X GET "https://$KEYCLOAK_HOST/admin/realms/homelab/clients?clientId=$CLIENT_NAME" \
 -H "Authorization: Bearer $HOMELAB_ACCESS_TOKEN" | jq -r '.[0].id')

CLIENT_SECRET=$(curl -s -X GET "https://$KEYCLOAK_HOST/admin/realms/homelab/clients/$CLIENT_UUID/client-secret" \
 -H "Authorization: Bearer $HOMELAB_ACCESS_TOKEN" | jq -r '.value')

echo ""
echo "=========================================="
echo "           SETUP COMPLETE"
echo "=========================================="
echo ""
print_status "Client $CLIENT_NAME setup completed successfully!"
echo "Client Details:"
echo "  - Client ID: $CLIENT_NAME"
echo "  - Client Secret: $CLIENT_SECRET"
echo "  - Redirect URI: $CLIENT_REDICT_URI"
echo ""
