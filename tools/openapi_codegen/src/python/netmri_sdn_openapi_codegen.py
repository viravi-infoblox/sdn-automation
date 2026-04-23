#!/usr/bin/env python3

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_COLLECTION_PLAN: Dict[str, Any] = {
    "version": "1.0",
    "stages": [
        {
            "id": "org_discovery",
            "description": "Discover organizations/tenants",
            "requiredData": ["organization_id", "organization_name"],
        },
        {
            "id": "site_discovery",
            "description": "Discover sites per organization",
            "requiredData": ["site_id", "site_name", "organization_id"],
        },
        {
            "id": "device_inventory",
            "description": "Discover devices per site with core identity attributes",
            "requiredData": [
                "model",
                "ip_address",
                "mac_address",
                "device_type",
                "sw_version",
                "serial_number",
            ],
        },
        {
            "id": "device_state_and_tables",
            "description": "Collect forwarding/route/interface/performance/environment",
            "requiredData": [
                "forwarding_table",
                "route_table",
                "interface_table",
                "cpu_status",
                "memory_status",
                "fan_status",
            ],
        },
        {
            "id": "topology_and_endpoints",
            "description": "Collect neighbors and endpoint visibility",
            "requiredData": [
                "lldp",
                "cdp",
                "ap_devices",
                "wired_clients",
                "wireless_clients",
                "end_hosts",
            ],
        },
    ],
}

STANDARD_PAYLOAD_TEMPLATE: Dict[str, Any] = {
    "schema": {
        "name": "netmri-openapi-rpc-payload",
        "version": "1.0",
    },
    "manualReview": {
        "status": "pending",
        "reviewedBy": "",
        "reviewedAt": "",
        "notes": "",
    },
    "reviewQueue": {
        "lowConfidenceMappings": [],
        "skippedPlugins": [],
    },
    "stats": {
        "totalPlugins": 0,
        "matchedPlugins": 0,
        "skippedPlugins": 0,
        "selectedOperations": 0,
    },
    "pluginCalls": [],
    "skippedPlugins": [],
    "collectionPlan": DEFAULT_COLLECTION_PLAN,
}


def _new_payload_template(vendor: str) -> Dict[str, Any]:
    payload = copy.deepcopy(STANDARD_PAYLOAD_TEMPLATE)
    payload["vendor"] = vendor
    payload["generatedAt"] = time.asctime(time.gmtime()) + " UTC"
    return payload


def _expand_home(path: Optional[str]) -> str:
    if not path:
        return ""
    return os.path.expanduser(path)

def _default_plugin_dir() -> str:
    candidates = [
        "SDN/Plugins",
        "Controller/SDN/Plugins",
        os.path.join(os.path.expanduser("~"), "dev/NetworkAutomation/Subsystems/Core/perl/NetMRI/SDN/Plugins"),
    ]
    for path in candidates:
        if os.path.isdir(path):
            return path
    return "SDN/Plugins"


def _default_payload_dir(root_dir: str) -> str:
    return os.path.join(root_dir, "Payloads")


def _default_output_dir(root_dir: str) -> str:
    return os.path.join(root_dir, "Output")


class Fetcher:
    def __init__(self, timeout: int = 30, user_agent: str = "NetMRI-OpenAPI-Codegen/1.0") -> None:
        self.timeout = timeout
        self.user_agent = user_agent

    def fetch(self, source: str) -> str:
        if not source:
            raise ValueError("OpenAPI source is required")

        if re.match(r"^https?://", source, flags=re.IGNORECASE):
            req = urllib.request.Request(source, headers={"User-Agent": self.user_agent})
            with urllib.request.urlopen(req, timeout=self.timeout) as res:
                return res.read().decode("utf-8")

        return Path(source).read_text(encoding="utf-8")


class SpecParser:
    def parse(self, raw_text: str) -> Dict[str, Any]:
        if not raw_text:
            raise ValueError("OpenAPI content is empty")

        spec = self._parse_json(raw_text)
        if spec is None:
            spec = self._parse_yaml(raw_text)

        if not isinstance(spec, dict):
            raise ValueError("Unable to parse OpenAPI content as JSON or YAML")
        if not isinstance(spec.get("paths"), dict):
            raise ValueError("OpenAPI spec must contain a 'paths' object")

        return spec

    def _parse_json(self, raw_text: str) -> Optional[Dict[str, Any]]:
        try:
            parsed = json.loads(raw_text)
        except Exception:
            return None
        return parsed if isinstance(parsed, dict) else None

    def _parse_yaml(self, raw_text: str) -> Optional[Dict[str, Any]]:
        try:
            import yaml  # type: ignore
        except Exception:
            return None

        try:
            parsed = yaml.safe_load(raw_text)
        except Exception:
            return None
        return parsed if isinstance(parsed, dict) else None


class PluginCatalog:
    def __init__(self, plugin_dir: str = "SDN/Plugins") -> None:
        self.plugin_dir = plugin_dir

    def list_plugins(self) -> List[str]:
        if not os.path.isdir(self.plugin_dir):
            return []

        plugins: List[str] = []
        pattern = re.compile(r"^Save(.+)\.pm$")
        for root, _, files in os.walk(self.plugin_dir):
            for file_name in files:
                m = pattern.match(file_name)
                if m:
                    plugins.append(m.group(1))
        return sorted(set(plugins))

    def tokenize_plugin_name(self, plugin_name: str) -> List[str]:
        parts = re.split(r"(?=[A-Z])|[_\-]", plugin_name or "")
        return [p.lower() for p in parts if p]


class PluginRequiredFieldsCatalog:
    """Loads required_fields hashes from Save*.pm plugin modules.

    The parser extracts keys from:
      sub required_fields { return { field => 'regex', ... }; }
    """

    def __init__(self, plugin_dir: str = "SDN/Plugins") -> None:
        self.plugin_dir = plugin_dir
        self._catalog: Dict[str, List[str]] = {}
        self._load()

    def _load(self) -> None:
        if not os.path.isdir(self.plugin_dir):
            return

        pattern = re.compile(r"^Save(.+)\.pm$")
        for root, _, files in os.walk(self.plugin_dir):
            for file_name in files:
                m = pattern.match(file_name)
                if not m:
                    continue
                plugin = m.group(1)
                path = Path(root) / file_name
                fields = self._extract_required_fields(path)
                if fields:
                    self._catalog[plugin] = fields

    @staticmethod
    def _extract_required_fields(path: Path) -> List[str]:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return []

        sub_match = re.search(r"sub\s+required_fields\s*\{([\s\S]*?)\n\}", text, flags=re.IGNORECASE)
        if not sub_match:
            return []

        body = sub_match.group(1)
        hash_match = re.search(r"return\s*\{([\s\S]*?)\}\s*;", body, flags=re.IGNORECASE)
        if not hash_match:
            return []

        hash_body = hash_match.group(1)
        keys = re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*=>", hash_body)
        deduped: List[str] = []
        for key in keys:
            if key not in deduped:
                deduped.append(key)
        return deduped

    def get(self, plugin_name: str) -> List[str]:
        return list(self._catalog.get(plugin_name) or [])


class PluginFieldIntentCatalog:
    """Loads plugin-field-intent.json and provides per-plugin API field intent lookups.

    Each entry declares which fields must come from the API response (apiRequiredFields),
    optional extras (apiOptionalFields), and keywords that should match OpenAPI response
    schema property names or operation metadata (apiResponseKeywords).
    """

    def __init__(self, root_dir: str = ".") -> None:
        self._catalog: Dict[str, Dict[str, Any]] = {}
        self._load(root_dir)

    def _load(self, root_dir: str) -> None:
        candidates = [
            Path(root_dir) / "tools" / "openapi_codegen" / "templates" / "plugin-field-intent.json",
            Path(root_dir) / "templates" / "plugin-field-intent.json",
            Path(__file__).resolve().parents[2] / "templates" / "plugin-field-intent.json",
        ]
        for path in candidates:
            if path.is_file():
                try:
                    data = json.loads(path.read_text(encoding="utf-8"))
                    for entry in data.get("plugins") or []:
                        plugin = entry.get("plugin") or ""
                        if plugin:
                            self._catalog[plugin] = entry
                except Exception:
                    pass
                return

    def get(self, plugin_name: str) -> Optional[Dict[str, Any]]:
        """Return the intent entry for plugin_name (with or without the 'Save' prefix)."""
        return self._catalog.get(plugin_name) or self._catalog.get(f"Save{plugin_name}")

    def loaded(self) -> bool:
        return bool(self._catalog)


@dataclass
class Operation:
    method: str
    path: str
    operation_id: str
    summary: str
    description: str
    tags: str
    parameters: Dict[str, Any]
    examples: Dict[str, Any]
    response_schema_keys: List[str]


