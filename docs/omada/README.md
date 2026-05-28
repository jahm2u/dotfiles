# Omada Network — Local Setup

Living notes for the home Omada controller + EAP deployment. Update as things change.

## Inventory

| Device | Model | MAC | IP | Notes |
|---|---|---|---|---|
| Hardware controller | OC300 | `b8:fb:b3:b3:98:aa` | `192.168.0.151` (DHCP) | Also reachable on `192.168.0.253` (fallback static). UI title shows `Omada Controller_B023D2`. |
| Access point #1 | EAP670 v2 (AX5400) | `e0:d3:62:73:01:a0` | `192.168.0.152` | Adopted, firmware `1.0.4`. Newer firmware available — see Firmware section in controller. |
| Access point #2 | EAP670 v2 (AX5400) | `e0:d3:62:73:07:64` | `192.168.0.155` | Adopted via Auto Find. Was discoverable via L2 broadcast even before DHCP. |
| Gateway / router | TP-Link ER605 v2.20 | `cc:ba:bd:51:60:2d` | `192.168.0.1` | Adopted after entering existing admin creds (`adminJeff`) at the controller's per-device credentials prompt. |
| Access point #3 | EAP670 v2 (AX5400) | `e0:d3:62:73:07:d0` | `192.168.0.100` | Wireless mesh client of AP#1. |
| Switch #1 | SG2210MP (8-port Gigabit PoE+, 2 SFP) | `a8:29:48:eb:5f:b2` | `192.168.0.146` | Adopted 2026-05-28. Uplinks to an ER605 LAN port. Replaced the retired TL-SG108E. Firmware 5.20.0. |

Current mesh topology:

```
ER605 (wired, 192.168.0.1)
  ├── SG2210MP  A8-29-48-EB-5F-B2  (wired uplink, 192.168.0.146)  ← wired aggregation: DVR, NAS, etc.
  └── AP#1  E0-D3-62-73-01-A0  (wired uplink, 192.168.0.152)
        ├── AP#2  E0-D3-62-73-07-64  (wireless mesh, 192.168.0.155)
        └── AP#3  E0-D3-62-73-07-D0  (wireless mesh, 192.168.0.100)
```

LAN: `192.168.0.0/24`, gateway `192.168.0.1` (MAC `cc:ba:bd:51:60:2d`).

## Access

- **URL:** <https://192.168.0.151/> (self-signed cert — Chrome will warn; click Advanced → Proceed, or type `thisisunsafe` on the warning page).
- **HTTP fallback:** <http://192.168.0.151:8088/> redirects to HTTPS.
- **Admin user:** `adminJeff` / email `jeff.hamersly@gmail.com`. Password not stored here.
- **TP-Link Cloud:** not bound (skipped at setup).

## Discovery (how I found the controller)

The OC300 does **not** have an LCD on the front. To find its DHCP-assigned IP from this Mac:

```bash
# 1. Ping sweep the LAN
for i in $(seq 1 254); do ping -c1 -W500 192.168.0.$i >/dev/null 2>&1 && echo 192.168.0.$i & done; wait

# 2. Probe the alive hosts for Omada's management ports
nmap -Pn -p 8088,8043,443 --open 192.168.0.0/24

# 3. The controller is the host that returns "Omada Controller" as <title>:
curl -sk -L --connect-timeout 3 https://<ip>/ | grep -i '<title>'
```

The controller listens on 80 / 443 / 8088 / 8043. Default management ports are `8088` (HTTP) and `8043` (HTTPS), but the UI is also served on `80`/`443` after first-run.

## Adopting a new EAP

1. Plug the EAP into a PoE port (or a PoE injector) on the same L2 LAN as the controller.
2. Wait ~60-90s for it to boot — power LED solid green, then slow flashing while it scans.
3. In the controller: **Devices → APs**. A pending device should appear with status **PENDING**.
4. Click the adopt icon. The AP applies controller config and goes **CONNECTED**.

If the AP was previously adopted by another controller, it will refuse adoption until factory reset: hold the reset pinhole for **~10 seconds** until LEDs cycle.

## Troubleshooting

### Finding APs that don't show up in ARP

A pre-adoption EAP can be invisible to ARP (no DHCP lease yet) but still discoverable by the controller via L2 broadcast. **Always check `Devices → Add Devices → Auto Find` first** — it surfaces unmanaged Omada hardware on the LAN regardless of IP state. Only fall back to LAN scans if Auto Find comes up empty.

If Auto Find shows nothing:

1. **Power.** EAP670 v2 is PoE-only (802.3af/at) — no DC jack. LED dark = no PoE. Try a different PoE port / injector.
2. **Cable / link.** Swap the patch cable. Check switch port link light.
3. **Prior adoption.** If the AP was on another controller, factory reset (hold pinhole ~10s) — it'll refuse new adoption otherwise.
4. **Different broadcast domain.** Omada L2 discovery needs AP + controller on the same VLAN/subnet. For L3 discovery, use DHCP option 138 or `Omada Discovery Utility` to set the controller inform URL on the AP.

### ER605 adoption

When the ER605 is already in use as a router with its own admin login, controller adoption fails with **`ADOPT FAILED`** because the controller doesn't know the existing credentials.

**What worked here:** retrying adoption from `Devices → Add Devices → Auto Find → select ER605 → Apply` triggers a per-device credential prompt ("The username and password for selected devices have been changed..."). Enter the router's current admin username + password and click **Adopt**. The router transitions ADOPTING → CONFIGURING → CONNECTED, preserving uptime and existing config.

Other path: factory reset (hold pin ~10s) — destructive, wipes WAN/DHCP/firewall.

### Moving an AP without an Ethernet uplink (mesh)

EAP670 v2 supports Omada Mesh — wireless uplink to another adopted AP, with PoE injector providing power locally. **Mesh is enabled by default**; no global toggle to flip.

**How to verify mesh is actually working** (this deployment, confirmed):

1. Switch to the site view (top-left dropdown → "Home").
2. **Devices** → click the wired root AP (the one with Ethernet uplink to the router).
3. Detail panel → **Connection** tab → look at **DOWNLINK DEVICE** + **CONNECTION TYPE**. Any AP listed there with `Wireless` is mesh-uplinked. RSSI in parentheses (e.g. `-55dBm`) indicates link quality (better than -65 dBm is generally fine).

**Procedure for placing a mesh AP:**
1. Adopt the AP wired first (so it pulls config from the controller).
2. Wait until status is **CONNECTED** — never unplug during ADOPTING/PROVISIONING/UPGRADING.
3. Unplug, move to final location, plug into PoE injector with a short cable. No LAN uplink needed.
4. AP boots, fails to find controller via wire, scans for mesh-capable neighbors, joins the strongest one. Status returns to CONNECTED and shows up as a `Wireless` downlink under its parent AP.

### Cert warning every visit

Self-signed. Either accept once (Chrome remembers per profile) or import the controller cert into Keychain. The thisisunsafe trick (type those letters on the warning page) bypasses without clicking.

## Firmware

- **AP1** is on `1.3.6` (auto-upgraded during adoption).
- **AP2 / AP3** are on `1.1.1`. Cloud Firmware Pool is empty for EAP670 v2, so upgrade requires manually downloading the `.bin` from TP-Link and using **Devices → APx → Action → Custom Upgrade → Browse**.
- **Controller** still has a v6.2.10.18 update available — see top-bar prompt.

## WLAN Optimization

- **Adaptive WLAN Optimization** is enabled — continuously tunes channels/power from telemetry, no service interruption.
- **One-shot RF Planning** (`Optimize Now`) is blocked by the current mesh topology ("No APs available for AI RF Planning" — mesh-uplinked APs are skipped). Re-trigger after AP2/AP3 are wired into a PoE switch.

## DHCP Reservations

Set at **Network Config → DHCP Reservation** to keep critical infra IPs stable across lease renewals:

| Name | MAC | IP |
|---|---|---|
| OC300 | `b8:fb:b3:b3:98:aa` | `192.168.0.151` |
| AP1   | `e0:d3:62:73:01:a0` | `192.168.0.152` |
| AP2   | `e0:d3:62:73:07:64` | `192.168.0.155` |
| AP3   | `e0:d3:62:73:07:d0` | `192.168.0.100` |
| SG2210MP | `a8:29:48:eb:5f:b2` | `192.168.0.146` |

## Backups

Controller backup downloads via **Global View → Settings → Maintenance → Export**. Includes Settings, User Info, Authenticated Clients, Firmware Update Logs. Files land in Downloads — keep at least the most recent off the OC300 itself for disaster recovery.

## References

- TP-Link Omada SDN: <https://www.omadanetworks.com/>
- OC300 product: <https://www.tp-link.com/us/business-networking/omada-sdn-controller/oc300/>
- EAP670 v2 product: <https://www.tp-link.com/us/business-networking/omada-wifi-ceiling-mount/eap670/>
- Omada Discovery Utility (for L3 discovery): bundled with the Omada Software Controller download.
