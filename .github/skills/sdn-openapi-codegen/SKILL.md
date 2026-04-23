---
name: sdn-openapi-codegen
description: "**WORKFLOW SKILL** — Generate NetMRI/NI SDN vendor integrations from OpenAPI specs. USE FOR: adding a new SD-WAN vendor (VeloCloud, Meraki, Mist, etc.); running the 4-step codegen pipeline (parse OpenAPI → fill customer data → Postman mock testing → generate Perl modules); deploying generated Client/Controller code to a NetMRI appliance; troubleshooting payload generation or module output. DO NOT USE FOR: editing existing production Client/Controller modules by hand; general Perl questions; unrelated OpenAPI work."
argument-hint: "Vendor name and OpenAPI spec location, e.g. 'VeloCloud from VeloCloud/Velo-openapi.yaml'"
---

# SDN OpenAPI Codegen Workflow

Generate production-ready Perl Client and Controller modules for a new SD-WAN
vendor integration in NetMRI/NI, starting from the vendor's OpenAPI specification.

## When to Use

- Adding a **new SD-WAN vendor** to NetMRI (e.g., VeloCloud, Meraki, Mist, SilverPeak, Viptela)
- Re-generating modules after payload updates or OpenAPI spec changes
- Creating Postman mock collections to validate collection logic before production deployment
- Deploying generated code to a NetMRI/NI appliance or Docker container

## Prerequisites

- Python 3.8+ (`python3 --version`)
- The vendor's OpenAPI spec file (YAML or JSON) or a URL to it
- Postman desktop app for mock server testing (Step 1.5)
- Access to a NetMRI/NI appliance or Docker container (deployment)
- Working directory: repository root (`SDN-Agent/`)

## Procedure

All commands assume you are in the `SDN-Agent` repository root.
Always pass `--root .` so plugin discovery resolves correctly.

---

### Step 1 — Parse OpenAPI Spec → Payload JSON

**Goal:** Identify which vendor API endpoints map to NetMRI SDN plugins.
Produces a payload JSON with empty `customerData` fields for the user to fill.

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --source <OPENAPI_FILE_OR_URL> \
  --vendor <VendorName> \
  --step1 \
  --root .
```

**Output:** `Payloads/<VendorName>-Payload.json`

**Post-step actions (manual):**

1. Review the identified API calls printed by the tool.
2. For each `pluginCall` entry in the payload JSON:
   - Call the vendor's API (use the `curlExample` in `_developerGuide`).
   - Paste the full JSON response body into `customerData.sampleResponse`.
   - Set `customerData.collectedAt` to the current date.
3. To exclude an API call, set `"review": { "action": "drop" }` or `"enabled": 0`.
4. When all data is collected, set `manualReview.status` to `"approved"`.

---

### Step 1.5 — Generate Postman Mock Collection (optional but recommended)

**Goal:** Create an importable Postman Collection for mock-server testing
before generating production code.

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <VendorName> \
  --payload-input Payloads/<VendorName>-Payload.json \
  --step1.5 \
  --root .
```

**Optional mock-data flags:**

| Flag | Default | Purpose |
|------|---------|---------|
| `--mock-count N` | 1000 | Number of device/edge records |
| `--mock-org-count N` | 10 | Number of org/enterprise records |

**Output:** `Postman-Collections/<VendorName>-Mock-Collection.postman_collection.json`

**Post-step actions (manual):**

1. Import the JSON file into Postman (`Cmd+O` → Upload).
2. Right-click the collection → **Mock collection** → **Create Mock Server**.
3. Copy the mock server URL (`https://xxxxxxxx.mock.pstmn.io`).
4. Configure NetMRI to point at the mock URL (via UI or SQL — see [reference](./references/mock-server-setup.md) if available).
5. Run `checkSdnConnection.pl` to validate connectivity:
   ```bash
   ./checkSdnConnection.pl \
     --sdn_type <VENDORNAME_UPPER> \
     --address xxxxxxxx.mock.pstmn.io \
     --protocol https \
     --api_key MOCK-TOKEN-123
   ```
6. Trigger a collection poll to verify end-to-end data flow.

---

### Step 2 — Generate Production Perl Modules

**Goal:** Produce the Client (HTTP wrapper) and Controller (collection
orchestrator) Perl modules from the filled payload.

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <VendorName> \
  --payload-input Payloads/<VendorName>-Payload.json \
  --step2 \
  --root .
