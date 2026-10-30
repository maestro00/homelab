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

## Wireless (2026-09-04)

- 5 GHz: ch 100 (DFS), `EHT160`, 31 dBm — moved off the crowded ch 36-48
  block; DFS 100-128 allows 1000 mW EIRP (vs 200 mW on UNII-1) and is nearly
  empty. Costs ~60 s radar check (CAC) on boot/channel change.
- 2.4 GHz: ch 6, `EHT40`, 19 dBm — cleanest channel in scan; only carries the
  MLO leg (base 2G SSID `GL-BE6500-f53` is disabled).
- MLO SSID `GL-BE6500-f53-MLO` spans 2.4+5 (no 6 GHz radio on this
  firmware/build — no 320 MHz available).

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
           -> AdGuard Home :3053 (--glinet, /etc/AdGuardHome/config.yaml)
           -> public resolvers 8.8.8.8 / 1.1.1.1 (load_balance)
```

- Protection enabled, filtering enabled, rewrites enabled but none defined
- `blocked_response_ttl: 10`; filter lists update every 24h
- AdGuard `upstream_dns` = `8.8.8.8`, `1.1.1.1`; `fallback_dns` = `8.8.8.8`
- AdGuard `bootstrap_dns` = 9.9.9.10 / 149.112.112.10 (Quad9)
- This is why pod resolv.conf must point at `192.168.0.1` without search
  domains (see `/etc/resolv-no-search.conf` on nodes)

> **unbound removed (2026-10-12):** the on-router recursive resolver
> (`/var/lib/unbound/unbound.conf`, port 5354) wedged repeatedly under LAN +
> K3s load, stalling every cold lookup and breaking apps on the TV. It is now
> stopped and disabled (`/etc/init.d/unbound stop; ... disable`, plus
> `uci set unbound.ub_main.enabled=0`), and AdGuard resolves directly against
> public resolvers. The backup config is `config.yaml.bak-<date>` on the
> router. To restore recursion, re-enable the service and add
> `127.0.0.1:5354` back to AdGuard `upstream_dns`.

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