class EndpointMatcher:
    # Vendor-specific synonym expansion: when a term from the map appears in the
    # operation haystack, the associated generic terms are appended so that plugin
    # intent keywords can match.
    VENDOR_HAYSTACK_SYNONYMS: Dict[str, Dict[str, List[str]]] = {
        "velocloud": {
            "edge": ["device", "gateway", "node", "router", "switch", "inventory", "hardware", "serial", "model", "firmware", "ip_address", "mac", "status", "version", "sw_version", "role", "node_role", "controller"],
            "edges": ["devices", "gateways", "nodes", "inventory"],
            "enterprise": ["organization", "org", "tenant", "customer"],
            "enterprises": ["organizations", "orgs", "tenants", "customers"],
            "clientdevice": ["endpoint", "client", "host", "station", "mac_address", "workload"],
            "clientdevices": ["endpoints", "clients", "hosts", "stations"],
            "healthstats": ["cpu", "memory", "performance", "utilization", "health", "sensor", "environmental", "statistics"],
            "health": ["performance", "status", "monitoring", "utilization"],
            "bgpsession": ["bgp", "peer", "neighbor", "autonomous_system", "session"],
            "bgpsessions": ["bgp", "peers", "neighbors"],
            "link": ["interface", "port", "connection", "speed", "duplex"],
            "links": ["interfaces", "ports", "connections"],
            "route": ["routing", "destination", "next_hop", "nexthop", "prefix", "forwarding"],
            "routes": ["routing", "route", "forwarding", "nexthop"],
            "firewall": ["firewall", "policy", "acl", "security"],
            "alert": ["alarm", "event", "notification"],
            "alerts": ["alarms", "events", "notifications"],
            "application": ["app", "traffic", "flow"],
            "applications": ["apps", "traffic", "flows"],
            "configuration": ["config", "setting", "profile", "property", "attribute"],
            "configure": ["config", "setting", "profile", "property"],
            "monitor": ["monitoring", "statistics", "counters", "performance"],
            "network": ["network", "segment", "overlay", "vlan", "vni"],
            "vnf": ["virtual", "network_function", "service"],
            "cluster": ["ha", "redundancy", "group"],
            "site": ["location", "branch"],
            "gateway": ["gateway", "device", "controller", "node"],
            "customer": ["organization", "org", "tenant"],
            "sdwan": ["sdn", "sd_wan", "wan", "overlay"],
        },
    }

    def __init__(self, spec: Dict[str, Any], threshold: float = 0.25, vendor: str = "") -> None:
        self.spec = spec or {}
        self.threshold = threshold
        self.vendor = vendor or ""
        self.operations = self._collect_operations(self.spec)

    def _build_haystack(self, op: Operation) -> str:
        """Build a searchable text from operation metadata, enriched with vendor synonyms."""
        haystack = " ".join([
            op.operation_id, op.summary, op.description, op.tags, op.path,
            " ".join(op.response_schema_keys),
        ]).lower()
        if not self.vendor:
            return haystack
        synonyms = self.VENDOR_HAYSTACK_SYNONYMS.get(self.vendor.lower(), {})
        if not synonyms:
            return haystack
        extra: List[str] = []
        for term, expansions in synonyms.items():
            if term in haystack:
                extra.extend(expansions)
        if extra:
            haystack = haystack + " " + " ".join(extra)
        return haystack

    def match_plugin(self, plugin_name: str, plugin_tokens: List[str], limit: int = 1, plugin_intent: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        ranked: List[Dict[str, Any]] = []
        for op in self.operations:
            if not self._is_semantically_compatible(plugin_tokens, op, plugin_intent):
                continue
            score = self._score(plugin_name, plugin_tokens, op, plugin_intent)
            op_data = {
                "method": op.method,
                "path": op.path,
                "operationId": op.operation_id,
                "summary": op.summary,
                "description": op.description,
                "tags": op.tags,
                "parameters": op.parameters,
                "examples": op.examples,
                "responseSchemaKeys": op.response_schema_keys,
                "score": score,
            }
            ranked.append(op_data)

        ranked = sorted(
            ranked,
            key=lambda x: (
                self._method_priority(x.get("method")),
                self._collection_stage_priority(x.get("path")),
                x["score"],
            ),
            reverse=True,
        )
        # Prefer GET endpoints whenever at least one viable GET exists.
        # Use a slightly relaxed threshold for GET to avoid falling back to POST too early.
        get_threshold = max(0.1, self.threshold * 0.7)
        get_ranked = [r for r in ranked if (r.get("method") or "").lower() == "get" and r["score"] >= get_threshold]
        if get_ranked:
            return get_ranked[: max(1, limit)]

        ranked = [r for r in ranked if r["score"] >= self.threshold]
        return ranked[: max(1, limit)]

    @staticmethod
    def _method_priority(method: Optional[str]) -> int:
        order = {
            "get": 5,
            "delete": 4,
            "put": 3,
            "patch": 2,
            "post": 1,
        }
        return order.get((method or "").lower(), 0)

    def _collection_stage_priority(self, path: Optional[str]) -> int:
        p = (path or "").lower()
        v = self.vendor.lower() if self.vendor else ""

        # VeloCloud v2 collection flow priorities.
        if v == "velocloud":
            # Enterprise (org) listing is the entry point.
            if p.rstrip("/").endswith("/enterprises"):
                return 5
            # Edges list = primary device discovery.
            if "/edges/" in p or p.rstrip("/").endswith("/edges"):
                if not any(seg in p for seg in ("/healthstats", "/links", "/bgp", "/firewall", "/device", "/vnf", "/config")):
                    return 4
            # Client devices = endpoint/host discovery.
            if "/clientdevices" in p:
                return 3
            if "/enterprises/" in p:
                return 2
            return 0

        # Mist / generic SDN collection flow.
        if "/orgs/" in p and p.endswith("/sites"):
            return 5
        if "/orgs/" in p and "/stats/devices" in p:
            return 4
        if "/orgs/" in p and "/devices/search" in p:
            return 4
        if "/sites/" in p and "/stats/clients" in p:
            return 4
        if "/orgs/" in p and ("/stats/ports" in p or "/stats/mxedges" in p):
            return 3
        if "/orgs/" in p:
            return 2
        if "/sites/" in p:
            return 1
        return 0

    def _collect_operations(self, spec: Dict[str, Any]) -> List[Operation]:
        ops: List[Operation] = []
        for path in sorted((spec.get("paths") or {}).keys()):
            path_obj = (spec.get("paths") or {}).get(path) or {}
            path_level_params = path_obj.get("parameters") if isinstance(path_obj.get("parameters"), list) else []
            for method in ["get", "post", "put", "patch", "delete"]:
                op = path_obj.get(method)
                if not isinstance(op, dict):
                    continue

                tags = op.get("tags")
                tags_text = " ".join(tags) if isinstance(tags, list) else ""
                operation_id = op.get("operationId") or self._fallback_operation_id(method, path)
                ops.append(
                    Operation(
                        method=method,
                        path=path,
                        operation_id=operation_id,
                        summary=op.get("summary") or "",
                        description=op.get("description") or "",
                        tags=tags_text,
                        parameters=self._extract_parameters(op, path_level_params, path),
                        examples=self._extract_examples(op),
                        response_schema_keys=self._extract_response_schema_keys(op),
                    )
                )
        return ops

    def _extract_parameters(self, op: Dict[str, Any], path_level_params: List[Any], path: str) -> Dict[str, Any]:
        params: Dict[str, Any] = {"path": [], "query": [], "body": 0}

        def add_params(raw_params: Any) -> None:
            if not isinstance(raw_params, list):
                return
            for p in raw_params:
                if not isinstance(p, dict):
                    continue
                name = p.get("name")
                where = p.get("in") or ""
                if not name:
                    continue
                if where == "path" and name not in params["path"]:
                    params["path"].append(name)
                if where == "query" and name not in params["query"]:
                    params["query"].append(name)

        # Merge path-level and operation-level parameters so placeholders like {org_id}
        # are captured even when declared only at the path item level.
        add_params(path_level_params)
        add_params(op.get("parameters"))

        # Fallback: capture path placeholders directly from URI template for specs that rely on
        # implicit placeholders or unresolved parameter refs.
        for placeholder in re.findall(r"\{([^}]+)\}", path or ""):
            if placeholder and placeholder not in params["path"]:
                params["path"].append(placeholder)

        if isinstance(op.get("requestBody"), dict):
            params["body"] = 1
        return params

    def _extract_examples(self, op: Dict[str, Any]) -> Dict[str, Any]:
        request_example = None
        response_example = None
        response_status = None

        request_body = op.get("requestBody")
        if isinstance(request_body, dict):
            content = request_body.get("content")
            request_example = self._extract_content_example(content)

        responses = op.get("responses")
        if isinstance(responses, dict):
            # Prefer 2xx examples, then any available response example.
            status_candidates = [
                s for s in responses.keys() if isinstance(s, str) and re.match(r"^2\\d\\d$", s)
            ]
            status_candidates.sort()
            status_candidates.extend(
                [s for s in responses.keys() if isinstance(s, str) and s not in status_candidates]
            )
            for status in status_candidates:
                response_obj = responses.get(status)
                if not isinstance(response_obj, dict):
                    continue
                content = response_obj.get("content")
                candidate = self._extract_content_example(content)
                if candidate is not None:
                    response_example = candidate
                    response_status = status
                    break

        return {
            "request": request_example,
            "response": response_example,
            "responseStatus": response_status,
        }

    def _extract_content_example(self, content: Any) -> Any:
        if not isinstance(content, dict):
            return None

        media_candidates = [
            "application/json",
            "application/*+json",
        ] + sorted(content.keys())

        seen = set()
        for media_type in media_candidates:
            if media_type in seen:
                continue
            seen.add(media_type)

            # Handle wildcard preference for +json media types.
            if media_type == "application/*+json":
                for key in sorted(content.keys()):
                    if key.startswith("application/") and key.endswith("+json"):
                        candidate = self._extract_example_from_media(content.get(key))
                        if candidate is not None:
                            return candidate
                continue

            candidate = self._extract_example_from_media(content.get(media_type))
            if candidate is not None:
                return candidate

        return None

    def _extract_example_from_media(self, media_obj: Any) -> Any:
        if not isinstance(media_obj, dict):
            return None

        if "example" in media_obj:
            return media_obj.get("example")

        examples_obj = media_obj.get("examples")
        if isinstance(examples_obj, dict):
            for key in sorted(examples_obj.keys()):
                ex = examples_obj.get(key)
                if isinstance(ex, dict) and "value" in ex:
                    return ex.get("value")
                if ex is not None:
                    return ex

        return None

    def _extract_response_schema_keys(self, op: Dict[str, Any]) -> List[str]:
        """Collect all response schema property names from 2xx responses of an operation."""
        keys: List[str] = []
        responses = op.get("responses") or {}
        for status, resp_obj in responses.items():
            if not isinstance(resp_obj, dict):
                continue
            if not re.match(r"^2", str(status)):
                continue
            for media_obj in (resp_obj.get("content") or {}).values():
                if isinstance(media_obj, dict):
                    self._collect_schema_keys(media_obj.get("schema") or {}, keys, depth=0)
        return list(dict.fromkeys(keys))  # deduplicate, preserve order

    def _collect_schema_keys(self, schema: Any, keys: List[str], depth: int = 0) -> None:
        """Recursively collect property names from a JSON Schema object (max depth 5)."""
        if depth > 4 or not isinstance(schema, dict):
            return
        ref = schema.get("$ref")
        if ref and isinstance(ref, str):
            resolved = self._resolve_ref(ref)
            if resolved:
                self._collect_schema_keys(resolved, keys, depth + 1)
            return
        for key in (schema.get("properties") or {}).keys():
            if key not in keys:
                keys.append(key)
            self._collect_schema_keys((schema.get("properties") or {}).get(key) or {}, keys, depth + 1)
        items = schema.get("items")
        if isinstance(items, dict):
            self._collect_schema_keys(items, keys, depth + 1)
        for combinator in ("allOf", "anyOf", "oneOf"):
            for sub in (schema.get(combinator) or []):
                self._collect_schema_keys(sub, keys, depth + 1)

    def _resolve_ref(self, ref: str) -> Optional[Dict[str, Any]]:
        """Resolve a local JSON Pointer $ref (e.g. '#/components/schemas/Foo')."""
        if not ref.startswith("#/"):
            return None
        node: Any = self.spec
        for part in ref[2:].split("/"):
            if not isinstance(node, dict):
                return None
            node = node.get(part)
        return node if isinstance(node, dict) else None

    def _fallback_operation_id(self, method: str, path: str) -> str:
        op_id = f"{method}_{path}".lower()
        op_id = re.sub(r"\{([^}]+)\}", r"\1", op_id)
        op_id = re.sub(r"[^a-zA-Z0-9]+", "_", op_id)
        op_id = re.sub(r"^_+|_+$", "", op_id)
        return op_id or f"{method.lower()}_endpoint"

    def _score(self, plugin_name: str, plugin_tokens: List[str], op: Operation, plugin_intent: Optional[Dict[str, Any]] = None) -> float:
        haystack = self._build_haystack(op)

        if plugin_intent:
            intent_keywords = [k.lower() for k in (plugin_intent.get("apiResponseKeywords") or []) if k]
            required_fields = [f.lower() for f in (plugin_intent.get("apiRequiredFields") or []) if f]
            response_keys_lc = [k.lower() for k in op.response_schema_keys]

            matched_kw = sum(1 for kw in intent_keywords if kw in haystack)
            keyword_score = (matched_kw / len(intent_keywords)) if intent_keywords else 0.0

            if required_fields and response_keys_lc:
                matched_req = sum(
                    1 for f in required_fields
                    if any(f in k or k in f for k in response_keys_lc)
                )
                schema_score = matched_req / len(required_fields)
            else:
                schema_score = 0.0

            score = 0.6 * keyword_score + 0.4 * schema_score
            for kw in intent_keywords:
                if len(kw) >= 4 and kw in (op.operation_id or "").lower():
                    score += 0.1
                    break
            for kw in intent_keywords:
                if len(kw) >= 4 and kw in (op.path or "").lower():
                    score += 0.05
                    break
            return min(score, 1.5)

        # Fallback: name-token overlap scoring (used when no intent entry is available).
        overlap = 0
        for token in plugin_tokens or []:
            if len(token) < 2:
                continue
            if token in haystack:
                overlap += 1

        base = (overlap / len(plugin_tokens)) if plugin_tokens else 0.0
        bonus = 0.0
        plugin_flat = (plugin_name or "").lower()
        if plugin_flat and plugin_flat in (op.operation_id or "").lower():
            bonus += 0.2
        if plugin_flat and plugin_flat in (op.path or "").lower():
            bonus += 0.1

        return base + bonus

    def _is_semantically_compatible(self, plugin_tokens: List[str], op: Operation, plugin_intent: Optional[Dict[str, Any]] = None) -> bool:
        if plugin_intent:
            intent_keywords = [k.lower() for k in (plugin_intent.get("apiResponseKeywords") or []) if k]
            tokens = intent_keywords if intent_keywords else [t.lower() for t in (plugin_tokens or []) if t]
        else:
            tokens = [t.lower() for t in (plugin_tokens or []) if t]

        if not tokens:
            return True

        path_lc = (op.path or "").lower()
        haystack = self._build_haystack(op)

        stopwords = {
            "table", "object", "stats", "status", "config", "save", "sdn", "data",
            "device", "devices", "list", "get", "show",
        }
        strong_tokens = [t for t in tokens if len(t) >= 4 and t not in stopwords]

        # Require at least one strong semantic token to appear when possible.
        if strong_tokens and not any(t in haystack for t in strong_tokens):
            return False

        # Guardrail: constant catalog endpoints should only satisfy constant-like plugins.
        if "/const/" in path_lc:
            allowed = {"alarm", "event", "fingerprint", "const"}
            if not any(t in allowed for t in tokens):
                return False

        # Guardrail: tunnel stats endpoints should not satisfy unrelated plugins.
        if "/stats/tunnels" in path_lc:
            tunnel_like = {"tunnel", "vpn", "vrf", "bgp", "peer", "route"}
            if not any(t in tunnel_like for t in tokens):
                return False

        # Guardrail: asset-filter endpoints should map to asset/filter/inventory-like plugins only.
        if "/assetfilters" in path_lc:
            asset_like = {"asset", "filter", "inventory", "device"}
            if not any(t in asset_like for t in tokens):
                return False

        return True


class RpcPayloadBuilder:
    AUTO_GENERATED_FIELDS = {
        "deviceid",
        "sdndeviceid",
        "sdncontrollerid",
        "controllerid",
        "fabricid",
        "starttime",
        "endtime",
        "timestamp",
        "lasttimestamp",
        "rowid",
        "acibdid",
        "aciepgid",
        "sdninterfaceid",
    }

    def __init__(self, matcher: EndpointMatcher) -> None:
        self.matcher = matcher

    @staticmethod
    def _normalize_field_name(field: str) -> str:
        return re.sub(r"[^a-z0-9]", "", (field or "").lower())

    @classmethod
    def _required_api_fields(cls, required_fields: List[str]) -> List[str]:
        if not required_fields:
            return []
        filtered: List[str] = []
        for field in required_fields:
            norm = cls._normalize_field_name(field)
            if not norm:
                continue
            if norm in cls.AUTO_GENERATED_FIELDS:
                continue
            filtered.append(field)
        return filtered

    @classmethod
    def _missing_required_fields(cls, candidate: Dict[str, Any], required_fields: List[str]) -> List[str]:
        required_fields = cls._required_api_fields(required_fields)
        if not required_fields:
            return []

        response_keys = [k for k in (candidate.get("responseSchemaKeys") or []) if k]
        response_norm = [cls._normalize_field_name(k) for k in response_keys]

        missing: List[str] = []
        for req in required_fields:
            req_norm = cls._normalize_field_name(req)
            if not req_norm:
                continue
            if any(req_norm in key_norm or key_norm in req_norm for key_norm in response_norm if key_norm):
                continue
            missing.append(req)
        return missing

    @classmethod
    def _candidate_satisfies_required_fields(cls, candidate: Dict[str, Any], required_fields: List[str]) -> bool:
        return len(cls._missing_required_fields(candidate, required_fields)) == 0

    @classmethod
    def _required_fields_for_plugin(
        cls,
        plugin_name: str,
        plugin_intent: Optional[Dict[str, Any]],
        plugin_required_fields_catalog: Optional["PluginRequiredFieldsCatalog"],
    ) -> List[str]:
        plugin_required = plugin_required_fields_catalog.get(plugin_name) if plugin_required_fields_catalog else []
        if plugin_required:
            return cls._required_api_fields(plugin_required)
        if plugin_intent:
            return cls._required_api_fields([f for f in (plugin_intent.get("apiRequiredFields") or []) if f])
        return []

    def build(
        self,
        vendor: str,
        plugins: List[str],
        tokenizer=None,
        match_limit: int = 1,
        intent_catalog: Optional["PluginFieldIntentCatalog"] = None,
        plugin_required_fields_catalog: Optional["PluginRequiredFieldsCatalog"] = None,
    ) -> Dict[str, Any]:
        plugin_candidates: Dict[str, List[Dict[str, Any]]] = {}
        skipped_plugins: List[str] = []
        skipped_reasons: Dict[str, str] = {}

        for plugin in plugins:
            tokens = tokenizer(plugin) if tokenizer else []
            intent = intent_catalog.get(plugin) if intent_catalog else None
            matches = self.matcher.match_plugin(plugin, tokens, match_limit, plugin_intent=intent)
            if not matches:
                skipped_plugins.append(plugin)
                skipped_reasons[plugin] = "no_suitable_operation_match"
                continue

            required_fields = self._required_fields_for_plugin(plugin, intent, plugin_required_fields_catalog)
            if required_fields:
                filtered = [m for m in matches if self._candidate_satisfies_required_fields(m, required_fields)]
                # If the schema-based filter removes all matches (common with generic/paginated
                # response schemas like VeloCloud v2), fall back to the unfiltered list so that
                # keyword-based matching still produces results.
                matches = filtered if filtered else matches

            plugin_candidates[plugin] = matches

        # Greedy set-cover style selection: choose operations that satisfy the most remaining plugins,
        # with score as a tie-breaker, to minimize the number of API calls.
        remaining = set(plugin_candidates.keys())
        selected_ops: List[Dict[str, Any]] = []

        while remaining:
            op_buckets: Dict[str, Dict[str, Any]] = {}
            for plugin in list(remaining):
                for candidate in plugin_candidates.get(plugin, []):
                    op_id = candidate.get("operationId")
                    method = candidate.get("method")
                    path = candidate.get("path")
                    if not op_id or not method or not path:
                        continue
                    key = f"{op_id}|{method}|{path}"
                    bucket = op_buckets.setdefault(
                        key,
                        {
                            "operation": candidate,
                            "plugins": [],
                            "score_sum": 0.0,
                        },
                    )
                    bucket["plugins"].append(plugin)
                    bucket["score_sum"] += float(candidate.get("score") or 0.0)

            if not op_buckets:
                break

            best = max(
                op_buckets.values(),
                key=lambda b: (
                    EndpointMatcher._method_priority((b.get("operation") or {}).get("method")),
                    self.matcher._collection_stage_priority((b.get("operation") or {}).get("path")),
                    len(b["plugins"]),
                    b["score_sum"],
                ),
            )
            selected_ops.append(best)
            for plugin in best["plugins"]:
                remaining.discard(plugin)

        calls: List[Dict[str, Any]] = []
        total_plugins = max(1, len(plugins))
        for chosen in selected_ops:
            op = chosen["operation"]
            plugins_for_op = sorted(set(chosen["plugins"]))
            avg_score = float(chosen["score_sum"]) / max(1, len(plugins_for_op))
            method = op.get("method")
            coverage_score = len(plugins_for_op) / total_plugins
            call_id = f"CALL-{len(calls) + 1:03d}"
            path = op.get("path") or "/"
            op_method = (method or "GET").upper()

            # Build _developerGuide to help the user understand what to collect
            developer_guide = self._build_developer_guide(
                call_id=call_id,
                method=op_method,
                path=path,
                parameters=op.get("parameters") or {},
                response_schema_keys=op.get("responseSchemaKeys") or [],
                plugins_for_op=plugins_for_op,
                calls_so_far=calls,
                vendor=vendor,
            )

            calls.append(
                {
                    "callId": call_id,
                    "enabled": 1,
                    "plugins": plugins_for_op,
                    "operationId": op.get("operationId"),
                    "method": method,
                    "path": path,
                    "parameters": op.get("parameters"),
                    "apiExamples": op.get("examples") or {"request": None, "response": None, "responseStatus": None},
                    "customerData": {
                        "sampleResponse": None,
                        "sampleRequest": None,
                        "responseNotes": "",
                        "collectedAt": "",
                    },
                    "review": {
                        "status": "pending",
                        "action": "keep",
                        "notes": "",
                    },
                    "_developerGuide": developer_guide,
                    "_debug": {
                        "score": avg_score,
                        "coverageCount": len(plugins_for_op),
                        "coverageScore": coverage_score,
                        "matched": 1,
                    },
                }
            )

        covered_plugins = {p for call in calls for p in call.get("plugins", [])}
        skipped_plugins.extend([p for p in plugins if p not in covered_plugins and p not in skipped_plugins])
        skipped_plugins = sorted(set(skipped_plugins))

        review_low_confidence = [
            {
                "operationId": call.get("operationId"),
                "method": call.get("method"),
                "path": call.get("path"),
                "score": (call.get("_debug") or {}).get("score"),
                "coverageCount": (call.get("_debug") or {}).get("coverageCount"),
                "plugins": call.get("plugins", []),
            }
            for call in calls
            if float((call.get("_debug") or {}).get("score") or 0.0) < 0.9
        ]
        review_skipped = [
            {
                "plugin": plugin,
                "reason": skipped_reasons.get(plugin) or "no_suitable_operation_match",
            }
            for plugin in skipped_plugins
        ]

        payload = _new_payload_template(vendor)
        payload["pluginCalls"] = calls
        payload["skippedPlugins"] = skipped_plugins
        payload["reviewQueue"] = {
            "lowConfidenceMappings": review_low_confidence,
            "skippedPlugins": review_skipped,
        }
        payload["stats"] = {
            "totalPlugins": len(plugins),
            "matchedPlugins": len(covered_plugins),
            "skippedPlugins": len(skipped_plugins),
            "selectedOperations": len(calls),
        }
        return payload

    # ----- Developer Guide helpers -----

    @staticmethod
    def _build_developer_guide(
        call_id: str,
        method: str,
        path: str,
        parameters: Dict[str, Any],
        response_schema_keys: List[str],
        plugins_for_op: List[str],
        calls_so_far: List[Dict[str, Any]],
        vendor: str,
    ) -> Dict[str, Any]:
        """Build a _developerGuide block that explains how to collect data for this call."""

        # --- curlExample ---
        path_params = parameters.get("path") or []
        curl_path = path
        for pp in path_params:
            curl_path = curl_path.replace(f"{{{pp}}}", f"<{pp}>")
        if method == "GET":
            curl_example = f"curl -s -b cookies.txt 'https://{{orchestrator}}{curl_path}'"
        else:
            curl_example = (
                f"curl -s -b cookies.txt -X {method} "
                f"'https://{{orchestrator}}{curl_path}' "
                f"-H 'Content-Type: application/json' -d '{{}}'"
            )

        # --- expectedResponseShape ---
        # Build a skeletal { key: "type?" } object from the schema keys discovered by the parser
        shape: Dict[str, str] = {}
        for key in response_schema_keys[:20]:  # cap at 20 to keep it readable
            shape[key] = "..."
        expected_shape = shape if shape else "Paste one full JSON response object here"

        # --- fieldsWeNeed ---
        # Derive from plugin names — these are the DB columns the plugins will populate
        fields_we_need: List[str] = []
        plugin_field_hints: Dict[str, List[str]] = {
            "SaveDevices": ["name", "ipAddress", "macAddress", "model", "serialNumber", "softwareVersion", "status"],
            "SaveSystemInfo": ["name", "model", "serialNumber", "softwareVersion", "osVersion", "uptime"],
            "SaveInventory": ["model", "serialNumber", "description", "hardwareRevision"],
            "SaveDeviceProperty": ["name", "value (any device-level key-value pairs)"],
            "SaveifConfig": ["interfaceName", "ipAddress", "macAddress", "mtu", "speed", "adminStatus"],
            "SaveifStatus": ["interfaceName", "operStatus", "adminStatus", "speed"],
            "SaveifPerf": ["interfaceName", "inOctets", "outOctets", "inErrors", "outErrors"],
            "SaveIPAddress": ["ipAddress", "subnetMask", "interfaceName"],
            "SaveDeviceCpuStats": ["cpuIndex", "cpuBusyPct"],
            "SaveDeviceMemStats": ["memoryUsed", "memoryFree", "memoryTotal"],
            "SaveSdnNetworks": ["networkId", "networkName", "organizationId"],
            "SaveVeloCloudOrganizations": ["enterpriseId", "enterpriseName"],
            "SaveMerakiOrganizations": ["organizationId", "organizationName"],
            "SaveMistOrganizations": ["org_id", "name"],
            "SaveMerakiNetworks": ["networkId", "name", "organizationId"],
            "SaveMistNetworks": ["site_id", "name", "org_id"],
            "SaveSdnEndpoint": ["macAddress", "ipAddress", "hostname", "vlan"],
            "SaveEnvironmental": ["fanStatus", "powerSupplyStatus", "temperatureValue"],
            "SaveForwarding": ["destPrefix", "nextHop", "interface", "protocol"],
            "SaveCDP": ["localPort", "remoteDeviceId", "remotePort"],
            "SaveLLDP": ["localPort", "remoteDeviceId", "remotePort"],
            "SavebgpPeerTable": ["peerAddress", "peerAs", "state"],
            "SaveFirewall": ["ruleName", "action", "sourceAddress", "destAddress"],
        }
        for plugin in plugins_for_op:
            hints = plugin_field_hints.get(plugin) or plugin_field_hints.get(f"Save{plugin}")
            if hints:
                for h in hints:
                    if h not in fields_we_need:
                        fields_we_need.append(h)

        # --- dependsOn ---
        # Determine if this call requires outputs from previous calls
        depends_on: List[str] = []
        for pp in path_params:
            pp_lc = pp.lower()
            for prev_call in calls_so_far:
                prev_id = prev_call.get("callId", "")
                prev_path = (prev_call.get("path") or "").lower()
                # If this call's path param matches a concept from a previous call's path
                if any(seg in pp_lc for seg in ["enterprise", "org"]) and any(
                    seg in prev_path for seg in ["/enterprises", "/orgs"]
                ):
                    if prev_id not in depends_on:
                        depends_on.append(prev_id)
                elif any(seg in pp_lc for seg in ["site", "network"]) and any(
                    seg in prev_path for seg in ["/sites", "/networks"]
                ):
                    if prev_id not in depends_on:
                        depends_on.append(prev_id)
                elif any(seg in pp_lc for seg in ["edge", "device"]) and any(
                    seg in prev_path for seg in ["/edges", "/devices"]
                ):
                    if prev_id not in depends_on:
                        depends_on.append(prev_id)

        # --- fillInstructions ---
        fill_instructions = (
            f"1. Call the {vendor} API: {method} {path}\n"
            f"2. Copy the FULL JSON response body\n"
            f"3. Paste it into customerData.sampleResponse (replace null)\n"
            f"4. Set customerData.collectedAt to the current date"
        )
        if depends_on:
            fill_instructions = (
                f"0. First collect responses for: {', '.join(depends_on)}\n" + fill_instructions
            )

        return {
            "curlExample": curl_example,
            "expectedResponseShape": expected_shape,
            "fieldsWeNeed": fields_we_need if fields_we_need else ["(see response schema keys above)"],
            "dependsOn": depends_on if depends_on else None,
            "fillInstructions": fill_instructions,
        }


class ClientGenerator:
    @staticmethod
    def generate(vendor: str, rpc_payload: Dict[str, Any], root_dir: str = ".") -> str:
        template = ClientGenerator._load_template(root_dir)
        if template:
            return ClientGenerator._generate_from_template(vendor=vendor, rpc_payload=rpc_payload, template_text=template)
        return ClientGenerator._generate_default(vendor=vendor, rpc_payload=rpc_payload)

    @staticmethod
    def _pagination_config(rpc_payload: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Extract pagination configuration from the payload."""
        pag = rpc_payload.get("pagination")
        return pag if isinstance(pag, dict) and pag.get("strategy") else None

    @staticmethod
    def _extract_auth_config(rpc_payload: Dict[str, Any]) -> Dict[str, Any]:
        """Extract authentication configuration from the payload."""
        auth = rpc_payload.get("authentication")
        if not isinstance(auth, dict):
            return {"header": "Authorization", "prefix": "Bearer"}
        prop = auth.get("tokenPropagation") or {}
        fmt = prop.get("format") or "Bearer <Token-Value>"
        prefix = fmt.split()[0] if fmt else "Bearer"
        return {"header": prop.get("header") or "Authorization", "prefix": prefix}

    @staticmethod
    def _extract_api_version(rpc_payload: Dict[str, Any]) -> str:
        """Infer API version string from pluginCall paths."""
        for call in rpc_payload.get("pluginCalls") or []:
            path = call.get("path") or ""
            m = re.match(r"/api/([^/]+(?:/[^/]+)?)/", path)
            if m:
                return m.group(1)
        return "v1"

    @staticmethod
    def _common_path_prefix(rpc_payload: Dict[str, Any]) -> str:
        """Find the API base path prefix to strip for relative URIs (e.g. /api/sdwan/v2/)."""
        version = ClientGenerator._extract_api_version(rpc_payload)
        return f"/api/{version}/"

    @staticmethod
    def _render_private_helpers(vendor: str, pag: Optional[Dict[str, Any]]) -> str:
        """Generate vendor-specific private GET + paginated-GET helpers."""
        v = vendor.lower()

        get_helper = (
            f"sub _{v}_get {{\n"
            "    my ($self, $uri, $params) = @_;\n"
            "    $params //= {};\n"
            "    my $res = $self->get($uri, $self->{supported_version}, $params);\n"
            "    if ($res->{success} && exists $res->{data}) {\n"
            "        return $res->{data};\n"
            "    }\n"
            "    my $msg = $res->{data}{error}{message}\n"
            "           // $self->{response}{_content}\n"
            "           // 'Unknown error';\n"
            "    return (undef, $msg);\n"
            "}\n"
        )

        strategy = (pag.get("strategy") or "link_header").lower() if pag else "link_header"
        if strategy == "body_cursor":
            data_field = (pag or {}).get("dataField") or "data"
            cursor_field = (pag or {}).get("cursorField") or "metaData.nextPageLink"
            accessor_parts = cursor_field.split(".")
            perl_accessor = "".join(f"{{'{p}'}}" for p in accessor_parts)

            pages_helper = (
                f"\nsub _{v}_get_pages {{\n"
                "    my ($self, $uri, $params) = @_;\n"
                "    $params //= {};\n"
                "    my @all;\n"
                "    my $max  = $self->{max_iterations_for_paginated_data};\n"
                "    my $iter = 0;\n"
                "\n"
                "    while (1) {\n"
                f"        my ($body, $err) = $self->_{v}_get($uri, $params);\n"
                "        return (undef, $err) if defined $err;\n"
                "\n"
                f"        my $items = ref($body) eq 'HASH' ? $body->{{'{data_field}'}} : $body;\n"
                "        push @all, ref($items) eq 'ARRAY' ? @$items : $items if defined $items;\n"
                "\n"
                "        my $next;\n"
                "        if (ref($body) eq 'HASH') {\n"
                f"            $next = $body->{perl_accessor};\n"
                "        }\n"
                "        # Also check Link header as fallback\n"
                "        unless ($next) {\n"
                "            if (ref($self->{response}) && $self->{response}->can('header')) {\n"
                "                my $link = $self->{response}->header('link') // '';\n"
                "                ($next) = $link =~ m{\\<([^>]+)\\>\\s*;\\s*rel=[\"']?next[\"']?};\n"
                "            }\n"
                "        }\n"
                "        last unless $next;\n"
                "\n"
                "        if ($next =~ m{^https?://}) {\n"
                "            $uri = $next;\n"
                "            $params = {};\n"
                "        } else {\n"
                "            $params = ref($params) eq 'HASH' ? { %$params } : {};\n"
                "            $params->{nextPageLink} = $next;\n"
                "        }\n"
                "        last if ++$iter >= $max;\n"
                "    }\n"
                "\n"
                "    return \\@all;\n"
                "}\n"
            )
        else:
            pages_helper = (
                f"\nsub _{v}_get_pages {{\n"
                "    my ($self, $uri, $params) = @_;\n"
                "    $params //= {};\n"
                "    my @all;\n"
                "    my $max  = $self->{max_iterations_for_paginated_data};\n"
                "    my $iter = 0;\n"
                "\n"
                "    while (1) {\n"
                f"        my ($pool, $err) = $self->_{v}_get($uri, $params);\n"
                "        return (undef, $err) if defined $err;\n"
                "\n"
                "        push @all, ref($pool) eq 'ARRAY' ? @$pool : $pool;\n"
                "\n"
                "        my $next;\n"
                "        if (ref($self->{response}) && $self->{response}->can('header')) {\n"
                "            my $link = $self->{response}->header('link') // '';\n"
                "            ($next) = $link =~ m{\\<([^>]+)\\>\\s*;\\s*rel=[\"']?next[\"']?};\n"
                "        }\n"
                "        last unless $next;\n"
                "\n"
                "        $uri    = $next;\n"
                "        $params = {};\n"
                "        last if ++$iter >= $max;\n"
                "    }\n"
                "\n"
                "    return \\@all;\n"
                "}\n"
            )

        return get_helper + pages_helper

    @staticmethod
    def _render_pagination_method(pag: Dict[str, Any]) -> str:
        """Generate a collect_paginated method matching the vendor's pagination strategy."""
        strategy = (pag.get("strategy") or "").lower()
        max_pages = int(pag.get("maxPages") or 100)

        if strategy == "body_cursor":
            # VeloCloud-style: response body contains data[] + metaData.nextPageLink cursor
            data_field = pag.get("dataField") or "data"
            cursor_field = pag.get("cursorField") or "metaData.nextPageLink"
            cursor_param = pag.get("cursorQueryParam") or "nextPageLink"
            # Build nested accessor like $body->{metaData}{nextPageLink}
            accessor_parts = cursor_field.split(".")
            perl_accessor = "".join(f"{{'{p}'}}" for p in accessor_parts)
            return f"""sub collect_paginated {{
    my ($self, $method, $uri, $api_version, $params) = @_;
    my @all;
    my $max_pages = {max_pages};
    my $page = 0;

    while (1) {{
        my ($body, $err) = $self->api_request($method, $uri, $params, $api_version);
        return (undef, $err) if $err;

        # Extract data array from response body
        my $items = ref($body) eq 'HASH' ? $body->{{'{data_field}'}} : $body;
        push @all, ref($items) eq 'ARRAY' ? @$items : $items if defined $items;

        # Check for next-page cursor in response body
        my $next_cursor;
        if (ref($body) eq 'HASH') {{
            $next_cursor = $body->{perl_accessor};
        }}
        last unless defined $next_cursor && length $next_cursor;

        # Append cursor to query params for next request
        $params = ref($params) eq 'HASH' ? {{ %$params }} : {{}};
        $params->{{'{cursor_param}'}} = $next_cursor;

        last if ++$page >= $max_pages;
    }}

    return \\@all;
}}
"""
        elif strategy == "link_header":
            # Standard Link: <url>; rel="next" header pagination
            return f"""sub collect_paginated {{
    my ($self, $method, $uri, $api_version, $params) = @_;
    my @all;
    my $max_pages = {max_pages};
    my $page = 0;

    while (1) {{
        my ($pool, $err) = $self->api_request($method, $uri, $params, $api_version);
        return (undef, $err) if $err;

        push @all, ref($pool) eq 'ARRAY' ? @$pool : $pool if defined $pool;

        # Follow Link header rel=next
        my $next;
        if (ref($self->{{response}}) && $self->{{response}}->can('header')) {{
            my $link = $self->{{response}}->header('link') || '';
            ($next) = $link =~ /\\<([^>]+)\\>\\;\\s+rel\\=[\\"\\'\\"]?next[\\"\\'\\"]?/;
        }}
        last unless $next;

        $uri = $next;
        $params = {{}};
        last if ++$page >= $max_pages;
    }}

    return \\@all;
}}
"""
        elif strategy == "offset":
            page_size = int(pag.get("pageSize") or 100)
            offset_param = pag.get("offsetParam") or "offset"
            limit_param = pag.get("limitParam") or "limit"
            return f"""sub collect_paginated {{
    my ($self, $method, $uri, $api_version, $params) = @_;
    my @all;
    my $max_pages = {max_pages};
    my $page_size = {page_size};
    my $offset = 0;

    $params = ref($params) eq 'HASH' ? {{ %$params }} : {{}};

    while (1) {{
        $params->{{'{limit_param}'}} = $page_size;
        $params->{{'{offset_param}'}} = $offset;

        my ($pool, $err) = $self->api_request($method, $uri, $params, $api_version);
        return (undef, $err) if $err;

        my @items = ref($pool) eq 'ARRAY' ? @$pool : ($pool);
        push @all, @items;

        last if scalar(@items) < $page_size;

        $offset += $page_size;
        last if $offset / $page_size >= $max_pages;
    }}

    return \\@all;
}}
"""
        # Default: return None to keep the template's built-in pagination
        return ""

    @staticmethod
    def _generate_from_template(vendor: str, rpc_payload: Dict[str, Any], template_text: str) -> str:
        if not vendor:
            raise ValueError("vendor is required")
        if not isinstance(rpc_payload, dict):
            raise ValueError("rpc_payload is required")

        auth_cfg = ClientGenerator._extract_auth_config(rpc_payload)
        api_version = ClientGenerator._extract_api_version(rpc_payload)
        pag = ClientGenerator._pagination_config(rpc_payload)
        path_prefix = ClientGenerator._common_path_prefix(rpc_payload)

        seen = set()
        ops = []
        for call in rpc_payload.get("pluginCalls") or []:
            op_id = call.get("operationId")
            enabled = 1 if call.get("enabled") is None else int(bool(call.get("enabled")))
            matched = (call.get("_debug") or {}).get("matched", call.get("matched", 1))
            if enabled and matched and op_id and op_id not in seen:
                seen.add(op_id)
                ops.append(call)

        methods = [ClientGenerator._render_method(op, vendor=vendor, path_prefix=path_prefix) for op in ops]
        methods_text = "\n".join(methods) if methods else ClientGenerator._render_noop()

        # Add private GET helpers before the public API methods
        private_helpers = ClientGenerator._render_private_helpers(vendor, pag)

        rendered = template_text
        rendered = rendered.replace("__VENDOR__", vendor)
        rendered = rendered.replace("__API_VERSION__", api_version)
        rendered = rendered.replace("__BASE_URI_TEMPLATE__", "https://example.invalid/api/\\%version\\%/")
        rendered = rendered.replace("__AUTH_HEADER_NAME__", auth_cfg["header"])
        rendered = rendered.replace("__AUTH_MODE__", auth_cfg["prefix"].lower())

        # Replace the generic token_prefix logic with vendor-specific auth
        auth_prefix = auth_cfg["prefix"]
        rendered = re.sub(
            r"    # Normalize auth credentials.*?^\s*\}$",
            f"    # Vendor authentication format: {auth_prefix} <token>\n"
            f"    $args{{auth_token_request_header}} = '{auth_cfg['header']}';\n"
            f"    if (defined $args{{api_key}} && length $args{{api_key}}) {{\n"
            f"        $args{{api_key}} = \"{auth_prefix} $args{{api_key}}\"\n"
            f"            unless $args{{api_key}} =~ /^{auth_prefix} /i;\n"
            f"    }}",
            rendered,
            flags=re.S | re.M,
            count=1,
        )

        # Replace fabric_id-only validation with api_key+fabric_id
        rendered = rendered.replace(
            "    # Keep required parameters minimal for broad reuse.\n"
            "    $args{fabric_id} = defined $args{fabric_id} ? $args{fabric_id} : '';",
            "    for my $required (qw(api_key fabric_id)) {\n"
            f"        die \"NetMRI::HTTP::Client::{vendor}: required parameter '$required' is missing\\n\"\n"
            "            unless defined $args{$required} && length $args{$required};\n"
            "    }",
        )

        # Remove auth_mode and token_prefix lines from template since we hardcode auth
        rendered = re.sub(r"\s*\$args\{auth_mode\}.*\n", "\n", rendered)
        rendered = re.sub(r"\s*\$args\{token_prefix\}.*\n", "\n", rendered)

        # Inject private helpers + public methods in place of the template placeholder
        combined_methods = private_helpers + "\n" + methods_text
        rendered = re.sub(
            r"sub __operation_method_name__ \{\n.*?\n\}\n",
            lambda _m: combined_methods + "\n\n",
            rendered,
            flags=re.S,
            count=1,
        )

        # Replace collect_paginated with vendor-specific pagination when configured
        if pag:
            pag_method = ClientGenerator._render_pagination_method(pag)
            if pag_method:
                rendered = re.sub(
                    r"sub collect_paginated \{.*?\n\}\n",
                    pag_method,
                    rendered,
                    flags=re.S,
                    count=1,
                )

        return rendered if rendered.endswith("\n") else rendered + "\n"

    @staticmethod
    def _generate_default(vendor: str, rpc_payload: Dict[str, Any]) -> str:
        if not vendor:
            raise ValueError("vendor is required")
        if not isinstance(rpc_payload, dict):
            raise ValueError("rpc_payload is required")

        auth_cfg = ClientGenerator._extract_auth_config(rpc_payload)
        api_version = ClientGenerator._extract_api_version(rpc_payload)
        pag = ClientGenerator._pagination_config(rpc_payload)
        path_prefix = ClientGenerator._common_path_prefix(rpc_payload)
        auth_prefix = auth_cfg["prefix"]

        package = f"NetMRI::HTTP::Client::{vendor}"
        seen = set()
        ops = []
        for call in rpc_payload.get("pluginCalls") or []:
            op_id = call.get("operationId")
            enabled = 1 if call.get("enabled") is None else int(bool(call.get("enabled")))
            matched = (call.get("_debug") or {}).get("matched", call.get("matched", 1))
            if enabled and matched and op_id and op_id not in seen:
                seen.add(op_id)
                ops.append(call)

        methods = [ClientGenerator._render_method(op, vendor=vendor, path_prefix=path_prefix) for op in ops]
        methods_text = "\n".join(methods) if methods else ClientGenerator._render_noop()

        private_helpers = ClientGenerator._render_private_helpers(vendor, pag)

        return f"""package {package};

use strict;
use warnings;

use NetMRI::HTTP::Client::Generic;
use URI::Escape qw(uri_escape);
use base 'NetMRI::HTTP::Client::Generic';

my $default_api_version = '{api_version}';
my $default_base_uri    = 'https://example.invalid/api/%version%/';

sub new {{
    my $class = shift;
    my %args  = @_;

    for my $required (qw(api_key fabric_id)) {{
        die "{package}: required parameter '$required' is missing\\n"
            unless defined $args{{$required}} && length $args{{$required}};
    }}

    $args{{base}} ||= $args{{address}}
        ? "https://$args{{address}}/api/\\%version\\%/"
        : $default_base_uri;

    # Authentication: {auth_cfg['header']}: {auth_prefix} <token>
    $args{{auth_token_request_header}} = '{auth_cfg["header"]}';
    $args{{api_key}} = "{auth_prefix} $args{{api_key}}"
        unless $args{{api_key}} =~ /^{auth_prefix} /i;

    $args{{requests_per_second}} //= 3;

    my $self = $class->SUPER::new(%args);
    $self->{{fabric_id}}                        = $args{{fabric_id}};
    $self->{{supported_version}}                = $default_api_version;
    $self->{{max_iterations_for_paginated_data}} ||= 100;

    $self->base();
    return bless $self, $class;
}}

sub get_throttle_key {{
    my $self = shift;
    return $self->{{fabric_id}} || 'Global';
}}

sub too_many_requests_response {{
    my ($self, $res) = @_;
    return (
        !$res->{{success}}
        && defined $res->{{data}}{{error}}{{code}}
        && $res->{{data}}{{error}}{{code}} == 429
    ) ? 1 : 0;
}}

{private_helpers}

{methods_text}

1;
"""

    @staticmethod
    def _load_template(root_dir: str) -> str:
        candidates = [
            Path(root_dir) / "tools" / "openapi_codegen" / "templates" / "Phase2-Client-Template.pm",
            Path(root_dir) / "templates" / "Phase2-Client-Template.pm",
            Path(__file__).resolve().parents[2] / "templates" / "Phase2-Client-Template.pm",
        ]
        for path in candidates:
            if path.is_file():
                return path.read_text(encoding="utf-8")
        return ""

    @staticmethod
    def _render_noop() -> str:
        return """sub api_noop {
    my $self = shift;
    return (undef, 'No matched API operation was found in the RPC payload');
}
"""

    @staticmethod
    def _render_method(call: Dict[str, Any], vendor: str = "", path_prefix: str = "") -> str:
        name = _method_name(call.get("operationId"))
        http_method = (call.get("method") or "get").lower()
        path = call.get("path") or "/"
        v = vendor.lower() if vendor else ""

        # Use relative URI by stripping the common API prefix
        rel_path = path
        if path_prefix and path.startswith(path_prefix):
            rel_path = path[len(path_prefix):]
        if not rel_path:
            rel_path = "/"

        path_params = (call.get("parameters") or {}).get("path") or []
        has_path_params = any("{" + p + "}" in rel_path for p in path_params)

        # For simple GET methods with no or few path params, generate positional-style methods
        if http_method == "get" and len(path_params) <= 2 and v:
            return ClientGenerator._render_positional_get_method(
                name=name, rel_path=rel_path, path_params=path_params,
                vendor_lc=v, is_list=not has_path_params or rel_path.endswith("/") or "list" in name.lower(),
            )

        # Fallback: %args style with private helpers
        path_subst_lines: List[str] = []
        for param in path_params:
            placeholder = "{" + param + "}"
            if placeholder not in rel_path:
                continue
            path_subst_lines.append(f'    die "Missing required path parameter: {param}\\n" unless defined $args{{{param}}};')
            path_subst_lines.append(
                f'    $uri =~ s/\\Q{placeholder}\\E/uri_escape("$args{{{param}}}")/ge;'
            )
        path_subst = "\n".join(path_subst_lines)
        if path_subst:
            path_subst += "\n"

        if http_method in {"get", "delete"}:
            param_builder = "    my $params = $args{query} && ref($args{query}) eq 'HASH' ? $args{query} : {};"
        else:
            param_builder = "    my $params = $args{body} && ref($args{body}) eq 'HASH' ? $args{body} : {};"

        # Use private helper if available
        helper = f"$self->_{v}_get" if v and http_method == "get" else f"$self->perform_request('{http_method}'"

        if v and http_method == "get":
            return (
                f"sub {name} {{\n"
                "    my ($self, %args) = @_;\n"
                f"    my $uri = '{rel_path}';\n"
                f"{path_subst}"
                f"{param_builder}\n"
                f"    return $self->_{v}_get($uri, $params);\n"
                "}\n"
            )

        return (
            f"sub {name} {{\n"
            "    my ($self, %args) = @_;\n"
            f"    my $uri = '{rel_path}';\n"
            f"{path_subst}"
            f"{param_builder}\n"
            f"    return $self->perform_request('{http_method}', $uri, $self->{{supported_version}}, $params);\n"
            "}\n"
        )

    @staticmethod
    def _render_positional_get_method(name: str, rel_path: str, path_params: List[str], vendor_lc: str, is_list: bool) -> str:
        """Generate a positional-parameter GET method using the vendor's private helpers."""
        if not path_params:
            # No path params: simple call like get_enterprises($params)
            helper = f"_{vendor_lc}_get_pages" if is_list else f"_{vendor_lc}_get"
            return (
                f"sub {name} {{\n"
                "    my ($self, $params) = @_;\n"
                f"    return $self->{helper}('{rel_path}', $params);\n"
                "}\n"
            )

        # Build path with uri_escape substitution
        uri_parts = rel_path
        die_checks: List[str] = []
        sig_params: List[str] = []

        for param in path_params:
            placeholder = "{" + param + "}"
            if placeholder not in uri_parts:
                continue
            safe_var = f"${param}"
            sig_params.append(safe_var)
            die_checks.append(
                f'    die "{name}: {param} is required\\n"\n'
                f'        unless defined ${param} && length ${param};'
            )
            uri_parts = uri_parts.replace(placeholder, f"' . uri_escape(${param}) . '")

        sig = ", ".join(["$self"] + sig_params + ["$params"])
        helper = f"_{vendor_lc}_get_pages" if is_list else f"_{vendor_lc}_get"
        die_text = "\n".join(die_checks)

        return (
            f"sub {name} {{\n"
            f"    my ({sig}) = @_;\n"
            f"{die_text}\n"
            f"\n"
            f"    my $uri = '{uri_parts}';\n"
            f"    return $self->{helper}($uri, $params);\n"
            "}\n"
        )


class ControllerGenerator:
    @staticmethod
    def generate(vendor: str, rpc_payload: Dict[str, Any], root_dir: str = ".") -> str:
        template = ControllerGenerator._load_template(root_dir)
        if template:
            return ControllerGenerator._generate_from_template(vendor=vendor, rpc_payload=rpc_payload, template_text=template)
        return ControllerGenerator._generate_default(vendor=vendor, rpc_payload=rpc_payload)

    @staticmethod
    def _generate_from_template(vendor: str, rpc_payload: Dict[str, Any], template_text: str) -> str:
        if not vendor:
            raise ValueError("vendor is required")
        if not isinstance(rpc_payload, dict):
            raise ValueError("rpc_payload is required")

        return ControllerGenerator._render_controller(vendor=vendor, rpc_payload=rpc_payload, template_text=template_text)

    @staticmethod
    def _generate_default(vendor: str, rpc_payload: Dict[str, Any]) -> str:
        if not vendor:
            raise ValueError("vendor is required")
        if not isinstance(rpc_payload, dict):
            raise ValueError("rpc_payload is required")

        return ControllerGenerator._render_controller(
            vendor=vendor,
            rpc_payload=rpc_payload,
            template_text=ControllerGenerator._default_template(),
        )

    @staticmethod
    def _render_controller(vendor: str, rpc_payload: Dict[str, Any], template_text: str) -> str:
        ops = ControllerGenerator._selected_ops(rpc_payload)
        has_cdata = ControllerGenerator._has_customer_data(ops)
        api_methods = [ControllerGenerator._render_api_wrapper_method(op) for op in ops]
        api_methods_text = "\n".join(api_methods) if api_methods else ControllerGenerator._render_noop()

        if has_cdata:
            context_helpers_text = ""  # Not needed when generating production code
        else:
            context_helpers_text = ControllerGenerator._render_context_helpers()

        collection_methods = ControllerGenerator._build_collection_methods(vendor=vendor, ops=ops, rpc_payload=rpc_payload)
        collection_methods_text = "\n\n".join(method["text"] for method in collection_methods)
        obtain_everything_body = ControllerGenerator._render_obtain_everything_body(
            vendor=vendor,
            method_names=[method["name"] for method in collection_methods],
            has_customer_data=has_cdata,
        )

        utility_methods = ControllerGenerator._render_utility_methods(vendor) if has_cdata else ""

        rendered = template_text
        rendered = rendered.replace("__VENDOR__", vendor)
        rendered = rendered.replace("__VENDOR_DISPLAY_NAME__", _vendor_display_name(vendor))
        rendered = rendered.replace("__CONTEXT_HELPERS__", context_helpers_text)
        rendered = rendered.replace("__OBTAIN_EVERYTHING_BODY__", obtain_everything_body)
        rendered = rendered.replace("__COLLECTION_METHODS__", collection_methods_text)
        rendered = rendered.replace("__API_WRAPPER_METHODS__", api_methods_text + "\n" + utility_methods)
        return rendered if rendered.endswith("\n") else rendered + "\n"

    @staticmethod
    def _load_template(root_dir: str) -> str:
        candidates = [
            Path(root_dir) / "tools" / "openapi_codegen" / "templates" / "Phase2-Controller-Template.pm",
            Path(root_dir) / "templates" / "Phase2-Controller-Template.pm",
            Path(__file__).resolve().parents[2] / "templates" / "Phase2-Controller-Template.pm",
        ]
        for path in candidates:
            if path.is_file():
                return path.read_text(encoding="utf-8")
        return ""

    @staticmethod
    def _default_template() -> str:
        return """package NetMRI::SDN::__VENDOR__;

use strict;
use warnings;
use Encode;
use Data::Dumper;
use NetMRI::SDN::Base;
use NetMRI::Util::Date;
use NetMRI::Util::Network qw(netmaskFromPrefix maskStringFromPrefix InetAddr);
use base 'NetMRI::SDN::Base';

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    $self->{vendor_name} = '__VENDOR_DISPLAY_NAME__';
    $self->{SaveDevices_unique_fieldname} = 'Serial';
    return bless $self, $class;
}

sub getApiClient {
    my $self = shift;
    my $api_helper = $self->SUPER::getApiClient();
    unless (ref($api_helper)) {
        $self->{logger}->error('__VENDOR__[' . ($self->{fabric_id} // '') . '] getApiClient: Error getting the API Client');
        return undef;
    }
    return $api_helper;
}

sub loadSdnDevices {
    my $self = shift;

    $self->{logger}->info('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: started');

    my $sql = $self->{sql};
    my $device_plugin = $self->getPlugin('SaveDevices');
    my $query;

    $self->{dn} = '' unless defined $self->{dn};

    if ($self->{dn} eq '') {
        $query = 'select * from ' . $device_plugin->target_table() . ' where SdnControllerId=' . $sql->escape($self->{fabric_id});
    }
    else {
        $query = 'select * from ' . $device_plugin->target_table() . ' where SdnDeviceDN = ' . $sql->escape($self->{dn}) . ' and SdnControllerId=' . $sql->escape($self->{fabric_id});
    }

    my $sdn_devices = $sql->table($query, AllowNoRows => 1, RefWanted => 1);
    unless (@$sdn_devices) {
        $self->{logger}->error('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: No devices for FabricID');
        return;
    }

    $self->{logger}->info('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: ' . scalar(@$sdn_devices) . ' entries');
    $self->{logger}->debug(Dumper($sdn_devices)) if ($self->{logger}->{Debug} && scalar(@$sdn_devices));
    $self->{logger}->info('__VENDOR__[' . ($self->{fabric_id} // '') . '] loadSdnDevices: finished');

    return $sdn_devices;
}

__CONTEXT_HELPERS__

sub obtainEverything {
__OBTAIN_EVERYTHING_BODY__
}

__COLLECTION_METHODS__

__API_WRAPPER_METHODS__

sub handle_error {
    my ($self, $resp, $datapoint, $dataset) = @_;
    my $err_text = '__VENDOR__ ' . $datapoint . ' failed';
    $err_text .= ' for device ' . $self->{dn} if defined $self->{dn} && length $self->{dn};
    $err_text .= ': ' . Dumper($resp) if defined $resp;
    $self->{logger}->warn($err_text) if $self->{logger};

    if ($dataset && $self->can('updateDataCollectionStatus')) {
        $self->updateDataCollectionStatus($dataset, 'Error');
    }
}

1;
"""

    @staticmethod
    def _selected_ops(rpc_payload: Dict[str, Any]) -> List[Dict[str, Any]]:
        seen = set()
        ops = []
        for call in rpc_payload.get("pluginCalls") or []:
            op_id = call.get("operationId")
            enabled = 1 if call.get("enabled") is None else int(bool(call.get("enabled")))
            matched = (call.get("_debug") or {}).get("matched", call.get("matched", 1))
            if enabled and matched and op_id and op_id not in seen:
                seen.add(op_id)
                ops.append(call)
        return ops

    @staticmethod
    def _render_api_wrapper_method(call: Dict[str, Any]) -> str:
        name = _method_name(call.get("operationId"))
        helper_name = f"api_{name}"
        return f"""sub {helper_name} {{
    my ($self, %args) = @_;
    return $self->getApiClient()->{name}(%args);
}}
"""

    @staticmethod
    def _build_collection_methods(vendor: str, ops: List[Dict[str, Any]], rpc_payload: Optional[Dict[str, Any]] = None) -> List[Dict[str, str]]:
        method_specs = [
            {
                "name": "obtainOrganizationsAndNetworks",
                "plugin_tokens": ["Organizations", "Networks", "SdnNetworks"],
                "args": "my $self = shift;",
                "returns": "return { organizations => \\@organization_rows, networks => \\@network_rows };",
                "purpose": "Collect organizations, sites, and SDN network mappings.",
                "save_hints": [f"save{vendor}Organizations", f"save{vendor}Networks", "saveSdnNetworks"],
                "datasets": [
                    {"var": "$organization_rows", "save": f"save{vendor}Organizations", "kind": "scalar_arrayref"},
                    {"var": "$network_rows", "save": f"save{vendor}Networks", "kind": "scalar_arrayref"},
                    {"var": "$sdn_network_rows", "save": "saveSdnNetworks", "kind": "scalar_arrayref"},
                ],
            },
            {
                "name": "getDevices",
                "plugin_tokens": ["Devices", "Inventory", "SdnEndpoint"],
                "args": "my $self = shift;",
                "returns": "return \\@device_rows;",
                "purpose": "Build and return SaveDevices rows for the current fabric.",
                "save_hints": ["saveDevices via obtainDevices() from NetMRI::SDN::Base"],
                "datasets": [
                    {"var": "$device_rows", "kind": "scalar_arrayref"},
                ],
            },
            {
                "name": "obtainSystemInfo",
                "plugin_tokens": ["SystemInfo", "Inventory", "DeviceProperty"],
                "args": "my ($self, $sdn_devices) = @_;",
                "returns": "return;",
                "purpose": "Collect system, inventory, and device property datasets for loaded devices.",
                "save_hints": ["saveSystemInfo", "saveInventory", "saveDeviceProperty"],
                "datasets": [
                    {"var": "$system_info", "save": "saveSystemInfo", "kind": "hashref"},
                    {"var": "$inventory_rows", "save": "saveInventory", "kind": "scalar_arrayref"},
                    {"var": "$device_property_rows", "save": "saveDeviceProperty", "kind": "scalar_arrayref"},
                ],
            },
            {
                "name": "obtainPerformance",
                "plugin_tokens": ["Performance", "DeviceCpuStats", "DeviceMemStats", "Firewall", "ifPerf"],
                "args": "my ($self, $sdn_devices) = @_;",
                "returns": "return;",
                "purpose": "Collect performance, CPU, memory, and related counters.",
                "save_hints": ["savePerformance", "saveDeviceCpuStats", "saveDeviceMemStats", "saveFirewall", "saveifPerf"],
                "datasets": [
                    {"var": "$performance_rows", "save": "savePerformance", "kind": "scalar_arrayref"},
                    {"var": "$device_cpu_rows", "save": "saveDeviceCpuStats", "kind": "scalar_arrayref"},
                    {"var": "$device_mem_rows", "save": "saveDeviceMemStats", "kind": "scalar_arrayref"},
                    {"var": "$firewall_rows", "save": "saveFirewall", "kind": "scalar_arrayref"},
                    {"var": "$if_perf_rows", "save": "saveifPerf", "kind": "scalar_arrayref"},
                ],
            },
            {
                "name": "obtainEnvironment",
                "plugin_tokens": ["Environmental", "hrStorageTable"],
                "args": "my ($self, $sdn_devices) = @_;",
                "returns": "return;",
                "purpose": "Collect environmental and storage state for loaded devices.",
                "save_hints": ["saveEnvironmental", "savehrStorageTable"],
                "datasets": [
                    {"var": "$environment_rows", "save": "saveEnvironmental", "kind": "scalar_arrayref"},
                    {"var": "$hr_storage_rows", "save": "savehrStorageTable", "kind": "scalar_arrayref"},
                ],
            },
            {
                "name": "obtainInterfaces",
                "plugin_tokens": ["ifConfig", "ifStatus", "ifPerf", "SwitchPortObject", "SdnFabricInterface", "VlanObject", "VlanTrunkPortTable", "dot1dBasePortTable"],
                "args": "my ($self, $sdn_devices) = @_;",
                "returns": "return;",
                "purpose": "Collect interface, switchport, and VLAN datasets for loaded devices.",
                "save_hints": ["saveifConfig", "saveifStatus", "saveifPerf", "saveSwitchPortObject", "saveSdnFabricInterface", "saveVlanObject", "saveVlanTrunkPortTable", "savedot1dBasePortTable"],
                "datasets": [
                    {"var": "$if_config_rows", "save": "saveifConfig", "kind": "scalar_arrayref"},
                    {"var": "$if_status_rows", "save": "saveifStatus", "kind": "scalar_arrayref"},
                    {"var": "$if_perf_rows", "save": "saveifPerf", "kind": "scalar_arrayref"},
                    {"var": "$switch_port_rows", "save": "saveSwitchPortObject", "kind": "scalar_arrayref"},
                    {"var": "$sdn_fabric_interface_rows", "save": "saveSdnFabricInterface", "kind": "scalar_arrayref"},
                    {"var": "$vlan_rows", "save": "saveVlanObject", "kind": "scalar_arrayref"},
                    {"var": "$vlan_trunk_rows", "save": "saveVlanTrunkPortTable", "kind": "scalar_arrayref"},
                    {"var": "$dot1d_base_port_rows", "save": "savedot1dBasePortTable", "kind": "scalar_arrayref"},
                ],
            },
            {
                "name": "obtainTopologyAndEndpoints",
                "plugin_tokens": ["LLDP", "CDP", "SdnEndpoint", "MistSdnEndpoint", "bsnAPTable", "bsnMobileStationTable"],
                "args": "my ($self, $sdn_devices) = @_;",
                "returns": "return;",
                "purpose": "Collect topology, AP, and endpoint visibility datasets.",
                "save_hints": ["saveLLDP", "saveCDP", "saveSdnEndpoint", "saveMistSdnEndpoint", "savebsnAPTable", "savebsnMobileStationTable"],
                "datasets": [
                    {"var": "$lldp_rows", "save": "saveLLDP", "kind": "scalar_arrayref"},
                    {"var": "$cdp_rows", "save": "saveCDP", "kind": "scalar_arrayref"},
                    {"var": "$sdn_endpoint_rows", "save": "saveSdnEndpoint", "kind": "scalar_arrayref"},
                    {"var": "$mist_sdn_endpoint_rows", "save": "saveMistSdnEndpoint", "kind": "scalar_arrayref"},
                    {"var": "$bsn_ap_rows", "save": "savebsnAPTable", "kind": "scalar_arrayref"},
                    {"var": "$bsn_mobile_station_rows", "save": "savebsnMobileStationTable", "kind": "scalar_arrayref"},
                ],
            },
        ]

        methods: List[Dict[str, str]] = []
        for spec in method_specs:
            matched_ops = ControllerGenerator._match_ops_by_plugins(ops, spec["plugin_tokens"])
            if not matched_ops:
                continue
            methods.append(
                {
                    "name": spec["name"],
                    "text": ControllerGenerator._render_collection_method(
                        vendor=vendor,
                        name=spec["name"],
                        signature=spec["args"],
                        purpose=spec["purpose"],
                        matched_ops=matched_ops,
                        save_hints=spec["save_hints"],
                        datasets=spec.get("datasets") or [],
                        return_statement=spec["returns"],
                    ),
                }
            )
        return methods

    @staticmethod
    def _match_ops_by_plugins(ops: List[Dict[str, Any]], plugin_tokens: List[str]) -> List[Dict[str, Any]]:
        matches: List[Dict[str, Any]] = []
        seen: set[str] = set()
        for op in ops:
            plugins = [str(plugin) for plugin in (op.get("plugins") or []) if plugin]
            include = False
            for plugin in plugins:
                plugin_lc = plugin.lower()
                for token in plugin_tokens:
                    token_lc = token.lower()
                    if plugin_lc == token_lc or plugin_lc.endswith(token_lc) or token_lc in plugin_lc:
                        include = True
                        break
                if include:
                    break
            op_id = str(op.get("operationId") or "")
            if include and op_id and op_id not in seen:
                seen.add(op_id)
                matches.append(op)
        return matches

    @staticmethod
    def _extract_customer_response_keys(call: Dict[str, Any]) -> List[str]:
        """Extract field names from customerData.sampleResponse for transform generation."""
        customer = call.get("customerData")
        if not isinstance(customer, dict):
            return []
        sample = customer.get("sampleResponse")
        if sample is None:
            return []
        if isinstance(sample, list) and sample:
            sample = sample[0]
        if isinstance(sample, dict):
            return list(sample.keys())
        return []

    @staticmethod
    def _has_customer_data(matched_ops: List[Dict[str, Any]]) -> bool:
        """Return True when at least one matched operation has customerData.sampleResponse."""
        for op in matched_ops:
            if ControllerGenerator._extract_customer_response_keys(op):
                return True
        return False

    @staticmethod
    def _render_customer_data_transform(call: Dict[str, Any], indent: str = "        ") -> List[str]:
        """Generate Perl hash-slice transform lines from customerData.sampleResponse keys."""
        keys = ControllerGenerator._extract_customer_response_keys(call)
        if not keys:
            return []
        helper_name = f"api_{_method_name(call.get('operationId'))}"
        lines = [
            f"{indent}# Response fields from customer data for {helper_name}():",
            f"{indent}# Available keys: {', '.join(keys[:20])}",
        ]
        return lines

    @staticmethod
    def _render_collection_method(
        vendor: str,
        name: str,
        signature: str,
        purpose: str,
        matched_ops: List[Dict[str, Any]],
        save_hints: List[str],
        datasets: List[Dict[str, str]],
        return_statement: str,
    ) -> str:
        has_cdata = ControllerGenerator._has_customer_data(matched_ops)

        # When customer data is available, generate production-ready methods
        if has_cdata:
            production = ControllerGenerator._render_production_method(
                vendor=vendor, name=name, signature=signature, purpose=purpose,
                matched_ops=matched_ops, save_hints=save_hints, datasets=datasets,
                return_statement=return_statement,
            )
            if production:
                return production

        # Fallback: skeleton mode
        candidate_lines = []
        for op in matched_ops:
            helper_name = f"api_{_method_name(op.get('operationId'))}"
            plugins = ", ".join(op.get("plugins") or []) or "no plugins"
            placeholders = ", ".join(ControllerGenerator._path_placeholders_from_call(op)) or "none"
            candidate_lines.append(
                f"    # - $self->{helper_name}(%args); # {(op.get('method') or 'get').upper()} {op.get('path') or '/'} [{plugins}] path_params=[{placeholders}]"
            )

        save_hint_lines = [f"    # - {hint}" for hint in save_hints]
        preflight_lines: List[str] = []
        if "$sdn_devices" in signature:
            preflight_lines.append("    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;")

        dataset_init_lines = ControllerGenerator._render_dataset_initializers(datasets)
        loop_lines = ControllerGenerator._render_collection_loop(name=name, signature=signature, matched_ops=matched_ops)
        save_lines = ControllerGenerator._render_dataset_save_calls(datasets)

        lines = [
            f"sub {name} {{",
            f"    {signature}",
            "",
            f'    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] {name}: started");',
        ]
        lines.extend(preflight_lines)
        lines.extend(dataset_init_lines)
        if dataset_init_lines:
            lines.append("")
        lines.extend(
            [
                "    my $api_helper = $self->getApiClient();",
                "    unless ($api_helper) {",
                f'        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] {name}: Error getting the API Client");',
                f"        {return_statement}",
                "    }",
                "",
            ]
        )
        lines.extend(
            [
                f"    # {purpose}",
                "    # Candidate API helpers for this dataset:",
            ]
        )
        lines.extend(candidate_lines or ["    # - No approved API helper was mapped for this dataset."])
        lines.extend(["    # Persist transformed rows using:"])
        lines.extend(save_hint_lines)
        if loop_lines:
            lines.extend(["", *loop_lines])
        if save_lines:
            lines.extend(["", *save_lines])

        lines.append(f'    $self->{{logger}}->warn("{vendor}[$self->{{fabric_id}}] {name}: generated skeleton requires vendor-specific transforms");')
        lines.extend(
            [
                f'    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] {name}: finished");',
                f"    {return_statement}",
                "}",
            ]
        )
        return "\n".join(lines)

    @staticmethod
    def _render_production_method(
        vendor: str,
        name: str,
        signature: str,
        purpose: str,
        matched_ops: List[Dict[str, Any]],
        save_hints: List[str],
        datasets: List[Dict[str, str]],
        return_statement: str,
    ) -> Optional[str]:
        """Generate a production-ready collection method using sampleResponse field names."""

        if name == "obtainOrganizationsAndNetworks":
            return ControllerGenerator._render_prod_orgs(vendor, matched_ops, save_hints)
        elif name == "getDevices":
            return ControllerGenerator._render_prod_devices(vendor, matched_ops)
        elif name == "obtainSystemInfo":
            return ControllerGenerator._render_prod_system_info(vendor, matched_ops)
        elif name == "obtainInterfaces":
            return ControllerGenerator._render_prod_interfaces(vendor, matched_ops)
        elif name == "obtainPerformance":
            return ControllerGenerator._render_prod_performance(vendor, matched_ops)
        elif name == "obtainEnvironment":
            return ControllerGenerator._render_prod_environment(vendor, matched_ops)
        elif name == "obtainTopologyAndEndpoints":
            return ControllerGenerator._render_prod_topology(vendor, matched_ops)
        return None

    @staticmethod
    def _sample_data_keys(call: Dict[str, Any]) -> List[str]:
        """Get the data record keys from a call's sampleResponse.data[0]."""
        customer = call.get("customerData")
        if not isinstance(customer, dict):
            return []
        sample = customer.get("sampleResponse")
        if isinstance(sample, dict) and "data" in sample:
            data = sample["data"]
            if isinstance(data, list) and data and isinstance(data[0], dict):
                return list(data[0].keys())
        if isinstance(sample, list) and sample and isinstance(sample[0], dict):
            return list(sample[0].keys())
        return []

    @staticmethod
    def _find_op_by_hint(matched_ops: List[Dict[str, Any]], hints: List[str]) -> Optional[Dict[str, Any]]:
        """Find the first operation whose operationId or path contains any hint substring."""
        for op in matched_ops:
            op_id = (op.get("operationId") or "").lower()
            path = (op.get("path") or "").lower()
            for hint in hints:
                h = hint.lower()
                if h in op_id or h in path:
                    return op
        return matched_ops[0] if matched_ops else None

    @staticmethod
    def _render_prod_orgs(vendor: str, matched_ops: List[Dict[str, Any]], save_hints: List[str]) -> str:
        """Generate production obtainOrganizationsAndNetworks."""
        org_op = ControllerGenerator._find_op_by_hint(matched_ops, ["enterprise", "organization", "list_enterprise"])
        if not org_op:
            return ""
        client_method = _method_name(org_op.get("operationId"))
        keys = ControllerGenerator._sample_data_keys(org_op)

        # Detect key field names from sample data
        id_field = "logicalId" if "logicalId" in keys else "id"
        name_field = "name" if "name" in keys else "domain" if "domain" in keys else "id"

        return f"""sub obtainOrganizationsAndNetworks {{
    my $self = shift;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainOrganizationsAndNetworks: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] obtainOrganizationsAndNetworks: no API client");
        return;
    }}

    my ($enterprises, $err) = $api_helper->{client_method}();
    unless (defined $enterprises) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] obtainOrganizationsAndNetworks: {client_method} failed: " . ($err // ''));
        return;
    }}

    $self->{{logger}}->debug("{vendor}[$self->{{fabric_id}}] obtainOrganizationsAndNetworks: received " . scalar(@$enterprises) . " enterprises");
    $self->{{logger}}->debug(Dumper($enterprises)) if $self->{{logger}}->{{Debug}};

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@org_rows, @sdn_net_rows);

    foreach my $ent (@$enterprises) {{
        next unless ref($ent) eq 'HASH';
        next unless $ent->{{'{id_field}'}} && $ent->{{'{name_field}'}};

        push @org_rows, {{
            id        => $ent->{{'{id_field}'}},
            name      => Encode::decode('UTF-8', $ent->{{'{name_field}'}}, Encode::FB_DEFAULT),
            fabric_id => $self->{{fabric_id}},
            StartTime => $timestamp,
            EndTime   => $timestamp,
        }};

        push @sdn_net_rows, {{
            sdn_network_key  => $ent->{{'{id_field}'}},
            sdn_network_name => $ent->{{'{name_field}'}},
            fabric_id        => $self->{{fabric_id}},
            StartTime        => $timestamp,
            EndTime          => $timestamp,
        }};
    }}

    if (@org_rows) {{
        $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainOrganizationsAndNetworks: saving " . scalar(@org_rows) . " organizations");
        $self->save{vendor}Organizations(\\@org_rows);
    }}

    if (@sdn_net_rows) {{
        $self->saveSdnNetworks(\\@sdn_net_rows);
    }}

    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainOrganizationsAndNetworks: finished");
    return $enterprises;
}}"""

    @staticmethod
    def _render_prod_devices(vendor: str, matched_ops: List[Dict[str, Any]]) -> str:
        """Generate production obtainDevices + getDevices."""
        # Find best edge/device endpoint — prefer "edge" or "client_device" endpoints over tunnels
        dev_op = None
        for hint_list in [["client_device", "clientdevice"], ["list_enterprise_edge", "edges"], ["edge"]]:
            dev_op = ControllerGenerator._find_op_by_hint(matched_ops, hint_list)
            if dev_op:
                break
        if not dev_op:
            dev_op = matched_ops[0] if matched_ops else None
        if not dev_op:
            return ""
        client_method = _method_name(dev_op.get("operationId"))
        keys = ControllerGenerator._sample_data_keys(dev_op)
        path_params = ControllerGenerator._path_placeholders_from_call(dev_op)

        # Detect field names from sample response
        name_f = next((k for k in ["name", "edgeName", "hostname"] if k in keys), "name")
        ip_f = next((k for k in ["ipAddress", "localIp", "peerIp", "ip"] if k in keys), "ipAddress")
        model_f = next((k for k in ["model", "deviceType"] if k in keys), "")
        serial_f = next((k for k in ["serialNumber", "serial"] if k in keys), "")
        sw_f = next((k for k in ["softwareVersion", "osVersion", "version"] if k in keys), "")
        status_f = next((k for k in ["status", "edgeState", "overallStatus"] if k in keys), "status")
        id_f = next((k for k in ["logicalId", "edgeId", "id"] if k in keys), "id")
        mac_f = next((k for k in ["macAddress", "mac"] if k in keys), "")

        # Enterprise-scoped call needs org iteration
        needs_org_iter = "enterpriseLogicalId" in path_params

        device_push = f"""            push @devices, {{
                SdnControllerId => $self->{{fabric_id}},
                IPAddress       => $gw->{{'{ip_f}'}} // '',
                SdnDeviceMac    => $gw->{{'{mac_f}'}} // '',
                DeviceStatus    => lc($gw->{{'{status_f}'}} // 'unknown') eq 'connected' ? 'connected' : lc($gw->{{'{status_f}'}} // 'unknown'),
                SdnDeviceDN     => "$org_id/$gw->{{'{id_f}'}}",
                Name            => $gw->{{'{name_f}'}} // '',
                NodeRole        => '{vendor} Gateway',
                Vendor          => $gw->{{vendor}} // $self->{{vendor_name}},
                Model           => $gw->{{'{model_f}'}}         // '',
                Serial          => $gw->{{'{serial_f}'}}        // '',
                SWVersion       => $gw->{{'{sw_f}'}}            // '',
                modTS           => NetMRI::Util::Date::formatDate(time()),
            }};"""

        if needs_org_iter:
            return f"""sub obtainDevices {{
    my ($self, $organizations) = @_;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainDevices: started");
    my $devices = $self->getDevices($organizations);
    $self->saveDevices($self->makeDevicesPoolWrapper($devices));
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainDevices: finished");
    return $devices;
}}

sub getDevices {{
    my ($self, $organizations) = @_;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] getDevices: started");

    unless ($organizations && @$organizations) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] getDevices: no organizations provided");
        return [];
    }}

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] getDevices: no API client");
        return [];
    }}

    my @devices;

    foreach my $org (@$organizations) {{
        my $org_id = $org->{{logicalId}} || $org->{{id}};
        next unless $org_id;

        my ($gateways, $err) = $api_helper->{client_method}($org_id);
        if ($err) {{
            $self->{{logger}}->warn("{vendor}[$self->{{fabric_id}}] getDevices: {client_method} failed for org $org_id: $err");
            next;
        }}
        next unless $gateways && @$gateways;

        foreach my $gw (@$gateways) {{
{device_push}
        }}
    }}

    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] getDevices: finished with " . scalar(@devices) . " devices");
    return \\@devices;
}}"""
        else:
            return f"""sub obtainDevices {{
    my ($self, $organizations) = @_;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainDevices: started");
    my $devices = $self->getDevices($organizations);
    $self->saveDevices($self->makeDevicesPoolWrapper($devices));
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainDevices: finished");
    return $devices;
}}

sub getDevices {{
    my ($self, $organizations) = @_;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] getDevices: started");

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] getDevices: no API client");
        return [];
    }}

    my ($gateways, $err) = $api_helper->{client_method}();
    unless (defined $gateways) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] getDevices: {client_method} failed: " . ($err // ''));
        return [];
    }}

    my @devices;
    foreach my $gw (@$gateways) {{
{device_push}
    }}

    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] getDevices: finished with " . scalar(@devices) . " devices");
    return \\@devices;
}}"""

    @staticmethod
    def _render_prod_system_info(vendor: str, matched_ops: List[Dict[str, Any]]) -> str:
        """Generate production obtainSystemInfo."""
        return f"""sub obtainSystemInfo {{
    my ($self, $sdn_devices) = @_;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainSystemInfo: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my $dp        = $self->getPlugin('SaveDeviceProperty');
    my $dp_fields = [qw(DeviceID PropertyName PropertyIndex Source)];
    my @inventory_rows;

    foreach my $dev (@$sdn_devices) {{
        next unless ref($dev) eq 'HASH' && $dev->{{DeviceID}};
        my $device_id = $dev->{{DeviceID}};
        $self->{{dn}} = $dev->{{SdnDeviceDN}};

        my $system_info = {{
            DeviceID        => $device_id,
            Name            => $dev->{{Name}},
            Vendor          => $dev->{{Vendor}},
            Model           => $dev->{{Model}}          // '',
            DeviceMAC       => $dev->{{SdnDeviceMac}}   // '',
            DeviceStatus    => $dev->{{DeviceStatus}},
            SWVersion       => $dev->{{SWVersion}}       // '',
            IPAddress       => $dev->{{IPAddress}},
            LastTimeStamp   => $timestamp,
            SdnControllerId => $dev->{{SdnControllerId}},
        }};
        $self->saveSystemInfo($system_info);
        $self->updateDataCollectionStatus('System', 'OK', $device_id);

        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysName',    '', 'SNMP'], $self->_remove_utf8($dev->{{Name}}))    if $dev->{{Name}};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysModel',   '', 'SNMP'], $dev->{{Model}})    if $dev->{{Model}};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysVendor',  '', 'SNMP'], $dev->{{Vendor}})   if $dev->{{Vendor}};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'sysVersion', '', 'SNMP'], $dev->{{SWVersion}}) if $dev->{{SWVersion}};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'DeviceMAC',  '', 'SNMP'], $dev->{{SdnDeviceMac}}) if $dev->{{SdnDeviceMac}};
        $dp->updateDevicePropertyValueIfChanged($dp_fields, [$device_id, 'SdnControllerId', '', 'NetMRI'], $dev->{{SdnControllerId}}) if $dev->{{SdnControllerId}};

        push @inventory_rows, {{
            DeviceID               => $device_id,
            entPhysicalIndex       => '1',
            entPhysicalClass       => 'chassis',
            entPhysicalDescr       => $dev->{{NodeRole}}   // '',
            entPhysicalName        => $dev->{{Name}},
            entPhysicalFirmwareRev => $dev->{{SWVersion}}  // '{vendor} OS',
            entPhysicalSoftwareRev => $dev->{{SWVersion}}  // '',
            entPhysicalSerialNum   => $dev->{{Serial}}     // 'N/A',
            entPhysicalMfgName     => $dev->{{Vendor}}     // '',
            entPhysicalModelName   => $dev->{{Model}}      // '',
            UnitState              => $dev->{{DeviceStatus}} // '',
            StartTime              => $timestamp,
            EndTime                => $timestamp,
        }};
    }}

    if (@inventory_rows) {{
        $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainSystemInfo: saving " . scalar(@inventory_rows) . " inventory rows");
        $self->saveInventory(\\@inventory_rows);
        $self->updateDataCollectionStatus('Inventory', 'OK');
    }}

    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainSystemInfo: finished");
}}"""

    @staticmethod
    def _render_prod_performance(vendor: str, matched_ops: List[Dict[str, Any]]) -> str:
        """Generate production obtainPerformance from healthStats sampleResponse."""
        health_op = ControllerGenerator._find_op_by_hint(matched_ops, ["health", "cpu", "mem", "performance"])
        if not health_op:
            return ""
        client_method = _method_name(health_op.get("operationId"))
        keys = ControllerGenerator._sample_data_keys(health_op)
        path_params = ControllerGenerator._path_placeholders_from_call(health_op)
        needs_edge = "edgeLogicalId" in path_params

        cpu_field = "cpuPct" if "cpuPct" in keys else "cpuUsage" if "cpuUsage" in keys else ""
        mem_used = "memoryUsageMB" if "memoryUsageMB" in keys else ""
        mem_total = "memoryTotalMB" if "memoryTotalMB" in keys else ""
        mem_free = "memoryFreeMB" if "memoryFreeMB" in keys else ""

        # Build the inner loop body
        if needs_edge:
            fetch_code = f"""
        my (undef, $edge_logical_id) = split m{{/}}, $dev->{{SdnDeviceDN}}, 2;
        unless ($edge_logical_id) {{
            $self->{{logger}}->warn("{vendor}[$self->{{fabric_id}}] obtainPerformance: cannot parse edge ID from DN=$dev->{{SdnDeviceDN}}");
            next;
        }}

        my ($stats, $err) = $api_helper->{client_method}($org_id, $edge_logical_id);"""
            org_setup = """
    my %dn_to_org;
    foreach my $dev (@$sdn_devices) {
        next unless ref($dev) eq 'HASH' && $dev->{SdnDeviceDN};
        my ($org_part) = split m{/}, $dev->{SdnDeviceDN}, 2;
        $dn_to_org{$dev->{SdnDeviceDN}} = $org_part if $org_part;
    }"""
            org_lookup = "        my $org_id = $dn_to_org{$dev->{SdnDeviceDN}} // '';\n"
        else:
            fetch_code = f"\n        my ($stats, $err) = $api_helper->{client_method}();"
            org_setup = ""
            org_lookup = ""

        return f"""sub obtainPerformance {{
    my ($self, $sdn_devices) = @_;
    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainPerformance: started");
    return unless ref($sdn_devices) eq 'ARRAY' && @$sdn_devices;

    my $api_helper = $self->getApiClient();
    unless ($api_helper) {{
        $self->{{logger}}->error("{vendor}[$self->{{fabric_id}}] obtainPerformance: no API client");
        return;
    }}

    my $timestamp = NetMRI::Util::Date::formatDate(time());
    my (@cpu_rows, @mem_rows);
{org_setup}

    foreach my $dev (@$sdn_devices) {{
        next unless ref($dev) eq 'HASH' && $dev->{{DeviceID}};
        my $device_id = $dev->{{DeviceID}};
{org_lookup}{fetch_code}
        if ($err) {{
            $self->{{logger}}->warn("{vendor}[$self->{{fabric_id}}] obtainPerformance: {client_method} failed: $err");
            next;
        }}

        my $items = ref($stats) eq 'ARRAY' ? $stats : [$stats];
        foreach my $s (@$items) {{
            next unless ref($s) eq 'HASH';

            if (defined $s->{{'{cpu_field}'}}) {{
                push @cpu_rows, {{
                    DeviceID  => $device_id,
                    StartTime => $timestamp,
                    EndTime   => $timestamp,
                    CpuIndex  => 1,
                    CpuBusy   => int($s->{{'{cpu_field}'}} // 0),
                }};
            }}

            if (defined $s->{{'{mem_total}'}}) {{
                my $total = $s->{{'{mem_total}'}} || 0;
                my $free  = $s->{{'{mem_free}'}} // 0;
                my $used  = $s->{{'{mem_used}'}} // ($total - $free);
                my $util  = $total ? int(($used / $total) * 100) : 0;
                push @mem_rows, {{
                    DeviceID       => $device_id,
                    StartTime      => $timestamp,
                    EndTime        => $timestamp,
                    UsedMem        => $used * 1024 * 1024,
                    FreeMem        => $free * 1024 * 1024,
                    Utilization5Min => $util,
                }};
            }}
        }}
    }}

    if (@cpu_rows) {{
        $self->saveDeviceCpuStats(\\@cpu_rows);
        $self->updateDataCollectionStatus('CPU', 'OK');
    }}
    if (@mem_rows) {{
        $self->saveDeviceMemStats(\\@mem_rows);
        $self->updateDataCollectionStatus('Memory', 'OK');
    }}

    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainPerformance: finished");
}}"""

    @staticmethod
    def _render_prod_interfaces(vendor: str, matched_ops: List[Dict[str, Any]]) -> str:
        """Generate production obtainInterfaces — delegates to skeleton for now."""
        return ""

    @staticmethod
    def _render_prod_environment(vendor: str, matched_ops: List[Dict[str, Any]]) -> str:
        """Generate production obtainEnvironment — delegates to skeleton for now."""
        return ""

    @staticmethod
    def _render_prod_topology(vendor: str, matched_ops: List[Dict[str, Any]]) -> str:
        """Generate production obtainTopologyAndEndpoints — delegates to skeleton for now."""
        return ""

    @staticmethod
    def _render_utility_methods(vendor: str) -> str:
        """Generate private utility methods for the controller."""
        return f"""
sub _remove_utf8 {{
    my ($self, $str) = @_;
    return '' unless defined $str;
    $str = Encode::encode('ASCII', $str, Encode::FB_DEFAULT);
    $str =~ s/[^[:print:]]//g;
    return $str;
}}

sub _parse_cidr {{
    my $cidr = shift // '';
    if ($cidr =~ m{{^([\\d.]+)/(\\d+)$}}) {{
        return ($1, $2);
    }}
    elsif ($cidr =~ m{{^([\\d.]+)$}}) {{
        return ($1, 32);
    }}
    return (undef, undef);
}}

sub _prefix_to_mask {{
    my $cidr = shift // '';
    my (undef, $len) = _parse_cidr($cidr);
    return undef unless defined $len;
    return maskStringFromPrefix("0.0.0.0/$len");
}}

sub _parse_bandwidth_bps {{
    my $mbps = shift // 0;
    return $mbps * 1_000_000 if $mbps =~ /^\\d+(\\.\\d+)?$/;
    return 0;
}}

sub _map_bgp_state {{
    my $raw = lc(shift // '');
    my %map = (
        established => 'established',
        connect     => 'connect',
        active      => 'active',
        opensent    => 'openSent',
        openconfirm => 'openConfirm',
        idle        => 'idle',
    );
    return $map{{$raw}} // 'idle';
}}
"""

    @staticmethod
    def _render_dataset_initializers(datasets: List[Dict[str, str]]) -> List[str]:
        lines: List[str] = []
        for dataset in datasets:
            var_name = dataset["var"]
            kind = dataset.get("kind") or "scalar_arrayref"
            if kind == "hashref":
                lines.append(f"    my {var_name};")
            else:
                lines.append(f"    my {var_name} = [];")
        return lines

    @staticmethod
    def _render_collection_loop(name: str, signature: str, matched_ops: List[Dict[str, Any]]) -> List[str]:
        if "$sdn_devices" in signature:
            lines = [
                "    foreach my $sdn_device (@$sdn_devices) {",
                "        next unless ref($sdn_device) eq 'HASH';",
                "",
                "        # Use device fields such as SdnDeviceDN, SdnDeviceMac, DeviceID, or IPAddress to build API arguments.",
            ]
            for op in matched_ops:
                helper_name = f"api_{_method_name(op.get('operationId'))}"
                placeholders = ControllerGenerator._path_placeholders_from_call(op)
                placeholders_text = ControllerGenerator._perl_placeholder_list(placeholders)
                if placeholders:
                    lines.append(f"        my %api_args = $self->_generated_api_args_from_device($sdn_device, {placeholders_text});")
                    lines.append("        next unless %api_args;")
                    lines.append(f"        # my ($res, $msg) = $self->{helper_name}(%api_args);")
                else:
                    lines.append(f"        # my ($res, $msg) = $self->{helper_name}();")
                lines.append("")
            if lines[-1] == "":
                lines.pop()
            lines.append("    }")
            return lines

        if name == "obtainOrganizationsAndNetworks":
            lines = [
                "    my $organization_contexts = [];",
                "",
                "    # Example flow:",
                "    # 1. Discover organizations or privileges using a vendor-specific seed call.",
                "    # 2. Populate @$organization_contexts with hashes containing org_id and name.",
                "    # 3. Call the approved organization/site helper methods for each organization.",
                "    # 4. Transform results into @$organization_rows, @$network_rows, and @$sdn_network_rows payloads.",
                "",
                "    foreach my $organization (@$organization_contexts) {",
                "        next unless ref($organization) eq 'HASH';",
            ]
            for op in matched_ops:
                helper_name = f"api_{_method_name(op.get('operationId'))}"
                placeholders = ControllerGenerator._path_placeholders_from_call(op)
                placeholders_text = ControllerGenerator._perl_placeholder_list(placeholders)
                if placeholders:
                    lines.append(f"        my %api_args = $self->_generated_api_args_from_organization($organization, {placeholders_text});")
                    lines.append("        next unless %api_args;")
                    lines.append(f"        # my ($res, $msg) = $self->{helper_name}(%api_args);")
                else:
                    lines.append(f"        # my ($res, $msg) = $self->{helper_name}();")
                lines.append("")
            if lines[-1] == "":
                lines.pop()
            lines.append("    }")
            return lines

        if name == "getDevices":
            lines = [
                "    my $organization_contexts = $self->_generated_organizations();",
                "    my $network_contexts = $self->_generated_networks();",
                "",
                "    # Example flow:",
                "    # 1. Reuse organization/network discovery context if required by the platform.",
                "    # 2. Call organization-scoped helpers for @$organization_contexts and site-scoped helpers for @$network_contexts.",
                "    # 3. Push normalized SaveDevices hashes into @$device_rows.",
            ]
            for op in matched_ops:
                helper_name = f"api_{_method_name(op.get('operationId'))}"
                placeholders = ControllerGenerator._path_placeholders_from_call(op)
                placeholders_text = ControllerGenerator._perl_placeholder_list(placeholders)
                if "site_id" in placeholders:
                    lines.extend(
                        [
                            "",
                            "    foreach my $network (@$network_contexts) {",
                            "        next unless ref($network) eq 'HASH';",
                            f"        my %api_args = $self->_generated_api_args_from_network($network, {placeholders_text});",
                            "        next unless %api_args;",
                            f"        # my ($res, $msg) = $self->{helper_name}(%api_args);",
                            "    }",
                        ]
                    )
                elif "org_id" in placeholders:
                    lines.extend(
                        [
                            "",
                            "    foreach my $organization (@$organization_contexts) {",
                            "        next unless ref($organization) eq 'HASH';",
                            f"        my %api_args = $self->_generated_api_args_from_organization($organization, {placeholders_text});",
                            "        next unless %api_args;",
                            f"        # my ($res, $msg) = $self->{helper_name}(%api_args);",
                            "    }",
                        ]
                    )
                else:
                    lines.extend(["", f"    # my ($res, $msg) = $self->{helper_name}();"])
            return lines

        return []

    @staticmethod
    def _path_placeholders_from_call(call: Dict[str, Any]) -> List[str]:
        path = str(call.get("path") or "")
        return re.findall(r"\{([A-Za-z0-9_]+)\}", path)

    @staticmethod
    def _perl_placeholder_list(placeholders: List[str]) -> str:
        quoted = ", ".join(f"'{placeholder}'" for placeholder in placeholders)
        return f"[{quoted}]"

    @staticmethod
    def _render_context_helpers() -> str:
        return """sub _generated_organizations {
    my $self = shift;
    my $ctx = $self->{generated_collection_context};
    return [] unless ref($ctx) eq 'HASH';
    return $ctx->{organizations} if ref($ctx->{organizations}) eq 'ARRAY';
    return [];
}

sub _generated_networks {
    my $self = shift;
    my $ctx = $self->{generated_collection_context};
    return [] unless ref($ctx) eq 'HASH';
    return $ctx->{networks} if ref($ctx->{networks}) eq 'ARRAY';
    return [];
}

sub _generated_extract_dn_context {
    my ($self, $dn) = @_;
    my @parts = split m{/}, ($dn || '');
    return {
        org_id => $parts[0] || '',
        site_id => $parts[1] || '',
        device_id => $parts[2] || '',
    };
}

sub _generated_api_args_from_organization {
    my ($self, $organization, $placeholders) = @_;
    return () unless ref($organization) eq 'HASH';
    $placeholders = [] unless ref($placeholders) eq 'ARRAY';

    my %candidates = (
        org_id => $organization->{org_id} || $organization->{organization_id} || $organization->{id} || '',
    );

    my %args;
    foreach my $placeholder (@$placeholders) {
        my $value = $candidates{$placeholder};
        return () unless defined $value && length $value;
        $args{$placeholder} = $value;
    }
    return %args;
}

sub _generated_api_args_from_network {
    my ($self, $network, $placeholders) = @_;
    return () unless ref($network) eq 'HASH';
    $placeholders = [] unless ref($placeholders) eq 'ARRAY';

    my %candidates = (
        org_id => $network->{org_id} || $network->{organization_id} || '',
        site_id => $network->{site_id} || $network->{id} || '',
    );

    my %args;
    foreach my $placeholder (@$placeholders) {
        my $value = $candidates{$placeholder};
        return () unless defined $value && length $value;
        $args{$placeholder} = $value;
    }
    return %args;
}

sub _generated_api_args_from_device {
    my ($self, $sdn_device, $placeholders) = @_;
    return () unless ref($sdn_device) eq 'HASH';
    $placeholders = [] unless ref($placeholders) eq 'ARRAY';

    my $dn_ctx = $self->_generated_extract_dn_context($sdn_device->{SdnDeviceDN} || $sdn_device->{dn} || '');
    my %candidates = (
        org_id => $sdn_device->{org_id} || $dn_ctx->{org_id} || '',
        site_id => $sdn_device->{site_id} || $dn_ctx->{site_id} || '',
        device_id => $sdn_device->{device_id} || $sdn_device->{SdnDeviceID} || $dn_ctx->{device_id} || '',
        client_mac => $sdn_device->{client_mac} || $sdn_device->{SdnDeviceMac} || $sdn_device->{mac} || '',
    );

    my %args;
    foreach my $placeholder (@$placeholders) {
        my $value = $candidates{$placeholder};
        return () unless defined $value && length $value;
        $args{$placeholder} = $value;
    }
    return %args;
}
"""

    @staticmethod
    def _render_dataset_save_calls(datasets: List[Dict[str, str]]) -> List[str]:
        lines: List[str] = []
        for dataset in datasets:
            save_method = dataset.get("save")
            if not save_method:
                continue

            var_name = dataset["var"]
            kind = dataset.get("kind") or "scalar_arrayref"
            if kind == "hashref":
                lines.append(f"    $self->{save_method}({var_name}) if ref({var_name}) eq 'HASH';")
            else:
                lines.append(f"    $self->{save_method}({var_name}) if ref({var_name}) eq 'ARRAY' && @{var_name};")
        return lines

    @staticmethod
    def _render_obtain_everything_body(vendor: str, method_names: List[str], has_customer_data: bool = False) -> str:
        lines = [
            "    my $self = shift;",
            "",
            f'    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainEverything: started");',
        ]

        if "obtainOrganizationsAndNetworks" in method_names:
            lines.append("    my $organizations = $self->obtainOrganizationsAndNetworks();")
            lines.append("    return unless $organizations;")
            if not has_customer_data:
                lines.append("    $self->{generated_collection_context} = $organizations if ref($organizations) eq 'HASH';")
        if "getDevices" in method_names:
            if has_customer_data:
                lines.append("    $self->obtainDevices($organizations);")
            else:
                lines.append("    $self->obtainDevices();")

        device_methods = [
            name
            for name in [
                "obtainSystemInfo",
                "obtainPerformance",
                "obtainEnvironment",
                "obtainInterfaces",
                "obtainTopologyAndEndpoints",
            ]
            if name in method_names
        ]

        if device_methods:
            lines.extend(
                [
                    "    my $sdn_devices = $self->loadSdnDevices();",
                    "    return unless $sdn_devices;",
                ]
            )
            for name in device_methods:
                lines.append(f"    $self->{name}($sdn_devices);")

        lines.append(f'    $self->{{logger}}->info("{vendor}[$self->{{fabric_id}}] obtainEverything: finished");')
        return "\n".join(lines)

    @staticmethod
    def _render_noop() -> str:
        return """sub api_noop {
    my $self = shift;
    return $self->getApiClient()->api_noop();
}
"""


class Scaffolder:
    def __init__(self, root_dir: str = ".", client_dir: Optional[str] = None, controller_dir: Optional[str] = None, payload_dir: Optional[str] = None) -> None:
        self.root_dir = root_dir
        self.client_dir = client_dir
        self.controller_dir = controller_dir
        self.payload_dir = payload_dir

    _STRIP_FROM_PLUGIN_CALLS = ("_debug", "apiExamples")

    def write_payload(self, vendor: str, rpc_payload: Dict[str, Any]) -> str:
        if not vendor:
            raise ValueError("vendor is required")

        payload_base = self.payload_dir or f"{self.root_dir}/Payloads"
        payload_path = Path(payload_base) / f"{vendor}-Payload.json"

        payload_path.parent.mkdir(parents=True, exist_ok=True)

        # Strip internal-only fields before writing
        cleaned = copy.deepcopy(rpc_payload)
        for call in cleaned.get("pluginCalls", []):
            for key in self._STRIP_FROM_PLUGIN_CALLS:
                call.pop(key, None)

        payload_path.write_text(json.dumps(cleaned, indent=3, sort_keys=True) + "\n", encoding="utf-8")
        return str(payload_path)

    @staticmethod
    def load_payload(payload_path: str) -> Dict[str, Any]:
        payload = json.loads(Path(payload_path).read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            raise ValueError("Payload JSON must be an object")
        if not isinstance(payload.get("pluginCalls"), list):
            raise ValueError("Payload JSON must contain a 'pluginCalls' array")

        # Normalize payload to the standard template and keep backward compatibility.
        template = _new_payload_template(payload.get("vendor") or "UnknownVendor")
        for key, value in template.items():
            payload.setdefault(key, copy.deepcopy(value))

        normalized_calls: List[Dict[str, Any]] = []
        for idx, call in enumerate(payload.get("pluginCalls") or [], start=1):
            if not isinstance(call, dict):
                continue

            call.setdefault("callId", f"CALL-{idx:03d}")
            call.setdefault("enabled", 1)

            plugins = call.get("plugins")
            if not isinstance(plugins, list) or not plugins:
                # backward compat: old payloads used a singular 'plugin' field
                legacy_plugin = call.get("plugin")
                call["plugins"] = [legacy_plugin] if legacy_plugin else []
            # remove redundant singular key if present
            call.pop("plugin", None)

            call.setdefault("parameters", {"path": [], "query": [], "body": 0})
            call.setdefault("apiExamples", {"request": None, "response": None, "responseStatus": None})
            call.setdefault("customerData", {
                "sampleResponse": None,
                "sampleRequest": None,
                "responseNotes": "",
                "collectedAt": "",
            })
            call.setdefault("review", {"status": "pending", "action": "keep", "notes": ""})

            # Disable reviewed calls that were explicitly dropped, removed, or rejected.
            review = call.get("review") if isinstance(call.get("review"), dict) else {}
            if _review_disables_call(review):
                call["enabled"] = 0

            # Keep matched optional in manually curated payloads; enabled+operation fields suffice.
            if "matched" not in call:
                call["matched"] = 1 if call.get("operationId") and call.get("method") and call.get("path") else 0

            normalized_calls.append(call)

        payload["pluginCalls"] = normalized_calls
        return payload

    def write_perl_modules(self, vendor: str, client_code: str, controller_code: str) -> Dict[str, str]:
        if not vendor:
            raise ValueError("vendor is required")

        client_base = self.client_dir or f"{self.root_dir}/Output/Client"
        controller_base = self.controller_dir or f"{self.root_dir}/Output/SDN"

        client_path = Path(client_base) / f"{vendor}.pm"
        controller_path = Path(controller_base) / f"{vendor}.pm"

        client_path.parent.mkdir(parents=True, exist_ok=True)
        controller_path.parent.mkdir(parents=True, exist_ok=True)

        client_path.write_text(client_code, encoding="utf-8")
        controller_path.write_text(controller_code, encoding="utf-8")

        return {
            "client_path": str(client_path),
            "controller_path": str(controller_path),
        }


        return {
            "client_path": str(client_path),
            "controller_path": str(controller_path),
        }


# ──────────────────────────────────────────────────────────────────────
#  InfrastructureFabric — vendor-agnostic consistent mock data graph
# ──────────────────────────────────────────────────────────────────────

import hashlib
import random as _random
import uuid as _uuid_mod


class InfrastructureFabric:
    """Build a consistent infrastructure graph that can back any SD-WAN vendor's
    mock server.  All cross-references are bidirectional and verifiable:
      - Sites with dedicated subnet allocations
      - Devices with deterministic interfaces on site transit networks
      - Bidirectional BGP peering (ring within each site)
      - Bidirectional LLDP neighbors on the shared WAN segment
      - ARP table entries matching actual device MACs
      - MAC forwarding table matching ARP + LLDP
      - IP routes (connected, BGP-learned, static) referencing real IPs
      - Client/endpoint devices on device LAN subnets with correct edgeId refs
    """

    # Site templates — used round-robin for any vendor
    _SITE_TEMPLATES = [
        {"name": "HQ-NewYork",      "city": "New York",     "wan_prefix": "10.1.1",  "lan_prefix": "192.168",  "asn": 65001},
        {"name": "Branch-Chicago",   "city": "Chicago",      "wan_prefix": "10.1.2",  "lan_prefix": "192.169",  "asn": 65002},
        {"name": "Branch-Dallas",    "city": "Dallas",       "wan_prefix": "10.1.3",  "lan_prefix": "192.170",  "asn": 65003},
        {"name": "DC-SanJose",       "city": "San Jose",     "wan_prefix": "10.1.4",  "lan_prefix": "192.171",  "asn": 65004},
        {"name": "Branch-London",    "city": "London",       "wan_prefix": "10.1.5",  "lan_prefix": "192.172",  "asn": 65005},
        {"name": "Branch-Tokyo",     "city": "Tokyo",        "wan_prefix": "10.1.6",  "lan_prefix": "192.173",  "asn": 65006},
        {"name": "Branch-Sydney",    "city": "Sydney",       "wan_prefix": "10.1.7",  "lan_prefix": "192.174",  "asn": 65007},
        {"name": "DC-Frankfurt",     "city": "Frankfurt",    "wan_prefix": "10.1.8",  "lan_prefix": "192.175",  "asn": 65008},
        {"name": "Branch-Mumbai",    "city": "Mumbai",       "wan_prefix": "10.1.9",  "lan_prefix": "192.176",  "asn": 65009},
        {"name": "Branch-Toronto",   "city": "Toronto",      "wan_prefix": "10.1.10", "lan_prefix": "192.177",  "asn": 65010},
    ]

    # Default model pools per vendor family.  Callers can override.
    _VENDOR_MODELS: Dict[str, List[str]] = {
        "velocloud":  ["Edge 520", "Edge 540", "Edge 620", "Edge 640", "Edge 840", "Edge 3400", "Edge 3800"],
        "meraki":     ["MX68", "MX75", "MX85", "MX105", "MX250", "MX450", "MS120-8", "MS120-24", "MS210-48", "MR46", "MR56"],
        "mist":       ["SRX300", "SRX320", "SRX340", "SRX345", "SRX550M", "EX2300-24P", "EX3400-48T", "AP43", "AP63"],
        "silverpeak": ["EC-XS", "EC-S", "EC-M", "EC-L", "EC-XL", "NX-700", "NX-3700", "NX-7700", "NX-10700"],
        "viptela":    ["vEdge 100", "vEdge 1000", "vEdge 2000", "vEdge 5000", "ISR 1111X", "ISR 4331", "ISR 4451"],
        "aci":        ["N9K-C9332C", "N9K-C9336PQ", "N9K-C93180YC-FX", "N9K-C9364C", "N9K-C9504", "N9K-C9508"],
    }
    _SW_VERSIONS = ["6.0.0.4", "6.0.1.0", "6.1.0.2", "5.4.0.6", "5.4.1.0", "6.2.0.0", "6.3.0.0", "6.4.0.0"]

    def __init__(
        self,
        vendor: str,
        num_devices: int = 50,
        num_sites: int = 5,
        num_clients: int = 200,
        num_orgs: int = 1,
        seed: int = 99,
    ):
        self.vendor = vendor
        self.vendor_lc = vendor.lower()
        self.num_devices = max(num_devices, 2)
        self.num_sites = min(max(num_sites, 1), len(self._SITE_TEMPLATES))
        self.num_clients = num_clients
        self.num_orgs = max(num_orgs, 1)
        self._rng = _random.Random(seed)
        self._built = False

        # Output data stores
        self.organizations: List[Dict[str, Any]] = []
        self.sites: List[Dict[str, Any]] = []
        self.devices: List[Dict[str, Any]] = []
        self.client_devices: List[Dict[str, Any]] = []

    # ── helpers ──

    def _uuid(self) -> str:
        return str(_uuid_mod.UUID(int=self._rng.getrandbits(128)))

    def _mac(self, seed_int: int) -> str:
        h = hashlib.md5(str(seed_int).encode()).hexdigest()
        return ":".join(h[i:i + 2] for i in range(0, 12, 2))

    def _serial(self, prefix: str, idx: int) -> str:
        return f"{prefix}{idx:06d}"

    def _models(self) -> List[str]:
        return self._VENDOR_MODELS.get(self.vendor_lc, self._VENDOR_MODELS["velocloud"])

    # ── public API ──

    def build(self) -> "InfrastructureFabric":
        """Build the full infrastructure graph.  Idempotent."""
        if self._built:
            return self
        self._build_orgs()
        self._build_sites()
        self._build_devices()
        self._build_bgp()
        self._build_lldp()
        self._build_routes()
        self._build_clients()
        self._build_arp_mac()
        self._strip_internal()
        self._built = True
        return self

    def consistency_report(self) -> Dict[str, Any]:
        """Return a dict summarising consistency checks (counts + failures)."""
        self.build()
        report: Dict[str, Any] = {}

        dev_by_id = {d["logicalId"]: d for d in self.devices}

        # BGP bidirectional
        bgp_ok = bgp_fail = 0
        for dev in self.devices:
            for peer in dev.get("bgpPeers", []):
                remote = dev_by_id.get(peer.get("peerLogicalId"))
                if remote and any(p.get("peerLogicalId") == dev["logicalId"] for p in remote.get("bgpPeers", [])):
                    bgp_ok += 1
                else:
                    bgp_fail += 1
        report["bgp"] = {"ok": bgp_ok, "fail": bgp_fail}

        # LLDP bidirectional
        lldp_ok = lldp_fail = 0
        for dev in self.devices:
            for nbr in dev.get("lldpNeighbors", []):
                remote = dev_by_id.get(nbr.get("remoteDeviceId"))
                if remote and any(n.get("remoteDeviceId") == dev["logicalId"] for n in remote.get("lldpNeighbors", [])):
                    lldp_ok += 1
                else:
                    lldp_fail += 1
        report["lldp"] = {"ok": lldp_ok, "fail": lldp_fail}

        # Client references
        cd_ok = sum(1 for cd in self.client_devices if cd.get("edgeLogicalId") in dev_by_id)
        report["clients"] = {"ok": cd_ok, "fail": len(self.client_devices) - cd_ok}

        # Route next-hops
        all_ips = {"0.0.0.0"}
        for d in self.devices:
            for intf in d.get("interfaces", []):
                all_ips.add(intf["ipAddress"])
        for st in self._SITE_TEMPLATES[:self.num_sites]:
            all_ips.add(f"{st['wan_prefix']}.254")
        rt_ok = rt_fail = 0
        for dev in self.devices:
            for rt in dev.get("ipRoutes", []):
                (rt_ok if rt["nextHop"] in all_ips else rt_fail).__class__  # just counting
                if rt["nextHop"] in all_ips:
                    rt_ok += 1
                else:
                    rt_fail += 1
        report["routes"] = {"ok": rt_ok, "fail": rt_fail}

        # ARP MAC accuracy
        mac_map: Dict[str, str] = {}
        for d in self.devices:
            for intf in d.get("interfaces", []):
                mac_map[intf["ipAddress"]] = intf["macAddress"]
        for cd in self.client_devices:
            mac_map[cd["ipAddress"]] = cd["macAddress"]
        for si, st in enumerate(self._SITE_TEMPLATES[:self.num_sites]):
            mac_map[f"{st['wan_prefix']}.254"] = self._mac(70000 + si)
        arp_ok = arp_fail = 0
        for dev in self.devices:
            for entry in dev.get("arpTable", []):
                expected = mac_map.get(entry["ipAddress"])
                if expected and expected == entry["macAddress"]:
                    arp_ok += 1
                else:
                    arp_fail += 1
        report["arp"] = {"ok": arp_ok, "fail": arp_fail}

        # LLDP→ARP→MAC chain
        chain_ok = chain_fail = 0
        for dev in self.devices:
            arp_ips = {a["ipAddress"] for a in dev.get("arpTable", [])}
            mac_set = {m["macAddress"] for m in dev.get("macTable", [])}
            for nbr in dev.get("lldpNeighbors", []):
                if nbr["remoteIpAddress"] in arp_ips and nbr["remoteInterfaceMac"] in mac_set:
                    chain_ok += 1
                else:
                    chain_fail += 1
        report["chain"] = {"ok": chain_ok, "fail": chain_fail}

        return report

    def print_consistency_report(self) -> None:
        r = self.consistency_report()
        print("\n── Infrastructure Fabric Consistency Report ──")
        for label, key in [
            ("BGP peers", "bgp"), ("LLDP neighbors", "lldp"),
            ("Client→Device refs", "clients"), ("Route next-hops", "routes"),
            ("ARP table", "arp"), ("LLDP→ARP→MAC chain", "chain"),
        ]:
            ok = r[key]["ok"]
            fail = r[key]["fail"]
            print(f"  {label}: {ok} OK, {fail} failures")
        print()

    # ── internal builders ──

    def _build_orgs(self) -> None:
        for oi in range(self.num_orgs):
            self.organizations.append({
                "logicalId": f"org-{oi:04d}-{self._uuid()}",
                "id": oi + 1,
                "name": f"Mock-{self.vendor}-Org-{oi + 1}" if self.num_orgs > 1 else f"Mock-{self.vendor}-Enterprise",
                "domain": f"org-{oi + 1}.mock-{self.vendor_lc}.example.com",
                "accountNumber": f"ACCT-{oi + 1:04d}",
                "timezone": "America/New_York",
                "locale": "en-US",
                "created": "2024-01-15T00:00:00.000Z",
                "modified": "2026-04-01T12:00:00.000Z",
            })

    def _build_sites(self) -> None:
        for si in range(self.num_sites):
            tmpl = self._SITE_TEMPLATES[si]
            self.sites.append({
                "siteId": si + 1,
                "name": tmpl["name"],
                "city": tmpl["city"],
                "wan_prefix": tmpl["wan_prefix"],
                "lan_prefix": tmpl["lan_prefix"],
                "asn": tmpl["asn"],
                "orgId": self.organizations[si % len(self.organizations)]["logicalId"] if self.organizations else None,
                "_edge_indices": [],
            })

    def _build_devices(self) -> None:
        models = self._models()
        for idx in range(self.num_devices):
            site = self.sites[idx % self.num_sites]
            site["_edge_indices"].append(idx)
            pos = len(site["_edge_indices"]) - 1
            sdef = self._SITE_TEMPLATES[idx % self.num_sites]

            logical_id = f"dev-{idx:04d}-{self._uuid()}"
            wan_ip = f"{sdef['wan_prefix']}.{pos + 1}"
            lan_ip = f"{sdef['lan_prefix']}.{pos}.1"

            num_lan = self._rng.randint(2, 5)
            interfaces = []
            # GE1 = WAN
            interfaces.append({
                "name": "GE1", "description": "GE1 - WAN",
                "macAddress": self._mac(20000 + idx * 100),
                "ipAddress": wan_ip, "subnetMask": "255.255.255.0",
                "cidr": f"{wan_ip}/24", "mtu": 1500,
                "operationalStatus": "up", "adminStatus": "up", "adminUp": True,
                "bandwidthUp": 10000, "bandwidthDown": 10000, "speed": 10000, "status": "STABLE",
            })
            for li in range(num_lan):
                intf_ip = f"{sdef['lan_prefix']}.{pos}.{li + 1}"
                interfaces.append({
                    "name": f"GE{li + 2}", "description": f"GE{li + 2} - LAN",
                    "macAddress": self._mac(20000 + idx * 100 + li + 1),
                    "ipAddress": intf_ip, "subnetMask": "255.255.255.0",
                    "cidr": f"{intf_ip}/24", "mtu": 1500,
                    "operationalStatus": "up" if self._rng.random() < 0.85 else "down",
                    "adminStatus": "up", "adminUp": True,
                    "bandwidthUp": self._rng.choice([100, 1000, 10000]),
                    "bandwidthDown": self._rng.choice([100, 1000, 10000]),
                    "speed": self._rng.choice([1000, 10000]), "status": "STABLE",
                })

            self.devices.append({
                "logicalId": logical_id, "id": idx + 1,
                "name": f"{self.vendor_lc}-device-{idx + 1:04d}",
                "deviceState": "CONNECTED" if self._rng.random() < 0.9 else "OFFLINE",
                "model": models[idx % len(models)],
                "serialNumber": self._serial(self.vendor_lc[:2].upper(), 20000 + idx),
                "softwareVersion": self._SW_VERSIONS[idx % len(self._SW_VERSIONS)],
                "vendor": self.vendor,
                "ipAddress": wan_ip, "managementIp": wan_ip,
                "siteId": site["siteId"], "siteName": site["name"],
                "activationState": "ACTIVATED",
                "created": "2024-06-01T00:00:00.000Z", "modified": "2026-04-01T12:00:00.000Z",
                "interfaces": interfaces,
                "ipRoutes": [], "bgpPeers": [], "lldpNeighbors": [],
                "arpTable": [], "macTable": [],
                "cpuUsage": round(self._rng.uniform(5, 85), 1),
                "memoryUsage": round(self._rng.uniform(20, 90), 1),
                "uptime": self._rng.randint(86400, 8640000),
                "_siteIdx": idx % self.num_sites,
            })

    def _build_bgp(self) -> None:
        for site in self.sites:
            idxs = site["_edge_indices"]
            if len(idxs) < 2:
                continue
            asn = site["asn"]
            for i in range(len(idxs)):
                j = (i + 1) % len(idxs)
                a, b = self.devices[idxs[i]], self.devices[idxs[j]]
                uptime = self._rng.randint(3600, 8640000)
                a_adv, b_adv = self._rng.randint(5, 200), self._rng.randint(5, 200)
                a["bgpPeers"].append({
                    "peerIp": b["interfaces"][0]["ipAddress"], "peerName": b["name"],
                    "peerLogicalId": b["logicalId"], "asn": asn,
                    "localIp": a["interfaces"][0]["ipAddress"],
                    "localPort": 179, "remotePort": 179, "state": "established",
                    "uptime": uptime, "routesAdvertised": a_adv, "routesReceived": b_adv,
                })
                b["bgpPeers"].append({
                    "peerIp": a["interfaces"][0]["ipAddress"], "peerName": a["name"],
                    "peerLogicalId": a["logicalId"], "asn": asn,
                    "localIp": b["interfaces"][0]["ipAddress"],
                    "localPort": 179, "remotePort": 179, "state": "established",
                    "uptime": uptime, "routesAdvertised": b_adv, "routesReceived": a_adv,
                })

    def _build_lldp(self) -> None:
        for site in self.sites:
            idxs = site["_edge_indices"]
            for i in range(len(idxs)):
                a = self.devices[idxs[i]]
                for j in range(len(idxs)):
                    if i == j:
                        continue
                    b = self.devices[idxs[j]]
                    a["lldpNeighbors"].append({
                        "localInterface": "GE1",
                        "localInterfaceMac": a["interfaces"][0]["macAddress"],
                        "remoteInterface": "GE1",
                        "remoteInterfaceMac": b["interfaces"][0]["macAddress"],
                        "remoteDeviceId": b["logicalId"],
                        "remoteDeviceName": b["name"],
                        "remoteIpAddress": b["interfaces"][0]["ipAddress"],
                        "remoteModel": b["model"],
                        "remoteSerialNumber": b["serialNumber"],
                        "remoteSoftwareVersion": b["softwareVersion"],
                        "capabilities": "Router, Bridge", "ttl": 120,
                    })

    def _build_routes(self) -> None:
        dev_by_id = {d["logicalId"]: d for d in self.devices}
        for dev in self.devices:
            si = dev["_siteIdx"]
            sdef = self._SITE_TEMPLATES[si]
            routes: List[Dict[str, Any]] = []
            # Connected: WAN transit
            routes.append({"destination": f"{sdef['wan_prefix']}.0/24", "nextHop": "0.0.0.0",
                           "metric": 0, "protocol": "connected", "interface": "GE1", "ifName": "GE1"})
            # Connected: LAN
            for intf in dev["interfaces"][1:]:
                subnet = intf["ipAddress"].rsplit(".", 1)[0] + ".0"
                routes.append({"destination": f"{subnet}/24", "nextHop": "0.0.0.0",
                               "metric": 0, "protocol": "connected", "interface": intf["name"], "ifName": intf["name"]})
            # Direct /32 to LLDP neighbors
            for nbr in dev["lldpNeighbors"]:
                routes.append({"destination": f"{nbr['remoteIpAddress']}/32", "nextHop": nbr["remoteIpAddress"],
                               "metric": 0, "protocol": "connected", "interface": "GE1", "ifName": "GE1"})
            # BGP-learned peer LAN subnets
            for peer in dev["bgpPeers"]:
                pe = dev_by_id.get(peer["peerLogicalId"])
                if pe:
                    for pi in pe["interfaces"][1:]:
                        ps = pi["ipAddress"].rsplit(".", 1)[0] + ".0"
                        routes.append({"destination": f"{ps}/24", "nextHop": peer["peerIp"],
                                       "metric": 20, "protocol": "bgp", "interface": "GE1", "ifName": "GE1"})
            # Static default
            routes.append({"destination": "0.0.0.0/0", "nextHop": f"{sdef['wan_prefix']}.254",
                           "metric": 1, "protocol": "static", "interface": "GE1", "ifName": "GE1"})
            # Cross-site statics
            for oi, osdef in enumerate(self._SITE_TEMPLATES[:self.num_sites]):
                if oi != si:
                    routes.append({"destination": f"{osdef['wan_prefix']}.0/24", "nextHop": f"{sdef['wan_prefix']}.254",
                                   "metric": 10, "protocol": "static", "interface": "GE1", "ifName": "GE1"})
            dev["ipRoutes"] = routes

    def _build_clients(self) -> None:
        for i in range(self.num_clients):
            tidx = i % self.num_devices
            tdev = self.devices[tidx]
            si = tdev["_siteIdx"]
            sdef = self._SITE_TEMPLATES[si]
            lan_base = tdev["interfaces"][1]["ipAddress"].rsplit(".", 1)[0]
            host = (i // self.num_devices) + 100
            seed = 50000 + i
            self.client_devices.append({
                "id": i + 1,
                "logicalId": f"cd-{i:04d}-{self._uuid()}",
                "name": f"client-{tdev['siteName']}-{i + 1:04d}",
                "ipAddress": f"{lan_base}.{host}",
                "macAddress": self._mac(seed),
                "vendor": self._rng.choice(["Dell", "HP", "Lenovo", "Apple", "Cisco"]),
                "model": self._rng.choice(["Laptop", "Desktop", "Printer", "IP Phone", "Camera"]),
                "serialNumber": self._serial("CD", seed),
                "operatingSystem": self._rng.choice(["Windows 11", "macOS 14", "Ubuntu 22.04", "ChromeOS"]),
                "softwareVersion": f"{self._rng.randint(10, 15)}.{self._rng.randint(0, 9)}.{self._rng.randint(0, 9)}",
                "status": "active" if self._rng.random() < 0.85 else "inactive",
                "lastActive": int(time.time()) - self._rng.randint(0, 86400),
                "edgeLogicalId": tdev["logicalId"],
                "edgeName": tdev["name"],
                "siteId": tdev["siteId"],
                "siteName": tdev["siteName"],
            })

    def _build_arp_mac(self) -> None:
        clients_by_edge: Dict[str, List[Dict[str, Any]]] = {}
        for cd in self.client_devices:
            clients_by_edge.setdefault(cd["edgeLogicalId"], []).append(cd)
        dev_by_id = {d["logicalId"]: d for d in self.devices}

        for dev in self.devices:
            arp: List[Dict[str, Any]] = []
            mac_tbl: List[Dict[str, Any]] = []
            # WAN side: LLDP neighbors
            for nbr in dev["lldpNeighbors"]:
                peer = dev_by_id.get(nbr["remoteDeviceId"])
                if not peer:
                    continue
                pw = peer["interfaces"][0]
                arp.append({"ipAddress": pw["ipAddress"], "macAddress": pw["macAddress"],
                            "interface": "GE1", "state": "reachable", "type": "dynamic",
                            "age": self._rng.randint(10, 300)})
                mac_tbl.append({"macAddress": pw["macAddress"], "interface": "GE1",
                                "vlan": 1, "type": "dynamic", "state": "learned", "deviceName": peer["name"]})
            # Site gateway
            si = dev["_siteIdx"]
            sdef = self._SITE_TEMPLATES[si]
            gw_ip = f"{sdef['wan_prefix']}.254"
            gw_mac = self._mac(70000 + si)
            arp.append({"ipAddress": gw_ip, "macAddress": gw_mac, "interface": "GE1",
                        "state": "reachable", "type": "dynamic", "age": self._rng.randint(10, 600)})
            mac_tbl.append({"macAddress": gw_mac, "interface": "GE1", "vlan": 1,
                            "type": "dynamic", "state": "learned", "deviceName": f"gateway-{sdef['name']}"})
            # LAN side: client devices
            lan_name = dev["interfaces"][1]["name"] if len(dev["interfaces"]) > 1 else "GE2"
            for cd in clients_by_edge.get(dev["logicalId"], []):
                arp.append({"ipAddress": cd["ipAddress"], "macAddress": cd["macAddress"],
                            "interface": lan_name,
                            "state": "reachable" if cd["status"] == "active" else "stale",
                            "type": "dynamic", "age": self._rng.randint(5, 1200)})
                mac_tbl.append({"macAddress": cd["macAddress"], "interface": lan_name,
                                "vlan": 100, "type": "dynamic", "state": "learned", "deviceName": cd["name"]})
            dev["arpTable"] = arp
            dev["macTable"] = mac_tbl

    def _strip_internal(self) -> None:
        for dev in self.devices:
            dev.pop("_siteIdx", None)
        for site in self.sites:
            site.pop("_edge_indices", None)

    # ── data accessors for PostmanMockGenerator ──

    def get_organizations(self) -> List[Dict[str, Any]]:
        return self.organizations

    def get_devices(self) -> List[Dict[str, Any]]:
        return self.devices

    def get_clients(self) -> List[Dict[str, Any]]:
        return self.client_devices

    def get_sites(self) -> List[Dict[str, Any]]:
        return [{k: v for k, v in s.items() if not k.startswith("_")} for s in self.sites]

    def get_device_detail(self, logical_id: str) -> Optional[Dict[str, Any]]:
        return next((d for d in self.devices if d["logicalId"] == logical_id), None)


class PostmanMockGenerator:
    """Generate a Postman Collection v2.1 JSON file from a filled RPC payload.

    The generated collection can be imported directly into Postman and used
    to create a Mock Server.  Each enabled pluginCall becomes a request item
    with its customerData.sampleResponse (or apiExamples.response) embedded
    as the saved example response — which is exactly what Postman Mock Server
    returns when it receives a matching request.
    """

    SCHEMA = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
    MIN_MOCK_RECORDS = 1000  # Minimum device/item count for list-type responses
    MIN_MOCK_RECORDS_ORG = 10  # Smaller count for org/enterprise/site-level lists

    # Path / operationId patterns that indicate org-level (low-volume) endpoints.
    _ORG_PATH_PATTERNS = re.compile(
        r"/(enterprises|organizations|orgs|tenants|customers|sites|networks)"
        r"(?:/\s*)?$",
        re.IGNORECASE,
    )
    _ORG_OPID_KEYWORDS = {"enterprise", "organization", "org", "tenant", "customer", "site", "network"}
    # Plugin names that are org/network level (not device-level).
    _ORG_PLUGINS = {
        "MerakiOrganizations", "MistOrganizations", "VeloCloudOrganizations",
        "MerakiNetworks", "MistNetworks", "SdnNetworks", "Networks",
        "Organizations",
    }

    @classmethod
    def _target_records_for_call(cls, call: Dict[str, Any], mock_count: Optional[int] = None, mock_org_count: Optional[int] = None) -> int:
        """Return the target record count: ORG-level endpoints get fewer records,
        device-level endpoints use mock_count (default MIN_MOCK_RECORDS = 1000)."""
        plugins = set(call.get("plugins") or [])
        path = (call.get("path") or "").rstrip("/")
        op_id = (call.get("operationId") or "").lower()

        device_target = mock_count if mock_count and mock_count > 0 else cls.MIN_MOCK_RECORDS
        org_target = mock_org_count if mock_org_count and mock_org_count > 0 else cls.MIN_MOCK_RECORDS_ORG

        # If every plugin is org-level, use the smaller count.
        if plugins and plugins <= cls._ORG_PLUGINS:
            return org_target

        # Path ends with an org-level collection (e.g. /enterprises/, /sites/).
        if cls._ORG_PATH_PATTERNS.search(path):
            return org_target

        # operationId is purely "list enterprises" style with no device sub-resource.
        op_tokens = set(re.split(r"[_\-]+", op_id))
        if op_tokens & cls._ORG_OPID_KEYWORDS and not op_tokens & {
            "edge", "edges", "device", "devices", "client", "clientdevice",
            "clientdevices", "ap", "station", "host", "endpoint",
        }:
            # But only if the path doesn't drill into a device-level sub-resource.
            if not re.search(r"/(edges|devices|clients|clientDevices|stations)/", path, re.IGNORECASE):
                return org_target

        return device_target

    @classmethod
    def generate(cls, vendor: str, rpc_payload: Dict[str, Any], mock_count: Optional[int] = None, mock_org_count: Optional[int] = None) -> Dict[str, Any]:
        if not vendor:
            raise ValueError("vendor is required")

        auth_cfg = rpc_payload.get("authentication") if isinstance(rpc_payload.get("authentication"), dict) else {}
        auth_header = "Authorization"
        auth_value = "Token {{api_token}}"
        if auth_cfg:
            prop = auth_cfg.get("tokenPropagation") or {}
            auth_header = prop.get("header") or "Authorization"
            fmt = prop.get("format") or "Bearer {{api_token}}"
            # Replace literal token placeholder with Postman variable
            auth_value = re.sub(r"<[^>]+>", "{{api_token}}", fmt)

        # Build a consistent infrastructure fabric for this vendor
        device_count = mock_count if mock_count and mock_count > 0 else cls.MIN_MOCK_RECORDS
        org_count = mock_org_count if mock_org_count and mock_org_count > 0 else cls.MIN_MOCK_RECORDS_ORG
        num_sites = min(max(org_count, 5), 10)
        num_clients = min(device_count * 4, 5000)
        fabric = InfrastructureFabric(
            vendor=vendor,
            num_devices=device_count,
            num_sites=num_sites,
            num_clients=num_clients,
            num_orgs=org_count,
        ).build()
        fabric.print_consistency_report()

        items: List[Dict[str, Any]] = []
        variables: Dict[str, str] = {
            "base_url": "https://mock-server.example.com",
            "api_token": "your_token_here",
        }

        enabled_calls = [
            c for c in (rpc_payload.get("pluginCalls") or [])
            if isinstance(c, dict) and int(bool(c.get("enabled", 1)))
        ]

        for idx, call in enumerate(enabled_calls, start=1):
            item = cls._build_item(
                index=idx,
                call=call,
                auth_header=auth_header,
                auth_value=auth_value,
                variables=variables,
                mock_count=mock_count,
                mock_org_count=mock_org_count,
                fabric=fabric,
            )
            items.append(item)

        collection: Dict[str, Any] = {
            "info": {
                "name": f"{vendor} API Mock Collection",
                "description": (
                    f"Auto-generated Postman mock collection for {vendor} — "
                    f"{len(items)} endpoint(s) from RPC payload.\n"
                    f"Import into Postman, create a Mock Server, and point "
                    f"NetMRI/NI at the mock URL for integration testing."
                ),
                "schema": cls.SCHEMA,
            },
            "item": items,
            "variable": [
                {"key": k, "value": v, "type": "string"}
                for k, v in sorted(variables.items())
            ],
        }
        return collection

    @classmethod
    def _build_item(
        cls,
        index: int,
        call: Dict[str, Any],
        auth_header: str,
        auth_value: str,
        variables: Dict[str, str],
        mock_count: Optional[int] = None,
        mock_org_count: Optional[int] = None,
        fabric: Optional[InfrastructureFabric] = None,
    ) -> Dict[str, Any]:
        call_id = call.get("callId") or f"CALL-{index:03d}"
        method = (call.get("method") or "GET").upper()
        path = call.get("path") or "/"
        op_id = call.get("operationId") or "unknown"
        plugins = ", ".join(call.get("plugins") or []) or "unmapped"

        # Build response body from customerData or fallback to apiExamples
        response_body, response_source = cls._pick_response_body(call, mock_count=mock_count, mock_org_count=mock_org_count, fabric=fabric)

        # Convert path placeholders {param} to Postman {{param}} variables
        postman_path = path
        path_params = (call.get("parameters") or {}).get("path") or []
        for param in path_params:
            placeholder = "{" + param + "}"
            postman_var = "{{" + param + "}}"
            postman_path = postman_path.replace(placeholder, postman_var)
            variables.setdefault(param, f"sample_{param}_value")

        # Split path into segments for url.path
        raw_url = "{{base_url}}" + postman_path
        path_segments = [seg for seg in postman_path.split("/") if seg]

        item: Dict[str, Any] = {
            "name": f"{index}. {call_id} — {op_id}",
            "request": {
                "method": method,
                "header": [
                    {"key": auth_header, "value": auth_value},
                    {"key": "Content-Type", "value": "application/json"},
                ],
                "url": {
                    "raw": raw_url,
                    "host": ["{{base_url}}"],
                    "path": path_segments,
                },
            },
            "response": [
                {
                    "name": f"{call_id} Success",
                    "originalRequest": {
                        "method": method,
                        "header": [
                            {"key": auth_header, "value": auth_value},
                        ],
                        "url": {
                            "raw": raw_url,
                            "host": ["{{base_url}}"],
                            "path": path_segments,
                        },
                    },
                    "status": "OK",
                    "code": 200,
                    "_postman_previewlanguage": "json",
                    "header": [
                        {"key": "Content-Type", "value": "application/json"},
                    ],
                    "body": response_body,
                },
            ] + cls._build_error_responses(
                call_id=call_id,
                method=method,
                raw_url=raw_url,
                path_segments=path_segments,
                auth_header=auth_header,
                auth_value=auth_value,
                path_params=path_params,
            ),
        }

        # Add request body for POST/PUT/PATCH methods
        if method in ("POST", "PUT", "PATCH"):
            request_body = cls._pick_request_body(call)
            if request_body:
                item["request"]["body"] = {
                    "mode": "raw",
                    "raw": request_body,
                    "options": {"raw": {"language": "json"}},
                }

        return item

    @classmethod
    def _build_error_responses(
        cls,
        call_id: str,
        method: str,
        raw_url: str,
        path_segments: List[str],
        auth_header: str,
        auth_value: str,
        path_params: List[str],
    ) -> List[Dict[str, Any]]:
        """Build standard error example responses (401, 403, 404, 429, 500)."""
        errors = [
            {
                "code": 401,
                "status": "Unauthorized",
                "body": {
                    "error": {"code": "UNAUTHORIZED", "message": "Authentication token is missing, expired, or invalid."},
                },
            },
            {
                "code": 403,
                "status": "Forbidden",
                "body": {
                    "error": {"code": "FORBIDDEN", "message": "Insufficient permissions to access this resource."},
                },
            },
            {
                "code": 429,
                "status": "Too Many Requests",
                "body": {
                    "error": {"code": "RATE_LIMIT_EXCEEDED", "message": "API rate limit exceeded. Retry after the period indicated in Retry-After header."},
                },
            },
            {
                "code": 500,
                "status": "Internal Server Error",
                "body": {
                    "error": {"code": "INTERNAL_ERROR", "message": "An unexpected error occurred on the server."},
                },
            },
        ]

        # Add 404 only if the endpoint has path parameters (i.e. targets a specific resource)
        if path_params:
            errors.insert(2, {
                "code": 404,
                "status": "Not Found",
                "body": {
                    "error": {"code": "NOT_FOUND", "message": "The requested resource was not found."},
                },
            })

        original_request = {
            "method": method,
            "header": [{"key": auth_header, "value": auth_value}],
            "url": {"raw": raw_url, "host": ["{{base_url}}"], "path": path_segments},
        }

        responses: List[Dict[str, Any]] = []
        for err in errors:
            responses.append({
                "name": f"{call_id} {err['status']}",
                "originalRequest": copy.deepcopy(original_request),
                "status": err["status"],
                "code": err["code"],
                "_postman_previewlanguage": "json",
                "header": [
                    {"key": "Content-Type", "value": "application/json"},
                ],
                "body": json.dumps(err["body"], indent=2),
            })

        return responses

    @classmethod
    def _pick_response_body(cls, call: Dict[str, Any], mock_count: Optional[int] = None, mock_org_count: Optional[int] = None, fabric: Optional[InfrastructureFabric] = None) -> Tuple[str, str]:
        """Pick the best response body: customerData > apiExamples > synthetic.

        When an InfrastructureFabric is provided, synthetic responses use
        infrastructure-consistent data with bidirectional relationships.
        List-type responses are amplified to the target record count for the call
        so the mock server returns realistic volumes for integration testing.
        """
        target = cls._target_records_for_call(call, mock_count=mock_count, mock_org_count=mock_org_count)

        # 1) customerData.sampleResponse
        cd = call.get("customerData") if isinstance(call.get("customerData"), dict) else {}
        sample = cd.get("sampleResponse")
        if sample is not None:
            amplified = cls._amplify_response(sample, target)
            return (json.dumps(amplified, indent=2), "customerData")

        # 2) apiExamples.response
        examples = call.get("apiExamples") if isinstance(call.get("apiExamples"), dict) else {}
        example_resp = examples.get("response")
        if example_resp is not None:
            if isinstance(example_resp, str):
                try:
                    parsed = json.loads(example_resp)
                    amplified = cls._amplify_response(parsed, target)
                    return (json.dumps(amplified, indent=2), "apiExamples")
                except (json.JSONDecodeError, TypeError):
                    return (example_resp, "apiExamples")
            amplified = cls._amplify_response(example_resp, target)
            return (json.dumps(amplified, indent=2), "apiExamples")

        # 3) Synthetic placeholder based on plugins
        plugins = call.get("plugins") or []
        synthetic = cls._synthetic_response(call, plugins, mock_count=mock_count, mock_org_count=mock_org_count, fabric=fabric)
        return (json.dumps(synthetic, indent=2), "synthetic")

    @classmethod
    def _pick_request_body(cls, call: Dict[str, Any]) -> Optional[str]:
        """Pick a request body example if available."""
        cd = call.get("customerData") if isinstance(call.get("customerData"), dict) else {}
        sample = cd.get("sampleRequest")
        if sample is not None:
            return json.dumps(sample, indent=2) if not isinstance(sample, str) else sample

        examples = call.get("apiExamples") if isinstance(call.get("apiExamples"), dict) else {}
        example_req = examples.get("request")
        if example_req is not None:
            return json.dumps(example_req, indent=2) if not isinstance(example_req, str) else example_req

        return None

    @classmethod
    def _synthetic_response(cls, call: Dict[str, Any], plugins: List[str], mock_count: Optional[int] = None, mock_org_count: Optional[int] = None, fabric: Optional[InfrastructureFabric] = None) -> Any:
        """Generate a synthetic response with infrastructure-consistent data
        when a fabric is available, or basic placeholder data otherwise."""
        op_id = call.get("operationId") or "unknown"
        path = call.get("path") or "/"

        # Auth/login endpoints → single token object, not a list
        auth_patterns = re.compile(r"(?:^|[_/\-])(?:login|auth|token|session)(?:[_/\-]|$)", re.IGNORECASE)
        if auth_patterns.search(op_id) or auth_patterns.search(path):
            return {
                "token": "FAKE-MOCK-TOKEN-123456",
                "userId": 100,
                "enterpriseId": 1,
                "role": "enterprise",
                "expiresAt": "2027-01-01T00:00:00.000Z",
            }

        # ── If a fabric is available, use infrastructure-consistent data ──
        if fabric is not None:
            data = cls._fabric_response_for_call(call, plugins, fabric)
            if data is not None:
                return data

        # ── Fallback: original synthetic placeholder logic ──
        device_plugins = {"Devices", "Inventory", "SystemInfo", "DeviceProperty"}
        is_device = any(p in device_plugins for p in plugins)

        org_plugins = {"Organizations", "MerakiOrganizations", "MistOrganizations",
                       "VeloCloudOrganizations", "SdnNetworks", "Networks"}
        is_org = any(p in org_plugins for p in plugins)

        records: List[Dict[str, Any]] = []
        target = cls._target_records_for_call(call, mock_count=mock_count, mock_org_count=mock_org_count)

        for i in range(1, target + 1):
            rec: Dict[str, Any] = {
                "id": 1000 + i,
                "name": f"Mock-{op_id}-{i:04d}",
                "logicalId": f"mock-uuid-{i:04d}",
            }

            if is_device or not is_org:
                octet4 = (i % 254) + 1
                octet3 = (i // 254) % 256
                rec.update({
                    "model": f"Model-{1000 + (i % 20)}",
                    "serialNumber": f"SN-{10000 + i}",
                    "ipAddress": f"10.0.{octet3}.{octet4}",
                    "macAddress": f"00:11:22:33:{(i >> 8) & 0xFF:02X}:{i & 0xFF:02X}",
                    "softwareVersion": f"{1 + i % 5}.{i % 10}.{i % 3}",
                    "status": "CONNECTED" if i % 7 != 0 else "DISCONNECTED",
                    "hostname": f"device-{i:04d}.mock.local",
                    "siteId": 100 + (i % 10),
                    "siteName": f"Site-{100 + (i % 10)}",
                    "lastContact": f"2026-03-{15 + (i % 16):02d}T{8 + (i % 14):02d}:{i % 60:02d}:00Z",
                })
            else:
                rec.update({
                    "accountNumber": f"ACCT-{2000 + i}",
                    "domain": f"org-{i:04d}.mock.example.com",
                    "networkCount": 5 + (i % 50),
                    "edgeCount": 10 + (i % 200),
                })

            records.append(rec)

        return records

    @classmethod
    def _fabric_response_for_call(cls, call: Dict[str, Any], plugins: List[str], fabric: InfrastructureFabric) -> Optional[Any]:
        """Map a pluginCall to the appropriate fabric data based on path/operationId/plugins.

        Returns None if no fabric mapping applies (falls back to legacy synthetic).
        """
        path_lc = (call.get("path") or "").lower()
        op_lc = (call.get("operationId") or "").lower()
        plugin_set = set(plugins)

        # ── Category detection by path, operationId, and plugins ──

        # Organizations / Enterprises
        org_plugins = {"Organizations", "MerakiOrganizations", "MistOrganizations",
                       "VeloCloudOrganizations"}
        if plugin_set & org_plugins or re.search(r"/(enterprises|organizations|orgs)/?$", path_lc):
            return fabric.get_organizations()

        # Networks / Sites
        net_plugins = {"SdnNetworks", "Networks", "MerakiNetworks", "MistNetworks"}
        if plugin_set & net_plugins or re.search(r"/(sites|networks)/?$", path_lc):
            return fabric.get_sites()

        # Client / Endpoint devices
        client_plugins = {"SdnEndpoint", "bsnMobileStationTable"}
        if plugin_set & client_plugins or re.search(r"/(clientdevices|clients|endpoints|stations)/?$", path_lc):
            return fabric.get_clients()

        # Device inventory / edges — broad device-level
        device_plugins = {"Devices", "Inventory", "SdnFabricInterface",
                          "SwitchPortObject", "ifConfig", "bsnAPTable"}
        if plugin_set & device_plugins or re.search(r"/(edges|devices|inventory)/?$", path_lc):
            return fabric.get_devices()

        # Forwarding / flow stats / routes — return devices with embedded tables
        forwarding_plugins = {"Forwarding", "IPAddress", "VrfARP", "atObject", "ipRouteTable"}
        if plugin_set & forwarding_plugins or "flow" in op_lc or "route" in path_lc:
            return fabric.get_devices()

        # Performance / health / system info
        perf_plugins = {"Performance", "SystemInfo", "DeviceCpuStats", "DeviceMemStats",
                        "Environmental", "DeviceProperty"}
        if plugin_set & perf_plugins or re.search(r"/(health|stats|performance|system)", path_lc):
            return fabric.get_devices()

        # BGP sessions
        bgp_plugins = {"bgpPeerTable", "LLDP"}
        if plugin_set & bgp_plugins or "bgp" in path_lc or "bgp" in op_lc:
            # Return flattened BGP peer list from all devices
            all_bgp: List[Dict[str, Any]] = []
            for dev in fabric.get_devices():
                for peer in dev.get("bgpPeers", []):
                    entry = dict(peer)
                    entry["edgeLogicalId"] = dev["logicalId"]
                    entry["edgeName"] = dev["name"]
                    all_bgp.append(entry)
            return all_bgp

        # Interface / port details
        intf_plugins = {"ifPerf", "RoutingPerfObject"}
        if plugin_set & intf_plugins or re.search(r"/(interfaces|ports|links)", path_lc):
            return fabric.get_devices()

        # Firewall
        if "Firewall" in plugin_set or "firewall" in path_lc:
            return fabric.get_devices()

        # Tunnel status
        if "tunnel" in path_lc or "tunnel" in op_lc:
            return fabric.get_devices()

        # QoS
        if "qos" in path_lc or "qos" in op_lc:
            return fabric.get_devices()

        # Generic device-level fallback for any unmatched path with device sub-resources
        if re.search(r"/(edges|devices)/\{", path_lc):
            return fabric.get_devices()[:1]  # single device detail

        return None

    @classmethod
    def _amplify_response(cls, response: Any, target: Optional[int] = None) -> Any:
        """Amplify list-type responses to at least *target* items.

        Handles:
        - Top-level arrays: [item, ...]
        - Wrapped arrays: {"data": [item, ...], ...}  (VeloCloud pattern)
        - Non-list responses (login tokens, single objects): returned unchanged.
        """
        if target is None:
            target = cls.MIN_MOCK_RECORDS

        # Top-level array
        if isinstance(response, list):
            if len(response) >= target:
                return response
            if len(response) == 0:
                return response
            return cls._replicate_records(response, target)

        # Wrapped array — look for common data wrapper keys
        if isinstance(response, dict):
            for data_key in ("data", "items", "results", "records", "devices", "edges", "networks"):
                inner = response.get(data_key)
                if isinstance(inner, list) and len(inner) > 0:
                    if len(inner) < target:
                        amplified = dict(response)
                        amplified[data_key] = cls._replicate_records(inner, target)
                        # Update any total/count fields
                        for count_key in ("totalCount", "total", "count"):
                            if count_key in amplified:
                                amplified[count_key] = len(amplified[data_key])
                        return amplified
                    return response

        # Single object (login token, etc.) — return as-is
        return response

    @classmethod
    def _replicate_records(cls, seed_records: List[Dict[str, Any]], target: int) -> List[Any]:
        """Replicate seed records up to *target* count, varying key fields."""
        result: List[Any] = []
        seed_count = len(seed_records)
        for i in range(target):
            template = seed_records[i % seed_count]
            if isinstance(template, dict):
                result.append(cls._vary_record(template, i + 1))
            else:
                result.append(template)
        return result

    @classmethod
    def _vary_record(cls, record: Dict[str, Any], index: int) -> Dict[str, Any]:
        """Create a clone of *record* with deterministically varied field values."""
        varied = dict(record)
        for key, val in record.items():
            lk = key.lower()
            if isinstance(val, (int, float)) and ("id" in lk or lk == "id"):
                varied[key] = 1000 + index
            elif isinstance(val, str):
                if "ip" in lk or lk.endswith("address") and "." in val:
                    # Vary IP-like strings — guaranteed unique per index
                    o4 = (index % 254) + 1
                    o3 = (index // 254) % 256
                    varied[key] = f"10.0.{o3}.{o4}"
                elif "mac" in lk and ":" in val:
                    varied[key] = f"00:11:22:33:{(index >> 8) & 0xFF:02X}:{index & 0xFF:02X}"
                elif "serial" in lk:
                    varied[key] = f"SN-{10000 + index}"
                elif "uuid" in lk or "logicalid" in lk or "uid" in lk:
                    varied[key] = f"uuid-{index:04d}"
                elif "name" in lk or "hostname" in lk:
                    varied[key] = f"{val.split()[0] if ' ' in val else val}-{index:04d}"
                elif "status" in lk:
                    varied[key] = "CONNECTED" if index % 7 != 0 else "DISCONNECTED"
        return varied

    @classmethod
    def write(cls, vendor: str, collection: Dict[str, Any], output_dir: str = ".") -> str:
        """Write the Postman collection to a JSON file."""
        out_path = Path(output_dir) / f"{vendor}-Mock-Collection.postman_collection.json"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(collection, indent=2) + "\n", encoding="utf-8")
        return str(out_path)


class Generator:
    def __init__(
        self,
        root_dir: str = ".",
        plugin_dir: Optional[str] = None,
        output_dir: Optional[str] = None,
        client_dir: Optional[str] = None,
        controller_dir: Optional[str] = None,
        payload_dir: Optional[str] = None,
        threshold: float = 0.25,
    ) -> None:
        self.root_dir = _expand_home(root_dir) or "."
        self.plugin_dir = _expand_home(plugin_dir) or _default_plugin_dir()

        effective_output_dir = _expand_home(output_dir) or _default_output_dir(self.root_dir)
        self.client_dir = _expand_home(client_dir) or os.path.join(effective_output_dir, "Client")
        self.controller_dir = _expand_home(controller_dir) or os.path.join(effective_output_dir, "SDN")
        self.payload_dir = _expand_home(payload_dir) or _default_payload_dir(self.root_dir)
        self.threshold = threshold

    def generate_payload(self, source: str, vendor: str, plugins: Optional[List[str]] = None) -> Dict[str, Any]:
        if not vendor:
            raise ValueError("vendor is required")
        if not source:
            raise ValueError("source is required")

        fetcher = Fetcher()
        parser = SpecParser()
        catalog = PluginCatalog(plugin_dir=self.plugin_dir)

        raw = fetcher.fetch(source)
        spec = parser.parse(raw)

        effective_plugins = plugins if plugins else catalog.list_plugins()
        effective_plugins = self._filter_plugins_for_vendor(vendor, effective_plugins)
        intent_catalog = PluginFieldIntentCatalog(root_dir=self.root_dir)
        required_fields_catalog = PluginRequiredFieldsCatalog(plugin_dir=self.plugin_dir)

        template_payload = self._load_vendor_payload_template(vendor)
        if template_payload is not None:
            payload = self._build_payload_from_template(
                vendor=vendor,
                template_payload=template_payload,
                spec=spec,
                effective_plugins=effective_plugins,
                intent_catalog=intent_catalog,
                required_fields_catalog=required_fields_catalog,
            )
            return self._annotate_payload_source(payload, source, used_template=True)

        matcher = EndpointMatcher(spec=spec, threshold=self.threshold, vendor=vendor)
        payload_builder = RpcPayloadBuilder(matcher=matcher)
        payload = payload_builder.build(
            vendor=vendor,
            plugins=effective_plugins,
            tokenizer=catalog.tokenize_plugin_name,
            match_limit=5,
            intent_catalog=intent_catalog,
            plugin_required_fields_catalog=required_fields_catalog,
        )

        return self._annotate_payload_source(payload, source, used_template=False)

    @staticmethod
    def _annotate_payload_source(payload: Dict[str, Any], source: str, used_template: bool) -> Dict[str, Any]:
        src = source or "unknown"
        payload["generation"] = {
            "source": src,
            "mode": "template_enriched_from_openapi" if used_template else "openapi_matched",
        }

        manual = payload.get("manualReview") if isinstance(payload.get("manualReview"), dict) else {}
        manual["notes"] = f"Generated from OpenAPI source: {src}"
        payload["manualReview"] = manual
        return payload

    @staticmethod
    def _filter_plugins_for_vendor(vendor: str, plugins: List[str]) -> List[str]:
        vendor_lc = (vendor or "").strip().lower()

        # Map of vendor keywords to the plugin prefixes they "own".
        # When generating for a given vendor, exclude plugins belonging to OTHER vendors.
        VENDOR_PLUGIN_PREFIXES: Dict[str, List[str]] = {
            "aci":       ["aci"],
            "meraki":    ["meraki"],
            "mist":      ["mist"],
            "velocloud": ["velocloud"],
            "silverpeak":["silverpeak"],
            "viptela":   ["viptela"],
        }

        # Collect prefixes owned by other vendors (not the current one)
        exclude_prefixes: List[str] = []
        for vkey, prefixes in VENDOR_PLUGIN_PREFIXES.items():
            if vkey in vendor_lc:
                continue  # this vendor's own prefixes — keep them
            exclude_prefixes.extend(prefixes)

        if not exclude_prefixes:
            return plugins

        def is_excluded(plugin: str) -> bool:
            name_lc = plugin.lower().replace("save", "", 1)  # strip leading "Save" prefix
            return any(name_lc.startswith(prefix) for prefix in exclude_prefixes)

        return [p for p in plugins if not is_excluded(p)]

    def _load_vendor_payload_template(self, vendor: str) -> Optional[Dict[str, Any]]:
        candidates = [
            Path(self.payload_dir) / f"{vendor}-Payload-from-code.json",
            Path(self.root_dir) / "Payloads" / f"{vendor}-Payload-from-code.json",
            Path(self.root_dir) / "tools" / "openapi_codegen" / "templates" / f"{vendor}-Payload-from-code.json",
            Path(self.payload_dir) / f"{vendor}-Payload-template.json",
            Path(self.root_dir) / "Payloads" / f"{vendor}-Payload-template.json",
        ]

        for path in candidates:
            if path.is_file():
                return Scaffolder.load_payload(str(path))
        return None

    def _build_payload_from_template(
        self,
        vendor: str,
        template_payload: Dict[str, Any],
        spec: Dict[str, Any],
        effective_plugins: List[str],
        intent_catalog: Optional["PluginFieldIntentCatalog"] = None,
        required_fields_catalog: Optional["PluginRequiredFieldsCatalog"] = None,
    ) -> Dict[str, Any]:
        matcher = EndpointMatcher(spec=spec, threshold=self.threshold, vendor=vendor)
        op_index: Dict[Tuple[str, str], Operation] = {
            (op.method.lower(), op.path): op for op in matcher.operations
        }

        payload = dict(template_payload)
        payload["vendor"] = vendor
        payload["generatedAt"] = time.asctime(time.gmtime()) + " UTC"
        template = _new_payload_template(vendor)
        for key, value in template.items():
            payload.setdefault(key, copy.deepcopy(value))

        normalized_calls: List[Dict[str, Any]] = []
        skip_reason_map: Dict[str, str] = {}
        for idx, call in enumerate(payload.get("pluginCalls") or [], start=1):
            if not isinstance(call, dict):
                continue

            method = (call.get("method") or "").lower()
            path = call.get("path")
            op = op_index.get((method, path)) if method and path else None

            call.setdefault("callId", f"CALL-{idx:03d}")
            call.setdefault("enabled", 1)
            call.setdefault("review", {"status": "pending", "action": "keep", "notes": ""})
            call.setdefault("customerData", {
                "sampleResponse": None,
                "sampleRequest": None,
                "responseNotes": "",
                "collectedAt": "",
            })

            plugins = call.get("plugins")
            if not isinstance(plugins, list) or not plugins:
                # backward compat: old payloads used a singular 'plugin' field
                legacy_plugin = call.get("plugin")
                call["plugins"] = [legacy_plugin] if legacy_plugin else []
            # remove redundant singular key if present
            call.pop("plugin", None)

            template_plugins = [
                p for p in (call.get("plugins") or [])
                if p in effective_plugins
            ]

            if op is not None:
                call.setdefault("operationId", op.operation_id)
                call.setdefault("parameters", op.parameters)
                call.setdefault(
                    "apiExamples",
                    {
                        "request": op.examples.get("request"),
                        "response": op.examples.get("response"),
                        "responseStatus": op.examples.get("responseStatus"),
                    },
                )
                call.setdefault("matched", 1)
            else:
                call.setdefault("parameters", {"path": [], "query": [], "body": 0})
                call.setdefault("apiExamples", {"request": None, "response": None, "responseStatus": None})
                call.setdefault("matched", 0)

            if op is not None and template_plugins:
                filtered_plugins: List[str] = []
                op_candidate = {"responseSchemaKeys": op.response_schema_keys}
                for plugin in template_plugins:
                    intent = intent_catalog.get(plugin) if intent_catalog else None
                    required_fields = RpcPayloadBuilder._required_fields_for_plugin(plugin, intent, required_fields_catalog)
                    if required_fields and not RpcPayloadBuilder._candidate_satisfies_required_fields(op_candidate, required_fields):
                        skip_reason_map[plugin] = "missing_required_outputs"
                        continue
                    filtered_plugins.append(plugin)
                call["plugins"] = filtered_plugins
            else:
                call["plugins"] = template_plugins

            # Nest scoring fields under _debug
            matched_val = call.pop("matched", 1 if op is not None else 0)
            score_val = call.pop("score", 1.0 if matched_val else 0.0)
            coverage_count = call.pop("coverageCount", len(call.get("plugins") or []))
            coverage_score = call.pop("coverageScore", 0.0)
            call["_debug"] = {
                "score": score_val,
                "coverageCount": coverage_count,
                "coverageScore": coverage_score,
                "matched": matched_val,
            }

            # Build _developerGuide
            call_method = (call.get("method") or "GET").upper()
            call_path = call.get("path") or "/"
            response_keys = op.response_schema_keys if op is not None else []
            call["_developerGuide"] = RpcPayloadBuilder._build_developer_guide(
                call_id=call.get("callId", f"CALL-{idx:03d}"),
                method=call_method,
                path=call_path,
                parameters=call.get("parameters") or {},
                response_schema_keys=response_keys,
                plugins_for_op=call.get("plugins") or [],
                calls_so_far=normalized_calls,
                vendor=vendor,
            )

            review = call.get("review") if isinstance(call.get("review"), dict) else {}
            if _review_disables_call(review):
                call["enabled"] = 0

            normalized_calls.append(call)

        total_plugins = max(1, len(effective_plugins))
        for call in normalized_calls:
            debug = call.get("_debug") if isinstance(call.get("_debug"), dict) else {}
            debug["coverageCount"] = len(call.get("plugins") or [])
            debug["coverageScore"] = debug["coverageCount"] / total_plugins
            call["_debug"] = debug

        payload["pluginCalls"] = normalized_calls

        covered_plugins = {
            p
            for call in normalized_calls
            if int(bool(call.get("enabled", 1))) and int(bool((call.get("_debug") or {}).get("matched", call.get("matched", 1))))
            for p in (call.get("plugins") or [])
        }
        skipped_plugins = sorted(set(p for p in effective_plugins if p not in covered_plugins))
        payload["skippedPlugins"] = skipped_plugins
        payload["reviewQueue"] = {
            "lowConfidenceMappings": [
                {
                    "operationId": call.get("operationId"),
                    "method": call.get("method"),
                    "path": call.get("path"),
                    "score": (call.get("_debug") or {}).get("score"),
                    "coverageCount": (call.get("_debug") or {}).get("coverageCount"),
                    "plugins": call.get("plugins", []),
                }
                for call in normalized_calls
                if float((call.get("_debug") or {}).get("score") or 0.0) < 0.9
            ],
            "skippedPlugins": [
                {"plugin": p, "reason": (skip_reason_map.get(p) or "no_template_mapping")}
                for p in skipped_plugins
            ],
        }
        payload["stats"] = {
            "totalPlugins": len(effective_plugins),
            "matchedPlugins": len(covered_plugins),
            "skippedPlugins": len(skipped_plugins),
            "selectedOperations": sum(
                1
                for call in normalized_calls
                if int(bool(call.get("enabled", 1))) and int(bool((call.get("_debug") or {}).get("matched", call.get("matched", 1))))
            ),
        }

        return payload

    def generate_vendor_code(self, source: str, vendor: str, plugins: Optional[List[str]] = None) -> Dict[str, Any]:
        payload = self.generate_payload(source=source, vendor=vendor, plugins=plugins)

        scaffolder = Scaffolder(
            root_dir=self.root_dir,
            client_dir=self.client_dir,
            controller_dir=self.controller_dir,
            payload_dir=self.payload_dir,
        )

        # Enforce two-phase generation: persist payload JSON, then consume it for Perl generation.
        payload_path = scaffolder.write_payload(vendor=vendor, rpc_payload=payload)
        payload_from_file = scaffolder.load_payload(payload_path)

        client_code = ClientGenerator.generate(vendor=vendor, rpc_payload=payload_from_file, root_dir=self.root_dir)
        controller_code = ControllerGenerator.generate(vendor=vendor, rpc_payload=payload_from_file, root_dir=self.root_dir)

        written = scaffolder.write_perl_modules(
            vendor=vendor,
            client_code=client_code,
            controller_code=controller_code,
        )

        return {
            "payload": payload_from_file,
            "files": {
                **written,
                "payload_path": payload_path,
            },
        }


def _method_name(operation_id: Optional[str]) -> str:
    name = re.sub(r"[^a-z0-9]+", "_", (operation_id or "call_endpoint").lower())
    name = re.sub(r"^_+|_+$", "", name)
    if re.match(r"^\d", name):
        name = f"op_{name}"
    return name or "call_endpoint"


def _review_disables_call(review: Any) -> bool:
    if not isinstance(review, dict):
        return False

    action = str(review.get("action") or "keep").strip().lower()
    status = str(review.get("status") or "").strip().lower()
    return action in {"drop", "remove", "reject", "rejected"} or status in {"reject", "rejected"}


def _vendor_display_name(vendor: str) -> str:
    display_names = {
        "mist": "Juniper Mist",
        "meraki": "Cisco Meraki",
        "viptela": "Cisco Viptela",
        "aci": "Cisco ACI",
        "silverpeak": "Silver Peak",
    }
    return display_names.get((vendor or "").strip().lower(), vendor)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Two-step codegen: Step 1 generates payload JSON from OpenAPI (user fills customerData), Step 2 generates Perl modules from filled payload."
    )
    parser.add_argument("--source", default="", help="OpenAPI URL or file path (YAML or JSON)")
    parser.add_argument("--vendor", required=True, help="Vendor name")
    parser.add_argument("--plugins", dest="plugins_csv", default="", help="Comma-separated plugin names")
    parser.add_argument("--root", default=".", help="Root output path")
    parser.add_argument("--plugin-dir", default="", help="Plugin directory")
    parser.add_argument("--output-dir", default="", help="Base output directory for generated Perl modules")
    parser.add_argument("--client-dir", default="", help="Client output directory")
    parser.add_argument("--controller-dir", default="", help="Controller output directory")
    parser.add_argument("--payload-dir", default="", help="Payload output directory (default: <root>/Payloads)")
    parser.add_argument("--payload-input", default="", help="Existing payload JSON path to generate Perl modules from")
    parser.add_argument("--threshold", type=float, default=0.25, help="Match threshold")
    parser.add_argument("--step1", action="store_true", help="Step 1: Parse OpenAPI spec and generate payload with empty customerData for user to fill")
    parser.add_argument("--step1.5", dest="step1_5", action="store_true", help="Step 1.5: Generate Postman Mock Collection from filled payload (requires --payload-input)")
    parser.add_argument("--mock-count", dest="mock_count", type=int, default=0, help="Device/edge entry count for mock responses (default: 1000)")
    parser.add_argument("--mock-org-count", dest="mock_org_count", type=int, default=0, help="Enterprise/org entry count for mock responses (default: 10)")
    parser.add_argument("--step2", action="store_true", help="Step 2: Generate Perl modules from filled payload (requires --payload-input)")
    return parser.parse_args()


def _customer_data_summary(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Return summary of customerData fill status across all pluginCalls."""
    calls = payload.get("pluginCalls") or []
    total = 0
    filled = 0
    empty_calls: List[str] = []
    for call in calls:
        if not isinstance(call, dict):
            continue
        if not int(bool(call.get("enabled", 1))):
            continue
        total += 1
        cd = call.get("customerData") if isinstance(call.get("customerData"), dict) else {}
        if cd.get("sampleResponse") is not None:
            filled += 1
        else:
            empty_calls.append(f"  {call.get('callId', '?')}: {(call.get('method') or 'GET').upper()} {call.get('path', '/')}")
    return {"total": total, "filled": filled, "empty_calls": empty_calls}


def _print_deployment_notes(vendor: str, payload: Dict[str, Any], files: Dict[str, str]) -> None:
    """Print vendor-specific deployment notes after Step 2 code generation.

    Lists generated files, new vendor-specific files (plugins, SQL tables),
    and standard files that need modifications — with their target paths on
    the NetMRI/NI appliance.
    """
    # Identify vendor-specific plugins from the payload
    all_plugins: List[str] = []
    for call in (payload.get("pluginCalls") or []):
        if not isinstance(call, dict) or not int(bool(call.get("enabled", 1))):
            continue
        for p in (call.get("plugins") or []):
            if p not in all_plugins:
                all_plugins.append(p)

    # Detect vendor-specific plugins (named after the vendor)
    vendor_lc = vendor.lower()
    vendor_plugins = [p for p in all_plugins if vendor_lc in p.lower()]
    # Vendor-specific SQL tables — one per vendor plugin
    vendor_sql_tables = [
        p.replace("Save", "").replace("Organizations", "Organization")
        for p in vendor_plugins
    ]

    print()
    print("=" * 70)
    print(f"DEPLOYMENT NOTES — {vendor}")
    print("=" * 70)

    print(f"""
After generating the source files, the following changes must be applied
on the NetMRI/NI appliance to complete the {vendor} integration.

─── A. GENERATED FILES (copy to appliance) ───

  {vendor}-Controller.pm
    Source: {files.get('controller_path', f'Output/SDN/{vendor}.pm')}
    Target: /usr/local/lib/site_perl/NetMRI/SDN/{vendor}.pm

  {vendor}-Client.pm
    Source: {files.get('client_path', f'Output/Client/{vendor}.pm')}
    Target: /usr/local/lib/site_perl/NetMRI/HTTP/Client/{vendor}.pm
""")

    if vendor_plugins:
        print("─── B. NEW VENDOR-SPECIFIC FILES (create on appliance) ───\n")
        for plugin_name in vendor_plugins:
            print(f"  Save{plugin_name}.pm")
            print(f"    Source: Controller/SDN/Plugins/Save{plugin_name}.pm")
            print(f"    Target: /usr/local/lib/site_perl/NetMRI/SDN/Plugins/Save{plugin_name}.pm")
            print()
        for table_name in vendor_sql_tables:
            print(f"  {table_name}.sql")
            print(f"    Source: Files/{vendor}/{table_name}.sql")
            print(f"    Target: /infoblox/netmri/db/db-netmri/create/{table_name}.sql")
            print(f"    Action: Run SQL to create the {table_name} table")
            print()
    else:
        print("─── B. NEW VENDOR-SPECIFIC FILES ───\n")
        print("  (No vendor-specific plugins detected — check payload pluginCalls)\n")

    print(f"""─── C. STANDARD FILES (modify for {vendor} support) ───

  ApiHelperFactory.pm
    Path:   /usr/local/lib/site_perl/NetMRI/SDN/ApiHelperFactory.pm
    Action: Register {vendor} in the factory dispatch map

  Base.pm
    Path:   /usr/local/lib/site_perl/NetMRI/SDN/Base.pm
    Action: Add {vendor} to autoload_save_methods if new plugins are used

  getDeviceList.sql
    Path:   /infoblox/netmri/app/transaction/netmri/processors/discovery/getDeviceList.sql
    Action: Add UNION clause for {vendor} device table

  getDeviceList.debug.sql
    Path:   /infoblox/netmri/app/transaction/netmri/processors/discovery/getDeviceList.debug.sql
    Action: Mirror the getDeviceList.sql change for debug queries

  checkSdnConnection.pl
    Path:   /infoblox/netmri/app/transaction/netmri/collectors/sdnEngine/checkSdnConnection.pl
    Action: Add {vendor} case to connection-check dispatch

  PropertyGroup.sql
    Path:   /infoblox/netmri/db/db-netmri/DeviceSupport/PropertyGroup.sql
    Action: Add property groups for {vendor} device properties

  PropertyGroupDef.sql
    Path:   /infoblox/netmri/db/db-netmri/DeviceSupport/PropertyGroupDef.sql
    Action: Add property group definitions for {vendor}

─── D. POST-DEPLOYMENT ───

  1. Run any new .sql files to create vendor tables
  2. Restart SDN Engine and Discovery Server
  3. Configure SDN controller in NetMRI UI (or via SQL insert)
  4. Trigger a collection poll to validate
""")


def main() -> int:
    args = _parse_args()
    plugins = [p.strip() for p in args.plugins_csv.split(",") if p.strip()]

    generator = Generator(
        root_dir=args.root,
        plugin_dir=args.plugin_dir or None,
        output_dir=args.output_dir or None,
        client_dir=args.client_dir or None,
        controller_dir=args.controller_dir or None,
        payload_dir=args.payload_dir or None,
        threshold=args.threshold,
    )

    # Determine operating mode
    if args.step1_5:
        # --- Step 1.5: Generate Postman Mock Collection from filled payload ---
        if not args.payload_input:
            raise ValueError("Step 1.5 requires --payload-input pointing to the filled payload JSON")

        payload_from_file = Scaffolder.load_payload(args.payload_input)

        cd_summary = _customer_data_summary(payload_from_file)
        user_mock_count = args.mock_count if args.mock_count and args.mock_count > 0 else None
        user_mock_org_count = args.mock_org_count if args.mock_org_count and args.mock_org_count > 0 else None
        effective_mock_count = user_mock_count or PostmanMockGenerator.MIN_MOCK_RECORDS
        effective_org_count = user_mock_org_count or PostmanMockGenerator.MIN_MOCK_RECORDS_ORG
        print(f"\n=== Step 1.5: Generating Postman Mock Collection ===")
        print(f"Payload: {args.payload_input}")
        print(f"Customer data: {cd_summary['filled']}/{cd_summary['total']} API calls have response data")
        print(f"Device/edge entry count: {effective_mock_count}  (orgs/enterprises: {effective_org_count})")

        collection = PostmanMockGenerator.generate(vendor=args.vendor, rpc_payload=payload_from_file, mock_count=user_mock_count, mock_org_count=user_mock_org_count)

        # Write to Postman-Collections/ directory
        output_dir = str(Path(generator.root_dir) / "Postman-Collections")
        collection_path = PostmanMockGenerator.write(
            vendor=args.vendor,
            collection=collection,
            output_dir=output_dir,
        )

        enabled_calls = [
            c for c in (payload_from_file.get("pluginCalls") or [])
            if isinstance(c, dict) and int(bool(c.get("enabled", 1)))
        ]

        # Report response source per call
        print(f"\n--- {len(enabled_calls)} mock endpoint(s) generated ---\n")
        for call in enabled_calls:
            call_id = call.get("callId", "?")
            method = (call.get("method") or "GET").upper()
            path = call.get("path") or "/"
            _, source = PostmanMockGenerator._pick_response_body(call)
            source_label = {
                "customerData": "customer response",
                "apiExamples": "OpenAPI example",
                "synthetic": "synthetic placeholder",
            }.get(source, source)
            print(f"  {call_id}: {method} {path}  [{source_label}]")

        print(f"\nPostman collection written to: {collection_path}")
        print()
        print("=" * 70)
        print("NEXT STEPS:")
        print("=" * 70)
        print(f"1. Open Postman and import '{collection_path}'.")
        print(f"2. In Postman: Collections → '{args.vendor} API Mock Collection' → Create Mock Server.")
        print(f"3. Copy the mock server URL (e.g., https://xxxxxxxx.mock.pstmn.io).")
        print(f"4. In NetMRI/NI, configure the SDN controller with the mock URL as the address.")
        print(f"5. Start a collection poll — the mock server will return the saved responses.")
        print(f"6. Once validated, run Step 2 to generate production Perl modules:")
        print(f"   python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \\")
        print(f"     --vendor {args.vendor} --payload-input {args.payload_input} --step2 --root {args.root}")
        print()

        result = {
            "payload": payload_from_file,
            "files": {"payload_path": args.payload_input, "collection_path": collection_path},
            "mode": "postman-mock",
        }

    elif args.step2 or (args.payload_input and not args.source and not args.step1):
        # --- Step 2: Generate Perl modules from filled payload ---
        if not args.payload_input:
            raise ValueError("Step 2 requires --payload-input pointing to the filled payload JSON")

        payload_from_file = Scaffolder.load_payload(args.payload_input)

        # Report customer data fill status
        cd_summary = _customer_data_summary(payload_from_file)
        print(f"\n=== Step 2: Generating Perl modules from payload ===")
        print(f"Payload: {args.payload_input}")
        print(f"Customer data: {cd_summary['filled']}/{cd_summary['total']} API calls have response data")
        if cd_summary["empty_calls"]:
            print(f"WARNING: {len(cd_summary['empty_calls'])} call(s) still have empty customerData.sampleResponse:")
            for line in cd_summary["empty_calls"]:
                print(line)
            print("Code generation will proceed but transforms for these calls will be skeleton-only.\n")

        client_code = ClientGenerator.generate(vendor=args.vendor, rpc_payload=payload_from_file, root_dir=generator.root_dir)
        controller_code = ControllerGenerator.generate(vendor=args.vendor, rpc_payload=payload_from_file, root_dir=generator.root_dir)
        scaffolder = Scaffolder(
            root_dir=generator.root_dir,
            client_dir=generator.client_dir,
            controller_dir=generator.controller_dir,
            payload_dir=generator.payload_dir,
        )
        written = scaffolder.write_perl_modules(
            vendor=args.vendor,
            client_code=client_code,
            controller_code=controller_code,
        )
        result = {
            "payload": payload_from_file,
            "files": {
                **written,
                "payload_path": args.payload_input,
            },
            "mode": "modules-from-payload",
        }

        print("\nGenerated files:")
        print(f"  Client:     {result['files']['client_path']}")
        print(f"  Controller: {result['files']['controller_path']}")
        print(f"\nStep 2 complete. Production-ready Perl modules have been generated.")

        _print_deployment_notes(args.vendor, payload_from_file, result["files"])

    else:
        # --- Step 1: Parse OpenAPI and generate payload with empty customerData ---
        if not args.source:
            raise ValueError("Step 1 requires --source pointing to an OpenAPI spec (YAML or JSON file/URL)")

        print(f"\n=== Step 1: Parsing OpenAPI spec and identifying API calls ===")
        print(f"Source: {args.source}")

        payload = generator.generate_payload(
            source=args.source,
            vendor=args.vendor,
            plugins=plugins,
        )
        scaffolder = Scaffolder(
            root_dir=generator.root_dir,
            client_dir=generator.client_dir,
            controller_dir=generator.controller_dir,
            payload_dir=generator.payload_dir,
        )
        payload_path = scaffolder.write_payload(vendor=args.vendor, rpc_payload=payload)
        payload_from_file = Scaffolder.load_payload(payload_path)
        result = {
            "payload": payload_from_file,
            "files": {
                "payload_path": payload_path,
            },
            "mode": "payload-only",
        }

        # Print identified API calls for user
        enabled_calls = [
            c for c in (payload_from_file.get("pluginCalls") or [])
            if isinstance(c, dict) and int(bool(c.get("enabled", 1)))
        ]

        print(f"\nPayload written to: {payload_path}")
        print(f"\n--- Identified {len(enabled_calls)} API call(s) for {args.vendor} ---\n")
        for call in enabled_calls:
            call_id = call.get("callId", "?")
            method = (call.get("method") or "GET").upper()
            path = call.get("path") or "/"
            op_id = call.get("operationId") or "unknown"
            plugins = ", ".join(call.get("plugins") or []) or "(no plugins)"
            print(f"  {call_id}: {method} {path}")
            print(f"          operationId: {op_id}")
            print(f"          plugins: {plugins}")
            params = call.get("parameters") or {}
            if params.get("path"):
                print(f"          path params: {', '.join(params['path'])}")
            if params.get("query"):
                print(f"          query params: {', '.join(params['query'])}")
            print()

        print("=" * 70)
        print("NEXT STEPS:")
        print("=" * 70)
        print(f"1. Review the identified API calls above.")
        print(f"2. Share these API calls with the customer to obtain actual response data.")
        print(f"3. For each API call in '{payload_path}',")
        print(f"   fill the 'customerData.sampleResponse' field with the actual JSON response.")
        print(f"4. Optionally fill 'customerData.sampleRequest' and 'customerData.responseNotes'.")
        print(f"5. Set 'customerData.collectedAt' to the collection timestamp.")
        print(f"6. To drop unwanted calls, set review.action='drop' or enabled=0.")
        print(f"7. Generate a Postman Mock Collection for testing (Step 1.5):")
        print(f"   python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \\")
        print(f"     --vendor {args.vendor} --payload-input {payload_path} --step1.5 --root {args.root}")
        print(f"   Add --mock-count N to override the default 1000 device/edge entries (e.g. --mock-count 5000).")
        print(f"   Add --mock-org-count N to override the default 10 org/enterprise entries (e.g. --mock-org-count 50).")
        print(f"8. Once validated with mock server, generate production Perl modules (Step 2):")
        print(f"   python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \\")
        print(f"     --vendor {args.vendor} --payload-input {payload_path} --step2 --root {args.root}")
        print()

    stats = result.get("payload", {}).get("stats") or {}
    if stats:
        print(
            "Matched plugin mappings: "
            f"{stats.get('matchedPlugins', 0)}/{stats.get('totalPlugins', 0)} "
            f"using {stats.get('selectedOperations', 0)} API calls"
        )
        print(f"Skipped plugins: {stats.get('skippedPlugins', 0)}")
    else:
        total = len(result.get("payload", {}).get("pluginCalls", []) or [])
        matched = 0
        for call in result.get("payload", {}).get("pluginCalls", []) or []:
            if (call.get("_debug") or {}).get("matched") or call.get("matched"):
                matched += 1
        print(f"Matched plugin mappings: {matched}/{total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())