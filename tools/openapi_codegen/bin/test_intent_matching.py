#!/usr/bin/env python3
"""Quick smoke test for intent-driven plugin matching."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "python"))

from netmri_sdn_openapi_codegen import (
    PluginFieldIntentCatalog,
    PluginCatalog,
    SpecParser,
    EndpointMatcher,
    RpcPayloadBuilder,
)


def main() -> None:
    root = Path(__file__).resolve().parents[3]

    # --- Intent catalog ---
    intent_cat = PluginFieldIntentCatalog(root_dir=str(root))
    print(f"Intent catalog loaded: {intent_cat.loaded()}")
    for name in ("IPAddress", "Forwarding", "Devices", "ifStatus", "MerakiNetworks"):
        entry = intent_cat.get(name)
        if entry:
            print(f"  {name}: {entry.get('apiRequiredFields')} | kw count={len(entry.get('apiResponseKeywords') or [])}")
        else:
            print(f"  {name}: MISSING")

    # --- Meraki spec ---
    spec_path = root / "Meraki-OpenAPI.json"
    if not spec_path.is_file():
        print(f"\nMeraki spec not found at {spec_path}, skipping endpoint tests.")
        return

    raw = spec_path.read_text(encoding="utf-8")
    spec = SpecParser().parse(raw)
    total_ops = sum(
        1 for p in spec["paths"].values()
        for m in ("get", "post", "put", "patch", "delete")
        if isinstance(p.get(m), dict)
    )
    print(f"\nMeraki operations: {total_ops}")

    matcher = EndpointMatcher(spec=spec, threshold=0.25)
    ops_with_schema = [op for op in matcher.operations if op.response_schema_keys]
    print(f"Operations with response schema keys: {len(ops_with_schema)}/{len(matcher.operations)}")
    for op in ops_with_schema[:3]:
        print(f"  {op.operation_id}: {op.response_schema_keys[:6]}")

    catalog = PluginCatalog(plugin_dir=str(root / "SDN" / "Plugins"))

    test_plugins = [
        ("IPAddress",      "apiRequiredFields: IPAddress, ifIndex  → expect interface/ip endpoint"),
        ("Forwarding",     "apiRequiredFields: vlan, MAC, port     → expect fdb/mac-table endpoint"),
        ("Devices",        "apiRequiredFields: IPAddress, NodeRole → expect device inventory endpoint"),
        ("MerakiNetworks", "apiRequiredFields: id, name, org_id   → expect networks endpoint"),
        ("ifStatus",       "apiRequiredFields: ifIndex, AdminStatus, OperStatus → expect port/interface endpoint"),
    ]

    for plugin_name, hint in test_plugins:
        tokens = catalog.tokenize_plugin_name(plugin_name)
        intent = intent_cat.get(plugin_name)
        matches = matcher.match_plugin(plugin_name, tokens, limit=3, plugin_intent=intent)
        print(f"\n=== Save{plugin_name} ({hint}) ===")
        print(f"    intent keywords count: {len(intent.get('apiResponseKeywords') or []) if intent else 0}")
        for m in matches:
            print(f"    score={m['score']:.3f}  {m['method'].upper():<7} {m['path']}")

    # --- Full payload build ---
    builder = RpcPayloadBuilder(matcher=matcher)
    plugins = catalog.list_plugins()
    # filter ACI plugins for Meraki
    plugins = [p for p in plugins if not p.lower().startswith("aci")]
    payload = builder.build(
        vendor="Meraki",
        plugins=plugins,
        tokenizer=catalog.tokenize_plugin_name,
        match_limit=5,
        intent_catalog=intent_cat,
    )
    stats = payload.get("stats") or {}
    print(f"\n=== Full Meraki payload stats ===")
    print(f"  totalPlugins:       {stats.get('totalPlugins')}")
    print(f"  matchedPlugins:     {stats.get('matchedPlugins')}")
    print(f"  skippedPlugins:     {stats.get('skippedPlugins')}")
    print(f"  selectedOperations: {stats.get('selectedOperations')}")
    print("\nTop-scored calls:")
    calls = sorted(payload.get("pluginCalls") or [], key=lambda c: c.get("score") or 0, reverse=True)
    for c in calls[:8]:
        print(f"  score={c['score']:.3f}  {c.get('method','').upper():<7} {c.get('path','')}")
        print(f"    plugins: {c.get('plugins')}")


if __name__ == "__main__":
    main()
