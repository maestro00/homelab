# Router and Tailscale reference

Network edge facts for `yukselcloud.com`: the GL.iNet router at
`192.168.0.1` (OpenWrt) and the Tailscale tailnet. No credentials live in
this file — router password is in `temp/router_pass`, Tailscale auth keys
are referenced by location only.

## Router hardware

| Field    | Value                                        |
| -------- | -------------------------------------------- |
| Model    | GL.iNet GL-BE6500                            |
| Firmware | OpenWrt 23.05-SNAPSHOT r0-3601c2a49          |
| Arch     | aarch64 (ARMv8 rev 4), kernel 5.4.213        |
| Console  | <http://console.gl-inet.com> -> 192.168.0.1  |
| SSH      | `sshpass -f temp/router_pass ssh root@192.168.0.1` |

## Networks and firewall zones

- `lan` 192.168.0.1/24 — fully trusted (input/output/forward ACCEPT)
- `wan` DHCP from ISP; gets the public IP directly (e.g. `85.156.79.45`);
  masquerade + mtu_fix, input DROP, forward REJECT
- `guest` 192.168.9.1/24 — input/forward REJECT
- `iot` zone exists — input/forward REJECT
- `tailscale0` and `wgclient1` zones present (GL WireGuard client)
- Samba/GL-NAS/WebDAV WAN ports explicitly DROPped

> **No active port forwards.** The only redirect (`GL-DMZ`, all protocols)
> is disabled. External inbound 443/80 does NOT reach Caddy — public
> domains resolve to the WAN IP but only answer from inside the LAN
> (hairpin). Remote access today = Tailscale. To publish externally, add a
> WAN->LAN redirect for 443 (and optionally 80) to the MetalLB/Caddy IP.

## DNS chain

```text
LAN client -> dnsmasq :53 (192.168.0.1)
           -> AdGuard Home (--glinet, /etc/AdGuardHome/config.yaml)
           -> unbound :5353 (recursive, on-router)
           -> bootstrap 9.9.9.10 / 149.112.112.10
```

- Protection enabled, filtering enabled, rewrites enabled but none defined
- `blocked_response_ttl: 10`; filter lists update every 24h
- This is why pod resolv.conf must point at `192.168.0.1` without search
  domains (see `/etc/resolv-no-search.conf` on nodes)

## DHCP static leases

| IP             | Host tag      | MAC               | Notes                     |
| -------------- | ------------- | ----------------- | ------------------------- |
| 192.168.0.171  | k8s-node-171  | BC:24:11:B8:96:55 | K3s server + ingress      |
| 192.168.0.172  | k8s-node-172  | BC:24:11:79:9D:83 | K3s agent                 |
| 192.168.0.182  | k8s-node-182  | BC:24:11:26:77:FF | K3s agent                 |
| 192.168.0.10   | infra-pi      | 88:A2:9E:14:4D:7C | Pi node                   |
| 192.168.0.51   | (untagged)    | E0:51:D8:1C:43:0F |                           |
| 192.168.0.52   | (untagged)    | E8:FF:1E:DD:37:F3 | External K3s MariaDB host |

> No reservation seen for `k8s-node-181` (.181). Add one to match the
> other nodes if it is on DHCP.

Useful UCI dumps: `uci show dhcp`, `uci show network`, `uci show firewall`.

## Tailscale

Tailnet `maestro00@` (MagicDNS enabled). Devices:

| Device     | Tailscale IP    | State                                    |
| ---------- | --------------- | ---------------------------------------- |
| gl-be6500  | 100.81.69.116   | Online — runs tailscale 1.92.5-1 OpenWrt |
| infra-pi   | 100.86.179.72   | Offline ~70d; offers exit node           |
| iphone173  | 100.76.30.1     | Offline                                  |
| taylan-1   | 100.95.26.114   | Offline ~69d                             |