```

**Output:**
- `Output/Client/<VendorName>.pm` — HTTP client with API methods
- `Output/SDN/<VendorName>.pm` — Controller with collection methods and data transforms

**Behavior notes:**
- When `customerData.sampleResponse` is present, the generator produces informed field mappings and vendor-specific auth/pagination helpers.
- When `customerData.sampleResponse` is missing, skeleton transforms with `TODO` markers are generated instead.

---

### Step 3 — Sync & Deploy Dependent Files

After Step 2, **you must** handle deployment copies and shared-file updates.

#### 3a. Copy generated output to Files/

```
Output/Client/<Vendor>.pm  →  Files/<Vendor>/<Vendor>-Client.pm
Output/SDN/<Vendor>.pm     →  Files/<Vendor>/<Vendor>-Controller.pm
```

Create `Files/<Vendor>/` if it does not exist.

#### 3b. Generate vendor-specific files

| File | Locations | Purpose |
|------|-----------|---------|
| `Save<Vendor>Organizations.pm` | `Controller/SDN/Plugins/` + `Files/<Vendor>/` | Plugin to persist org/tenant data |
| `<Vendor>Organization.sql` | `Files/<Vendor>/` | DDL for vendor organization table |

Key data-type decisions:
- UUID identifiers (e.g., VeloCloud `logicalId`) → `char(64)` columns, UUID regex validation.
- Numeric identifiers (e.g., Meraki `organizationId`) → `INT` columns, `^\d+$` validation.

#### 3c. Update shared files

| File | Action |
|------|--------|
| `ApiHelperFactory.pm` | Register vendor in factory dispatch; add `use` statement and `get_<vendor>_helper` sub |
| `Base.pm` | Add plugin name to `autoload_save_methods` list |
| `PropertyGroup.sql` | Add property group entries for vendor datasets |
| `PropertyGroupDef.sql` | Add obtainEverything entry for vendor |
| `getDeviceList.sql` / `getDeviceList.debug.sql` | Add UNION clause for vendor device table |
| `checkSdnConnection.pl` | Add vendor case to connection-check logic |

#### 3d. Deploy to appliance

```bash
# Template:  ./deploy_<vendor>_to_ni.sh <container_name> [host_files_dir]
./deploy_velocloud_to_ni.sh ni Files
```

Post-deployment: run new `.sql` files, restart SDN Engine + Discovery Server,
configure the SDN controller, and trigger a collection poll.

---

## CLI Flags Reference

| Flag | Required | Description |
|------|----------|-------------|
| `--vendor <Name>` | Always | Vendor name (e.g., `VeloCloud`, `Mist`, `Meraki`) |
| `--source <path>` | Step 1 | OpenAPI spec file or URL |
| `--step1` | Step 1 | Parse OpenAPI → payload JSON |
| `--step1.5` | Step 1.5 | Generate Postman mock collection |
| `--step2` | Step 2 | Generate Perl modules from payload |
| `--payload-input <path>` | Steps 1.5, 2 | Path to the filled payload JSON |
| `--root <dir>` | Recommended | Workspace root (default: `.`) |
| `--mock-count N` | Optional | Device count for mock data (default: 1000) |
| `--mock-org-count N` | Optional | Org count for mock data (default: 10) |
| `--threshold N` | Optional | Match confidence threshold (default: 0.25) |
| `--plugin-dir <dir>` | Optional | Plugin directory override |
| `--output-dir <dir>` | Optional | Output directory override |

## Directory Map

```
SDN-Agent/
├── tools/openapi_codegen/     # Code generator (you run this)
│   ├── bin/                   #   CLI entry point
│   ├── src/python/            #   Core Python module
│   └── templates/             #   Perl module templates
├── Payloads/                  # Step 1 output: payload JSON files
├── Postman-Collections/       # Step 1.5 output: Postman mock collections
├── Output/                    # Step 2 output: generated Perl modules
│   ├── Client/                #   HTTP client wrappers
│   └── SDN/                   #   Collection controllers
├── Controller/SDN/Plugins/    # Production Save*.pm plugins
├── Client/                    # Production HTTP client modules
├── Files/                     # Deployment-ready copies
│   └── <Vendor>/              #   Vendor-specific deployment files
├── <Vendor>/                  # OpenAPI specs and vendor docs
└── deploy_*.sh                # Deployment scripts
```

## Invariants & Safety Rules

1. **Files/ mirroring** — Every edit to `Output/` modules MUST be propagated to `Files/<Vendor>/`.
2. **Plugin mirroring** — Every edit to `Controller/SDN/Plugins/Save*.pm` MUST be propagated to `Files/<Vendor>/Save*.pm`.
3. **Auto-increment safety** — Never include auto-increment columns (`SdnDeviceID`, `sdn_network_id`) in application-level data hashes passed to Save plugins.
4. **Trailing-slash consistency** — When a vendor API uses trailing slashes, ensure Client URIs, Postman mock paths, and OpenAPI paths all match.
5. **Customer data gate** — Never skip the data-collection step between Step 1 and Step 2; skeleton modules are generated without it but production code requires real response data.
6. **Step 3 is mandatory** — Never skip dependent-file sync after Step 2.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Step 1 requires --source` | Add `--source <path>` pointing to the OpenAPI file or URL |
| `Step 1.5 requires --payload-input` | Point `--payload-input` to the filled payload JSON |
| Mock server returns 404 | Verify request URL matches collection paths; check `base_url` variable |
| `0/N API calls have response data` | Fill `customerData.sampleResponse` — synthetic data is used in the meantime |
| Connection check fails | Ensure mock server is active; use host only in `--address` (no `https://`) |
| Generated code has skeleton transforms | Fill `customerData.sampleResponse` for informed field mappings |
| Plugin discovery misses plugins | Run from repo root or pass `--root .` so `SDN/Plugins` resolves |
