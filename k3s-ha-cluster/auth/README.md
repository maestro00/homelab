# Authentication Stack

This folder contains identity and authentication components used across the
homelab.

## Components

### lldap

- Lightweight LDAP directory
- Acts as the identity backend for Authelia
- Stores users and groups only
- Internal access only (ClusterIP/LoadbalancerIP)

### Redis

- Session storage for Authelia
- Enables session persistence across Authelia restarts
- Internal access only (ClusterIP)
- Requires authentication

### Authelia

- Authentication gateway
- Integrates with Caddy via forward-auth
- Uses lldap as LDAP backend
- Provides SSO, MFA, and access control

## Auth Flow

User → Caddy → Authelia → lldap → Application
