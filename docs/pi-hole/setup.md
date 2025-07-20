# Pi-hole Setup

pi-hole is bla bla bla...

## Map Static IP Addresses of Hosts

Go to [Pi-hole DNS Records](http://192.168.0.10/admin/settings/dnsrecords) and
add local DNS records of your hosts.

My IP and hosts look like

```text
192.168.0.10 infra-pi
192.168.0.171 k8s-node-171
192.168.0.172 k8s-node-172
192.168.0.181 k8s-node-181
192.168.0.182 k8s-node-182
192.168.0.51 lab-pve1
192.168.0.52 lab-pve2
```

## DHCP Server

DHCP bla bla...

Addresses booked for DHCP dnymaic IP assignment for the devices is
`192.168.0.230` to `192.168.0.254`.
