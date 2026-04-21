#!/usr/bin/env python3
"""
Generate a Postman Collection with mock examples for VeloCloud SD-WAN API.
Creates a mock server compatible collection with infrastructure-consistent data:
  - 1 enterprise (organization)
  - 5 sites with dedicated subnets
  - 50 VeloCloud Edge devices distributed across sites
  - Bidirectional BGP peering between edges on the same site
  - IP routes referencing actual peer and connected networks
  - 200 client devices linked to actual edge logicalIds
  - Consistent interface addressing within site transit networks

Endpoints mocked (from Client/VeloCloud.pm):
  GET /api/sdwan/v2/enterprises/
  GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/edges
  GET /api/sdwan/v2/enterprises/{enterpriseLogicalId}/clientDevices
  GET /api/sdwan/v2/gateways/{gatewayLogicalId}/

Usage:
    python3 tools/generate_velocloud_postman_collection.py

Output:
    Postman-Collections/VeloCloud-Postman-MockServer-Collection.json
"""

import json
import uuid
import random
import os
import hashlib
import time

# ──────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────
NUM_EDGES = 50
NUM_CLIENT_DEVICES = 200
NUM_SITES = 5
COLLECTION_NAME = "VeloCloud SDN Mock Server"

# Fixed IDs for deterministic generation
ENTERPRISE_LOGICAL_ID = "ent-a1b2c3d4-0001-4000-8000-000000000001"
ENTERPRISE_NAME = "Mock-VeloCloud-Enterprise"
ENTERPRISE_DOMAIN = "mock-velocloud.example.com"
FABRIC_ID = "55"

EDGE_MODELS = ["Edge 520", "Edge 540", "Edge 620", "Edge 640", "Edge 840", "Edge 3400", "Edge 3800"]
SW_VERSIONS = ["6.0.0.4", "6.0.1.0", "6.1.0.2", "5.4.0.6", "5.4.1.0", "6.2.0.0"]
ROUTE_PROTOCOLS = ["connected", "static", "bgp", "ospf"]

# Site definitions — each site has a WAN transit /24, a LAN /16 block, and a city
SITE_DEFS = [
    {"name": "HQ-NewYork",     "city": "New York",     "wan_prefix": "10.1.1",   "lan_prefix": "192.168",  "asn": 65001},
    {"name": "Branch-Chicago",  "city": "Chicago",      "wan_prefix": "10.1.2",   "lan_prefix": "192.169",  "asn": 65002},
    {"name": "Branch-Dallas",   "city": "Dallas",       "wan_prefix": "10.1.3",   "lan_prefix": "192.170",  "asn": 65003},
    {"name": "DC-SanJose",      "city": "San Jose",     "wan_prefix": "10.1.4",   "lan_prefix": "192.171",  "asn": 65004},
    {"name": "Branch-London",   "city": "London",       "wan_prefix": "10.1.5",   "lan_prefix": "192.172",  "asn": 65005},
]

random.seed(99)  # deterministic


def make_uuid():
    return str(uuid.uuid4())


def make_mac(seed_int):
    h = hashlib.md5(str(seed_int).encode()).hexdigest()
    return ":".join(h[i : i + 2] for i in range(0, 12, 2))


def make_serial(prefix, idx):
    return f"{prefix}{idx:06d}"


# ──────────────────────────────────────────────────────
# Infrastructure builder — generates all data in one pass
# for cross-referencing consistency
# ──────────────────────────────────────────────────────

def build_infrastructure():
    """Build entire infrastructure graph, then derive per-endpoint views."""

    # ── Sites ──
    sites = []
    for si, sdef in enumerate(SITE_DEFS):
        sites.append({
            "siteId": si + 1,
            "name": sdef["name"],
            "city": sdef["city"],
            "wan_prefix": sdef["wan_prefix"],
            "lan_prefix": sdef["lan_prefix"],
            "asn": sdef["asn"],
            "edge_indices": [],         # filled below
        })

    # ── Assign edges to sites (round-robin) ──
    for idx in range(NUM_EDGES):
        sites[idx % NUM_SITES]["edge_indices"].append(idx)

    # ── Phase 1: Build edge skeletons with deterministic IDs & IPs ──
    edges = []
    for idx in range(NUM_EDGES):
        site = sites[idx % NUM_SITES]
        sdef = SITE_DEFS[idx % NUM_SITES]
        pos_in_site = site["edge_indices"].index(idx)  # 0-based position within site

        logical_id = f"edge-{idx:04d}-{uuid.UUID(int=random.getrandbits(128))}"
        model = EDGE_MODELS[idx % len(EDGE_MODELS)]
        version = SW_VERSIONS[idx % len(SW_VERSIONS)]
        serial = make_serial("VC", 20000 + idx)
        state = "CONNECTED" if random.random() < 0.9 else "OFFLINE"

        # WAN IP: site transit network, unique per edge in site
        wan_ip = f"{sdef['wan_prefix']}.{pos_in_site + 1}"
        # LAN IP: site LAN block, edge gets its own /24
        lan_ip = f"{sdef['lan_prefix']}.{pos_in_site}.1"
        # Management IP = WAN IP
        mgmt_ip = wan_ip

        # Interfaces — deterministic per edge
        num_lan = random.randint(2, 5)
        interfaces = []
        # GE1 = WAN uplink on the site transit network
        interfaces.append({
            "name": "GE1",
            "description": "GE1 - WAN",
            "macAddress": make_mac(20000 + idx * 100),
            "ipAddress": wan_ip,
            "subnetMask": "255.255.255.0",
            "cidr": f"{wan_ip}/24",
            "mtu": 1500,
            "operationalStatus": "up",
            "adminStatus": "up",
            "adminUp": True,
            "bandwidthUp": 10000,
            "bandwidthDown": 10000,
            "speed": 10000,
            "status": "STABLE",
        })
        # GE2..GEN = LAN interfaces
        for li in range(num_lan):
            intf_name = f"GE{li + 2}"
            intf_ip = f"{sdef['lan_prefix']}.{pos_in_site}.{li + 1}"
            interfaces.append({
                "name": intf_name,
                "description": f"{intf_name} - LAN",
                "macAddress": make_mac(20000 + idx * 100 + li + 1),
                "ipAddress": intf_ip,
                "subnetMask": "255.255.255.0",
                "cidr": f"{intf_ip}/24",
                "mtu": 1500,
                "operationalStatus": "up" if random.random() < 0.85 else "down",
                "adminStatus": "up",
                "adminUp": True,
                "bandwidthUp": random.choice([100, 1000, 10000]),
                "bandwidthDown": random.choice([100, 1000, 10000]),
                "speed": random.choice([1000, 10000]),
                "status": "STABLE",
            })

        edges.append({
            "logicalId": logical_id,
            "id": idx + 1,
            "name": f"velocloud-edge-{idx + 1:04d}",
            "edgeState": state,
            "model": model,
            "serialNumber": serial,
            "softwareVersion": version,
            "vendor": "VeloCloud",
            "ipAddress": mgmt_ip,
            "managementIp": mgmt_ip,
            "siteId": site["siteId"],
            "siteName": site["name"],
            "activationState": "ACTIVATED",
            "created": "2024-06-01T00:00:00.000Z",
            "modified": "2026-04-01T12:00:00.000Z",
            "interfaces": interfaces,
            "ipRoutes": [],    # filled in phase 3
            "bgpPeers": [],    # filled in phase 2
            "lldpNeighbors": [],  # filled in phase 2.5
            "arpTable": [],    # filled in phase 5
            "macTable": [],    # filled in phase 5
            "cpuUsage": round(random.uniform(5, 85), 1),
            "memoryUsage": round(random.uniform(20, 90), 1),
            "uptime": random.randint(86400, 8640000),
            "_siteIndex": idx % NUM_SITES,
            "_posInSite": pos_in_site,
        })

    # ── Phase 2: Bidirectional BGP peering ──
    # Within each site, pair adjacent edges as BGP peers.
    # The first edge also peers with the last to form a ring.
    for site in sites:
        site_edges = site["edge_indices"]
        if len(site_edges) < 2:
            continue
        for i in range(len(site_edges)):
            j = (i + 1) % len(site_edges)
            edge_a = edges[site_edges[i]]
            edge_b = edges[site_edges[j]]
            site_asn = site["asn"]

            shared_uptime = random.randint(3600, 8640000)
            a_advertised = random.randint(5, 200)
            b_advertised = random.randint(5, 200)

            # A → B
            edge_a["bgpPeers"].append({
                "peerIp": edge_b["interfaces"][0]["ipAddress"],
                "peerName": edge_b["name"],
                "peerLogicalId": edge_b["logicalId"],
                "asn": site_asn,
                "localIp": edge_a["interfaces"][0]["ipAddress"],
                "localPort": 179,
                "remotePort": 179,
                "state": "established",
                "uptime": shared_uptime,
                "routesAdvertised": a_advertised,
                "routesReceived": b_advertised,
            })
            # B → A (mirror)
            edge_b["bgpPeers"].append({
                "peerIp": edge_a["interfaces"][0]["ipAddress"],
                "peerName": edge_a["name"],
                "peerLogicalId": edge_a["logicalId"],
                "asn": site_asn,
                "localIp": edge_b["interfaces"][0]["ipAddress"],
                "localPort": 179,
                "remotePort": 179,
                "state": "established",
                "uptime": shared_uptime,
                "routesAdvertised": b_advertised,
                "routesReceived": a_advertised,
            })

    # ── Phase 2.5: Bidirectional LLDP/CDP neighbors ──
    # All edges on the same site share a WAN transit L2 segment.
    # Each edge sees every other edge on the same site as an LLDP neighbor
    # on GE1, and this is symmetrical.
    for site in sites:
        site_edges = site["edge_indices"]
        for i in range(len(site_edges)):
            edge_a = edges[site_edges[i]]
            for j in range(len(site_edges)):
                if i == j:
                    continue
                edge_b = edges[site_edges[j]]
                edge_a["lldpNeighbors"].append({
                    "localInterface": "GE1",
                    "localInterfaceMac": edge_a["interfaces"][0]["macAddress"],
                    "remoteInterface": "GE1",
                    "remoteInterfaceMac": edge_b["interfaces"][0]["macAddress"],
                    "remoteDeviceId": edge_b["logicalId"],
                    "remoteDeviceName": edge_b["name"],
                    "remoteIpAddress": edge_b["interfaces"][0]["ipAddress"],
                    "remoteModel": edge_b["model"],
                    "remoteSerialNumber": edge_b["serialNumber"],
                    "remoteSoftwareVersion": edge_b["softwareVersion"],
                    "capabilities": "Router, Bridge",
                    "ttl": 120,
                })

    # ── Phase 3: IP routes referencing actual infrastructure ──
    for idx, edge in enumerate(edges):
        site = sites[edge["_siteIndex"]]
        sdef = SITE_DEFS[edge["_siteIndex"]]
        routes = []

        # Connected route for WAN transit subnet
        routes.append({
            "destination": f"{sdef['wan_prefix']}.0/24",
            "nextHop": "0.0.0.0",
            "metric": 0,
            "protocol": "connected",
            "interface": "GE1",
            "ifName": "GE1",
        })

        # Connected routes for each LAN interface
        for intf in edge["interfaces"][1:]:
            subnet = intf["ipAddress"].rsplit(".", 1)[0] + ".0"
            routes.append({
                "destination": f"{subnet}/24",
                "nextHop": "0.0.0.0",
                "metric": 0,
                "protocol": "connected",
                "interface": intf["name"],
                "ifName": intf["name"],
            })

        # Direct /32 host routes to every other edge on the same WAN segment
        # These are the directly-connected peers visible via LLDP on GE1
        for nbr in edge["lldpNeighbors"]:
            routes.append({
                "destination": f"{nbr['remoteIpAddress']}/32",
                "nextHop": nbr["remoteIpAddress"],
                "metric": 0,
                "protocol": "connected",
                "interface": "GE1",
                "ifName": "GE1",
            })

        # BGP-learned routes: for each BGP peer, learn their LAN subnets
        for peer in edge["bgpPeers"]:
            peer_edge = next((e for e in edges if e["logicalId"] == peer["peerLogicalId"]), None)
            if peer_edge:
                for pintf in peer_edge["interfaces"][1:]:
                    peer_subnet = pintf["ipAddress"].rsplit(".", 1)[0] + ".0"
                    routes.append({
                        "destination": f"{peer_subnet}/24",
                        "nextHop": peer["peerIp"],
                        "metric": 20,
                        "protocol": "bgp",
                        "interface": "GE1",
                        "ifName": "GE1",
                    })

        # Static default route via site gateway (.254)
        routes.append({
            "destination": "0.0.0.0/0",
            "nextHop": f"{sdef['wan_prefix']}.254",
            "metric": 1,
            "protocol": "static",
            "interface": "GE1",
            "ifName": "GE1",
        })

        # Cross-site static routes to other sites' WAN subnets
        for other_sdef in SITE_DEFS:
            if other_sdef["wan_prefix"] != sdef["wan_prefix"]:
                routes.append({
                    "destination": f"{other_sdef['wan_prefix']}.0/24",
                    "nextHop": f"{sdef['wan_prefix']}.254",
                    "metric": 10,
                    "protocol": "static",
                    "interface": "GE1",
                    "ifName": "GE1",
                })

        edge["ipRoutes"] = routes

    # ── Phase 4: Client devices referencing actual edge logicalIds ──
    # Distribute clients across edges; each client's IP is on the edge's LAN subnet.
    client_devices = []
    for i in range(NUM_CLIENT_DEVICES):
        target_edge_idx = i % NUM_EDGES
        target_edge = edges[target_edge_idx]
        sdef = SITE_DEFS[target_edge["_siteIndex"]]

        # Client IP on the edge's LAN subnet (GE2)
        lan_intf = target_edge["interfaces"][1]  # first LAN interface
        lan_base = lan_intf["ipAddress"].rsplit(".", 1)[0]
        host_offset = (i // NUM_EDGES) + 100  # 100-based to avoid collisions with edge .1
        client_ip = f"{lan_base}.{host_offset}"

        seed = 50000 + i
        client_devices.append({
            "id": i + 1,
            "logicalId": f"cd-{i:04d}-{uuid.UUID(int=random.getrandbits(128))}",
            "name": f"client-{target_edge['siteName']}-{i + 1:04d}",
            "ipAddress": client_ip,
            "macAddress": make_mac(seed),
            "vendor": random.choice(["Dell", "HP", "Lenovo", "Apple", "Cisco"]),
            "model": random.choice(["Laptop", "Desktop", "Printer", "IP Phone", "Camera"]),
            "serialNumber": make_serial("CD", seed),
            "operatingSystem": random.choice(["Windows 11", "macOS 14", "Ubuntu 22.04", "ChromeOS"]),
            "softwareVersion": f"{random.randint(10, 15)}.{random.randint(0, 9)}.{random.randint(0, 9)}",
            "status": ("active" if random.random() < 0.85 else "inactive"),
            "lastActive": int(time.time()) - random.randint(0, 86400),
            "edgeLogicalId": target_edge["logicalId"],
            "edgeName": target_edge["name"],
            "siteId": target_edge["siteId"],
            "siteName": target_edge["siteName"],
        })

    # ── Phase 5: ARP table + MAC forwarding table ──
    # ARP: IP→MAC for every host reachable on a directly-connected L2 segment.
    # MAC: MAC→interface for every learned MAC on each port.
    # Both must be consistent with LLDP neighbors, client devices, and interfaces.

    # Build client lookup by edge logicalId for LAN-side ARP/MAC entries
    clients_by_edge = {}
    for cd in client_devices:
        clients_by_edge.setdefault(cd["edgeLogicalId"], []).append(cd)

    # Build edge lookup by logicalId
    edge_by_lid = {e["logicalId"]: e for e in edges}

    for edge in edges:
        arp = []
        mac_tbl = []
        wan_intf = edge["interfaces"][0]  # GE1

        # --- WAN side: ARP/MAC for every LLDP neighbor (same-site peers on GE1) ---
        for nbr in edge["lldpNeighbors"]:
            peer = edge_by_lid.get(nbr["remoteDeviceId"])
            if not peer:
                continue
            peer_wan = peer["interfaces"][0]
            arp.append({
                "ipAddress": peer_wan["ipAddress"],
                "macAddress": peer_wan["macAddress"],
                "interface": "GE1",
                "state": "reachable",
                "type": "dynamic",
                "age": random.randint(10, 300),
            })
            mac_tbl.append({
                "macAddress": peer_wan["macAddress"],
                "interface": "GE1",
                "vlan": 1,
                "type": "dynamic",
                "state": "learned",
                "deviceName": peer["name"],
            })

        # ARP/MAC for site gateway (.254) on GE1
        site_idx = next(si for si, s in enumerate(sites)
                        if edge["siteId"] == s["siteId"])
        sdef = SITE_DEFS[site_idx]
        gw_ip = f"{sdef['wan_prefix']}.254"
        gw_mac = make_mac(70000 + site_idx)  # deterministic per-site gateway MAC
        arp.append({
            "ipAddress": gw_ip,
            "macAddress": gw_mac,
            "interface": "GE1",
            "state": "reachable",
            "type": "dynamic",
            "age": random.randint(10, 600),
        })
        mac_tbl.append({
            "macAddress": gw_mac,
            "interface": "GE1",
            "vlan": 1,
            "type": "dynamic",
            "state": "learned",
            "deviceName": f"gateway-{sdef['name']}",
        })

        # --- LAN side: ARP/MAC for every client device connected to this edge ---
        edge_clients = clients_by_edge.get(edge["logicalId"], [])
        lan_intf_name = edge["interfaces"][1]["name"] if len(edge["interfaces"]) > 1 else "GE2"
        for cd in edge_clients:
            arp.append({
                "ipAddress": cd["ipAddress"],
                "macAddress": cd["macAddress"],
                "interface": lan_intf_name,
                "state": "reachable" if cd["status"] == "active" else "stale",
                "type": "dynamic",
                "age": random.randint(5, 1200),
            })
            mac_tbl.append({
                "macAddress": cd["macAddress"],
                "interface": lan_intf_name,
                "vlan": 100,
                "type": "dynamic",
                "state": "learned",
                "deviceName": cd["name"],
            })

        edge["arpTable"] = arp
        edge["macTable"] = mac_tbl

    # ── Strip internal keys before returning ──
    for edge in edges:
        edge.pop("_siteIndex", None)
        edge.pop("_posInSite", None)

    return edges, client_devices


def gen_enterprises():
    """GET /api/sdwan/v2/enterprises/"""
    return [
        {
            "logicalId": ENTERPRISE_LOGICAL_ID,
            "id": 1,
            "name": ENTERPRISE_NAME,
            "domain": ENTERPRISE_DOMAIN,
            "accountNumber": "MOCK-ACCT-001",
            "timezone": "America/New_York",
            "locale": "en-US",
            "created": "2024-01-15T00:00:00.000Z",
            "modified": "2026-04-01T12:00:00.000Z",
        }
    ]


def gen_gateway_detail(edge):
    """GET /api/sdwan/v2/gateways/{gatewayLogicalId}/"""
    return {
        "logicalId": edge["logicalId"],
        "id": edge["id"],
        "name": edge["name"],
        "edgeState": edge["edgeState"],
        "model": edge["model"],
        "serialNumber": edge["serialNumber"],
        "softwareVersion": edge["softwareVersion"],
        "ipAddress": edge["ipAddress"],
        "interfaces": edge["interfaces"],
        "ipRoutes": edge["ipRoutes"],
        "bgpPeers": edge["bgpPeers"],
        "lldpNeighbors": edge["lldpNeighbors"],
        "arpTable": edge["arpTable"],
        "macTable": edge["macTable"],
        "cpuUsage": edge["cpuUsage"],
        "memoryUsage": edge["memoryUsage"],
        "uptime": edge["uptime"],
    }


def print_consistency_report(edges, client_devices):
    """Print a brief report verifying data consistency."""
    print("\n── Consistency Report ──")

    # 1. BGP bidirectional check
    bgp_ok = 0
    bgp_fail = 0
    edge_by_id = {e["logicalId"]: e for e in edges}
    for edge in edges:
        for peer in edge["bgpPeers"]:
            remote = edge_by_id.get(peer["peerLogicalId"])
            if remote:
                mirror = [p for p in remote["bgpPeers"] if p["peerLogicalId"] == edge["logicalId"]]
                if mirror:
                    bgp_ok += 1
                else:
                    bgp_fail += 1
                    print(f"  BGP FAIL: {edge['name']} → {remote['name']} has no return peer")
            else:
                bgp_fail += 1
                print(f"  BGP FAIL: {edge['name']} peer {peer['peerLogicalId']} not found")
    print(f"  BGP peers: {bgp_ok} bidirectional OK, {bgp_fail} failures")

    # 2. LLDP bidirectional check
    lldp_ok = 0
    lldp_fail = 0
    for edge in edges:
        for nbr in edge.get("lldpNeighbors", []):
            remote = edge_by_id.get(nbr["remoteDeviceId"])
            if remote:
                mirror = [n for n in remote.get("lldpNeighbors", [])
                          if n["remoteDeviceId"] == edge["logicalId"]]
                if mirror:
                    lldp_ok += 1
                else:
                    lldp_fail += 1
                    print(f"  LLDP FAIL: {edge['name']} → {remote['name']} has no return neighbor")
            else:
                lldp_fail += 1
                print(f"  LLDP FAIL: {edge['name']} neighbor {nbr['remoteDeviceId']} not found")
    print(f"  LLDP neighbors: {lldp_ok} bidirectional OK, {lldp_fail} failures")

    # 3. Client device edge references
    cd_ok = sum(1 for cd in client_devices if cd["edgeLogicalId"] in edge_by_id)
    cd_fail = len(client_devices) - cd_ok
    print(f"  Client→Edge refs: {cd_ok} valid, {cd_fail} broken")

    # 4. Route next-hops reference real IPs
    all_ips = set()
    for e in edges:
        for intf in e["interfaces"]:
            all_ips.add(intf["ipAddress"])
    # Gateway IPs (.254) are implicit
    for sdef in SITE_DEFS:
        all_ips.add(f"{sdef['wan_prefix']}.254")
    all_ips.add("0.0.0.0")

    rt_ok = 0
    rt_orphan = 0
    for edge in edges:
        for rt in edge["ipRoutes"]:
            if rt["nextHop"] in all_ips:
                rt_ok += 1
            else:
                rt_orphan += 1
    print(f"  Route next-hops: {rt_ok} valid, {rt_orphan} orphaned")

    # 5. ARP table MAC consistency — every ARP entry's MAC must match
    # the actual interface MAC of the referenced device
    all_macs = {}  # ip → mac from actual device interfaces
    for e in edges:
        for intf in e["interfaces"]:
            all_macs[intf["ipAddress"]] = intf["macAddress"]
    # Client device MACs
    cd_by_ip = {cd["ipAddress"]: cd["macAddress"] for cd in client_devices}
    all_macs.update(cd_by_ip)
    # Gateway MACs (synthetic, so we just verify they exist)
    for si, sdef in enumerate(SITE_DEFS):
        all_macs[f"{sdef['wan_prefix']}.254"] = make_mac(70000 + si)

    arp_ok = 0
    arp_mac_mismatch = 0
    arp_ip_unknown = 0
    for edge in edges:
        for entry in edge.get("arpTable", []):
            expected_mac = all_macs.get(entry["ipAddress"])
            if expected_mac is None:
                arp_ip_unknown += 1
            elif expected_mac == entry["macAddress"]:
                arp_ok += 1
            else:
                arp_mac_mismatch += 1
                print(f"  ARP MISMATCH: {edge['name']} ARP {entry['ipAddress']} → "
                      f"{entry['macAddress']} (expected {expected_mac})")
    print(f"  ARP table: {arp_ok} correct, {arp_mac_mismatch} MAC mismatches, "
          f"{arp_ip_unknown} unknown IPs")

    # 6. MAC table consistency — every MAC in the forwarding table must appear
    # in either an edge interface or a client device
    all_known_macs = set()
    for e in edges:
        for intf in e["interfaces"]:
            all_known_macs.add(intf["macAddress"])
    for cd in client_devices:
        all_known_macs.add(cd["macAddress"])
    # Gateway MACs
    for si in range(len(SITE_DEFS)):
        all_known_macs.add(make_mac(70000 + si))

    mac_ok = 0
    mac_unknown = 0
    for edge in edges:
        for entry in edge.get("macTable", []):
            if entry["macAddress"] in all_known_macs:
                mac_ok += 1
            else:
                mac_unknown += 1
                print(f"  MAC UNKNOWN: {edge['name']} learned {entry['macAddress']} "
                      f"on {entry['interface']} — not in any device")
    print(f"  MAC table: {mac_ok} known, {mac_unknown} unknown MACs")

    # 7. Cross-table neighbor chain: LLDP neighbor → ARP entry → MAC entry
    chain_ok = 0
    chain_fail = 0
    for edge in edges:
        arp_ips = {a["ipAddress"] for a in edge.get("arpTable", [])}
        mac_addrs = {m["macAddress"] for m in edge.get("macTable", [])}
        for nbr in edge.get("lldpNeighbors", []):
            has_arp = nbr["remoteIpAddress"] in arp_ips
            has_mac = nbr["remoteInterfaceMac"] in mac_addrs
            if has_arp and has_mac:
                chain_ok += 1
            else:
                chain_fail += 1
                missing = []
                if not has_arp:
                    missing.append("ARP")
                if not has_mac:
                    missing.append("MAC")
                print(f"  CHAIN FAIL: {edge['name']} LLDP→{nbr['remoteDeviceName']} "
                      f"missing {'+'.join(missing)}")
    print(f"  LLDP→ARP→MAC chain: {chain_ok} complete, {chain_fail} broken")
    print()


# ──────────────────────────────────────────────────────
# Postman collection builder
# ──────────────────────────────────────────────────────

def postman_header_auth():
    return [
        {"key": "Authorization", "value": "Token {{apiKey}}", "type": "text"},
        {"key": "Content-Type", "value": "application/json", "type": "text"},
    ]


def make_example(name, method, url_raw, status, response_body, query_params=None, headers_extra=None):
    url_obj = {
        "raw": url_raw,
        "protocol": "https",
        "host": ["{{baseUrl}}"],
        "path": url_raw.replace("{{baseUrl}}/", "").split("/"),
    }
    if query_params:
        url_obj["query"] = [{"key": k, "value": v} for k, v in query_params.items()]
        url_obj["raw"] = url_raw + "?" + "&".join(f"{k}={v}" for k, v in query_params.items())

    resp_headers = [
        {"key": "Content-Type", "value": "application/json"},
    ]
    if headers_extra:
        resp_headers.extend(headers_extra)

    return {
        "name": name,
        "originalRequest": {
            "method": method,
            "header": postman_header_auth(),
            "url": url_obj,
        },
        "status": "OK",
        "code": status,
        "header": resp_headers,
        "body": json.dumps(response_body, separators=(",", ":")),
        "_postman_previewlanguage": "json",
    }


def make_request(name, method, url_raw, description, examples, query_params=None):
    url_obj = {
        "raw": url_raw,
        "protocol": "https",
        "host": ["{{baseUrl}}"],
        "path": url_raw.replace("{{baseUrl}}/", "").split("/"),
    }
    if query_params:
        url_obj["query"] = [{"key": k, "value": v} for k, v in query_params.items()]

    return {
        "name": name,
        "request": {
            "method": method,
            "header": postman_header_auth(),
            "url": url_obj,
            "description": description,
        },
        "response": examples,
    }


def build_collection():
    print("Generating VeloCloud mock data with consistent infrastructure...")

    base = "{{baseUrl}}"
    eid = ENTERPRISE_LOGICAL_ID

    # ── Build infrastructure graph in one pass ──
    edges_data, client_devices_data = build_infrastructure()

    # ── 1. GET /api/sdwan/v2/enterprises/ ──
    enterprises_data = gen_enterprises()
    ent_examples = [make_example("List Enterprises - Success", "GET",
                                  f"{base}/api/sdwan/v2/enterprises/", 200, enterprises_data)]
    req_enterprises = make_request("List Enterprises", "GET",
                                    f"{base}/api/sdwan/v2/enterprises/",
                                    "Returns all enterprises (organizations) visible to the API token.",
                                    ent_examples)

    # ── 2. GET /api/sdwan/v2/enterprises/{id}/edges ──
    # edges_data already built by build_infrastructure()
    edges_examples = [make_example("List Enterprise Edges - Success", "GET",
                                    f"{base}/api/sdwan/v2/enterprises/{eid}/edges", 200, edges_data)]
    req_edges = make_request("List Enterprise Edges", "GET",
                              f"{base}/api/sdwan/v2/enterprises/{eid}/edges",
                              "Returns all Edge devices for the enterprise. Each edge includes interfaces, bgpPeers, ipRoutes.",
                              edges_examples)

    # ── 3. GET /api/sdwan/v2/enterprises/{id}/clientDevices ──
    # client_devices_data already built by build_infrastructure()
    cd_examples = [make_example("List Client Devices - Success", "GET",
                                 f"{base}/api/sdwan/v2/enterprises/{eid}/clientDevices", 200, client_devices_data)]
    req_client_devices = make_request("List Enterprise Client Devices", "GET",
                                       f"{base}/api/sdwan/v2/enterprises/{eid}/clientDevices",
                                       "Returns non-edge client/endpoint devices for the enterprise.",
                                       cd_examples)

    # ── 4. GET /api/sdwan/v2/gateways/{gatewayLogicalId}/ (per edge) ──
    # Create examples for first 5 edges (Postman mock matches on URL path)
    gw_items = []
    for edge in edges_data[:5]:
        gw_detail = gen_gateway_detail(edge)
        gw_ex = [make_example(f"Gateway Detail - {edge['name']}", "GET",
                               f"{base}/api/sdwan/v2/gateways/{edge['logicalId']}/", 200, gw_detail)]
        gw_items.append(make_request(
            f"Get Gateway Detail ({edge['name']})", "GET",
            f"{base}/api/sdwan/v2/gateways/{edge['logicalId']}/",
            f"Returns full detail for edge {edge['name']} including interfaces, ipRoutes, bgpPeers, CPU/memory.",
            gw_ex))

    # Also add a "generic" gateway detail request using the first edge as the default example
    generic_gw_detail = gen_gateway_detail(edges_data[0])
    generic_gw_ex = [make_example("Gateway Detail - Default", "GET",
                                    f"{base}/api/sdwan/v2/gateways/{edges_data[0]['logicalId']}/", 200, generic_gw_detail)]
    req_gw_generic = make_request("Get Gateway Detail (Generic)", "GET",
                                    f"{base}/api/sdwan/v2/gateways/{{{{gatewayLogicalId}}}}/",
                                    "Returns full gateway/edge detail. Replace gatewayLogicalId with edge logicalId.",
                                    generic_gw_ex)

    # ── Build folder structure ──
    collection = {
        "info": {
            "_postman_id": make_uuid(),
            "name": COLLECTION_NAME,
            "description": (
                f"Mock collection for VeloCloud SD-WAN Orchestrator v2 API.\n\n"
                f"- 1 Enterprise: {ENTERPRISE_NAME} ({ENTERPRISE_LOGICAL_ID})\n"
                f"- {NUM_EDGES} Edge devices with interfaces, routes, BGP peers\n"
                f"- {NUM_CLIENT_DEVICES} Client endpoint devices\n\n"
                f"Import → Create Mock Server → use the mock URL as baseUrl."
            ),
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
        },
        "variable": [
            {"key": "baseUrl", "value": "https://vco.example.com", "type": "string"},
            {"key": "apiKey", "value": "YOUR_API_TOKEN_HERE", "type": "string"},
            {"key": "enterpriseLogicalId", "value": ENTERPRISE_LOGICAL_ID, "type": "string"},
            {"key": "gatewayLogicalId", "value": edges_data[0]["logicalId"], "type": "string"},
        ],
        "item": [
            {
                "name": "1 - Enterprise Discovery",
                "description": "List enterprises (organizations)",
                "item": [req_enterprises],
            },
            {
                "name": "2 - Edge Inventory",
                "description": "List edges per enterprise and client devices",
                "item": [req_edges, req_client_devices],
            },
            {
                "name": "3 - Gateway Detail (Interfaces, Routes, BGP)",
                "description": "Per-edge gateway detail with interfaces, IP routes, and BGP peers",
                "item": [req_gw_generic] + gw_items,
            },
        ],
    }

    return collection, edges_data, client_devices_data


def print_summary(collection):
    print(f"\n=== VeloCloud Postman Mock Server Collection ===")
    print(f"Enterprise   : {ENTERPRISE_NAME} ({ENTERPRISE_LOGICAL_ID})")
    print(f"Sites        : {NUM_SITES} ({', '.join(s['name'] for s in SITE_DEFS)})")
    print(f"Edges        : {NUM_EDGES}")
    print(f"Client Devs  : {NUM_CLIENT_DEVICES}")
    print()
    print("API Endpoints mocked:")
    print("  GET /api/sdwan/v2/enterprises/")
    print("  GET /api/sdwan/v2/enterprises/:enterpriseLogicalId/edges")
    print("  GET /api/sdwan/v2/enterprises/:enterpriseLogicalId/clientDevices")
    print("  GET /api/sdwan/v2/gateways/:gatewayLogicalId/  (5 edge examples + generic)")
    print()
    print("Each edge includes: interfaces[], ipRoutes[], bgpPeers[], cpuUsage, memoryUsage, uptime")


def main():
    collection, edges_data, client_devices_data = build_collection()
    print_summary(collection)
    print_consistency_report(edges_data, client_devices_data)

    out_dir = os.path.join(os.path.dirname(__file__), "..", "Postman-Collections")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, "VeloCloud-Postman-MockServer-Collection.json")

    with open(out_path, "w") as f:
        json.dump(collection, f, indent=2)

    size_mb = os.path.getsize(out_path) / (1024 * 1024)
    print(f"\nWritten: {out_path}")
    print(f"Size   : {size_mb:.2f} MB")
    print()
    print("── Next Steps ──")
    print("1. Open Postman → Import → Upload File → select the JSON above")
    print("2. Click 'Mock Servers' → 'Create Mock Server' → select this collection")
    print("3. Copy the mock server URL (e.g. https://xxxxxxxx.mock.pstmn.io)")
    print("4. Update the collection variable 'baseUrl' to that mock URL")
    print("5. Send requests — they will return the embedded example responses")
    print()
    print("To use with the VeloCloud Client code:")
    print(f'   address   => "<mock-server-host>"')
    print(f'   api_key   => "YOUR_POSTMAN_API_KEY"')
    print(f'   fabric_id => "{FABRIC_ID}"')


if __name__ == "__main__":
    main()
