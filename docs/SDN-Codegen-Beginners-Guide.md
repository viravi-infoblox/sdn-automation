# SDN OpenAPI Codegen — Beginner's Guide

This guide walks through the complete workflow for adding a new SD-WAN vendor
integration to NetMRI/NI using the OpenAPI code generator.

---

## Prerequisites

- **Python 3.8+** installed (`python3 --version` to check)
- **Git** installed
- The vendor's OpenAPI specification file (YAML or JSON) or a URL to it
- **Postman** desktop app (free — https://www.postman.com/downloads/)
- Access to a NetMRI/NI appliance or Docker container (for deployment)

## Getting Started

```bash
# Clone the repository
git clone <repo-url> SDN-Agent
cd SDN-Agent

# (Optional) Create a Python virtual environment
python3 -m venv .venv
source .venv/bin/activate   # macOS/Linux
# .venv\Scripts\activate    # Windows
```

All commands in this guide assume you are in the `SDN-Agent` root directory.
The `--root .` flag tells the script to use the current directory as the
workspace root for finding plugins and writing output files.

## Directory Structure

```
SDN-Agent/
├── tools/openapi_codegen/       # The code generator (you run this)
│   ├── bin/                     #   CLI entry point
│   ├── src/python/              #   Core Python module
│   └── templates/               #   Perl module templates
├── Payloads/                    # Step 1 output: payload JSON files
├── Postman-Collections/         # Step 1.5 output: Postman mock collections
├── Output/                      # Step 2 output: generated Perl modules
│   ├── Client/                  #   HTTP client wrappers
│   └── SDN/                     #   Collection controllers
├── Controller/SDN/              # Production SDN modules + plugins
│   └── Plugins/                 #   Save*.pm plugin modules
├── Client/                      # Production HTTP client modules
├── Files/                       # Deployment-ready copies for appliance
│   └── <Vendor>/                #   Vendor-specific files
├── <Vendor>/                    # OpenAPI specs and vendor docs
│   └── <vendor>-openapi.yaml
├── docs/                        # Documentation (this guide)
├── sdnEngine/                   # SDN engine scripts
└── deploy_*.sh                  # Deployment scripts
```

**Key directories for the workflow:**
- You **read** from `<Vendor>/` (OpenAPI specs)
- Step 1 **writes** to `Payloads/`
- Step 1.5 **writes** to `Postman-Collections/`
- Step 2 **writes** to `Output/Client/` and `Output/SDN/`
- You **deploy** from `Files/` (copy generated output + shared files here first)

## Quick Reference — The Three Steps

```
Step 1    Parse OpenAPI spec → Payload JSON (identify API calls)
              ↓
          User collects real API responses from vendor
              ↓
Step 1.5  Generate Postman Mock Collection → Test with mock server
              ↓
Step 2    Generate production Perl modules → Deploy to NetMRI
```

---

## Step 1: Parse the OpenAPI Spec

**What it does:** Reads the vendor's OpenAPI spec and identifies which API
endpoints map to NetMRI's SDN plugin system.  Produces a payload JSON file
with empty `customerData` fields for you to fill.

**Command:**

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --source <OPENAPI_FILE_OR_URL> \
  --vendor <VendorName> \
  --step1 \
  --root .
```

**Example (VeloCloud):**

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --source VeloCloud/Velo-openapi.yaml \
  --vendor VeloCloud \
  --step1 \
  --root .
```

**Output:** `Payloads/VeloCloud-Payload.json`

The script prints a list of identified API calls.  Review them — each one
shows the HTTP method, path, operationId, and which NetMRI plugins it covers.

### Filling in Customer Data

Open the generated payload JSON and for each `pluginCall` entry:

1. Call the vendor's API (use the `curlExample` in `_developerGuide`)
2. Copy the **full JSON response body**
3. Paste it into `customerData.sampleResponse` (replace `null`)
4. Set `customerData.collectedAt` to the current date
5. Optionally add `customerData.responseNotes` with any observations

To **exclude** an API call you don't need, set:
```json
"review": { "action": "drop" }
```
or set `"enabled": 0`.

---

## Step 1.5: Generate & Test with Postman Mock Server

**What it does:** Creates a Postman Collection JSON file from your payload.
Each enabled API call becomes a mock endpoint that returns either your
customer data, the OpenAPI example, or infrastructure-consistent synthetic
data.  The synthetic data includes bidirectional BGP peers, LLDP neighbors,
forwarding tables, ARP/MAC tables, and proper IP route references — all
cross-verified for consistency.

**Command:**

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <VendorName> \
  --payload-input Payloads/<VendorName>-Payload.json \
  --step1.5 \
  --root .
```

**Optional flags:**

| Flag | Default | Purpose |
|------|---------|---------|
| `--mock-count N` | 1000 | Number of device/edge records in mock responses |
| `--mock-org-count N` | 10 | Number of org/enterprise records |

**Example:**

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor VeloCloud \
  --payload-input Payloads/VeloCloud-Payload.json \
  --step1.5 \
  --root . \
  --mock-count 50 \
  --mock-org-count 1
```

**Output:** `Postman-Collections/VeloCloud-Mock-Collection.postman_collection.json`

The script also prints a consistency report verifying that all mock data
relationships are valid (BGP, LLDP, routes, ARP, MAC tables — all 0 failures).

---

### Importing into Postman and Creating a Mock Server

#### 1. Import the Collection

1. Open **Postman** desktop app
2. Click **Import** (top-left, or `Ctrl+O` / `Cmd+O`)
3. Drag and drop the generated `.postman_collection.json` file, or click
   **Upload Files** and select it
4. Click **Import** to confirm

You should see the collection appear in the left sidebar under **Collections**
with the name `<Vendor> API Mock Collection`.

#### 2. Create a Mock Server

1. In the left sidebar, click the **three dots** (`...`) next to the
   imported collection name
2. Select **Mock collection**
3. In the dialog:
   - **Mock server name:** give it any name (e.g., `VeloCloud Mock`)
   - **Environment:** leave as "No Environment" (variables are in the collection)
   - Uncheck **Save the mock server URL as a new environment** (optional)
4. Click **Create Mock Server**
5. Postman shows the mock server URL — it looks like:
   ```
   https://xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.mock.pstmn.io
   ```
6. **Copy this URL** — you'll need it for NetMRI configuration

> **Tip:** The mock server URL is also visible under **Mock Servers** in the
> left sidebar at any time.

#### 3. Test the Mock Server

In Postman, try sending a request to your mock server:

1. Open any request in the imported collection (e.g., "List Enterprises")
2. In the **Variables** tab of the collection, set `base_url` to your mock
   server URL (e.g., `https://xxxxxxxx.mock.pstmn.io`)
3. Click **Send**
4. You should get a `200 OK` response with the mock data

#### 4. Configure NetMRI/NI to Use the Mock Server

**Option A — Via NetMRI UI:**

1. Navigate to **Settings → SDN Controllers**
2. Add a new controller:
   - **Type:** `<VendorName>` (e.g., `VeloCloud`)
   - **Address:** your mock server URL (without `https://`)
   - **Protocol:** `https`
   - **API Key:** any non-empty string (e.g., `MOCK-TOKEN-123`)

**Option B — Via SQL insert (development/testing):**

```sql
INSERT INTO config.sdn_controller_settings (
    id, virtual_network_id, controller_address, protocol,
    sdn_username, sdn_password, SecureVersion,
    created_at, updated_at, UnitID, sdn_type, api_key,
    on_prem, use_global_proxy, handle, scan_interface_id,
    ca_cert_id, ca_cert_content,
    start_blackout_schedule, blackout_duration,
    max_requests_per_second, collect_offline_devices
) VALUES (
    "1", "2",
    "xxxxxxxx.mock.pstmn.io",   -- your mock server host
    "https",
    NULL, NULL, 1,
    NOW(), NOW(), "0",
    "<VendorName>",             -- e.g. "VeloCloud"
    "<YOUR_API_KEY>",           -- any non-empty string for mock
    "0", "1", "TEST", "1",
    NULL, NULL, "", "0", "0", ""
);
```

Then add a polling schedule:

```sql
INSERT IGNORE INTO SdnPollingSchedule (
    tid, Fabric, Target, Datapoint,
    ScheduledTime, Frequency, IsPending, DebugOn
) VALUES (
    1, 1, 'Global', 'obtainEverything',
    NOW(), '3600', '0', '0'
);
```

#### 5. Validate the Connection

```bash
./checkSdnConnection.pl \
  --sdn_type <VENDORNAME_UPPER> \
  --address xxxxxxxx.mock.pstmn.io \
  --protocol https \
  --api_key MOCK-TOKEN-123
```

Example:
```bash
./checkSdnConnection.pl \
  --sdn_type VELOCLOUD \
  --address xxxxxxxx.mock.pstmn.io \
  --protocol https \
  --api_key MOCK-TOKEN-123
```

#### 6. Trigger a Collection Poll

Restart the SDN Engine and Discovery Server, then trigger a poll to verify
the mock server returns data that the Client/Controller modules can process.

---

## Step 2: Generate Production Perl Modules

**What it does:** Generates the production-ready Client and Controller Perl
modules from your filled payload.

**Command:**

```bash
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <VendorName> \
  --payload-input Payloads/<VendorName>-Payload.json \
  --step2 \
  --root .
```

**Output:**
- `Output/Client/<VendorName>.pm` — HTTP client wrapper
- `Output/SDN/<VendorName>.pm` — Collection controller

The script also prints **Deployment Notes** listing every file that needs to
be copied or modified on the NetMRI appliance.

---

## Deployment to NetMRI/NI

After Step 2, the script prints a full deployment checklist.  Here is the
general pattern for any vendor:

### A. Generated Files — Copy to Appliance

| File | Source (local) | Target (appliance) |
|------|---------------|---------------------|
| Controller | `Output/SDN/<Vendor>.pm` | `/usr/local/lib/site_perl/NetMRI/SDN/<Vendor>.pm` |
| Client | `Output/Client/<Vendor>.pm` | `/usr/local/lib/site_perl/NetMRI/HTTP/Client/<Vendor>.pm` |

### B. New Vendor-Specific Files — Create on Appliance

Each vendor may require new plugin modules and SQL table definitions.
These are detected automatically from the payload and listed in the
Step 2 output.

| File Type | Source (local) | Target (appliance) |
|-----------|---------------|---------------------|
| Plugin `.pm` | `Controller/SDN/Plugins/Save<VendorPlugin>.pm` | `/usr/local/lib/site_perl/NetMRI/SDN/Plugins/Save<VendorPlugin>.pm` |
| Table `.sql` | `Files/<Vendor>/<TableName>.sql` | `/infoblox/netmri/db/db-netmri/create/<TableName>.sql` |

### C. Standard Files — Modify for New Vendor

These files already exist on the appliance and need vendor-specific additions:

| File | Appliance Path | Action |
|------|---------------|--------|
| `ApiHelperFactory.pm` | `/usr/local/lib/site_perl/NetMRI/SDN/ApiHelperFactory.pm` | Register vendor in factory dispatch |
| `Base.pm` | `/usr/local/lib/site_perl/NetMRI/SDN/Base.pm` | Add vendor to `autoload_save_methods` |
| `getDeviceList.sql` | `/infoblox/netmri/app/transaction/netmri/processors/discovery/getDeviceList.sql` | Add UNION clause for vendor device table |
| `getDeviceList.debug.sql` | `/infoblox/netmri/app/transaction/netmri/processors/discovery/getDeviceList.debug.sql` | Mirror the `getDeviceList.sql` change |
| `checkSdnConnection.pl` | `/infoblox/netmri/app/transaction/netmri/collectors/sdnEngine/checkSdnConnection.pl` | Add vendor case to connection-check |
| `PropertyGroup.sql` | `/infoblox/netmri/db/db-netmri/DeviceSupport/PropertyGroup.sql` | Add property groups for vendor |
| `PropertyGroupDef.sql` | `/infoblox/netmri/db/db-netmri/DeviceSupport/PropertyGroupDef.sql` | Add property group definitions |

### D. Post-Deployment

1. Run any new `.sql` files to create vendor tables
2. Restart SDN Engine and Discovery Server
3. Configure the SDN controller (UI or SQL)
4. Trigger a collection poll to validate

### Using the Deploy Script

A deploy script is provided that copies files into the NetMRI Docker
container, backs up existing files, and installs the new ones:

```bash
# Usage:  ./deploy_velocloud_to_ni.sh <container_name> [host_files_dir]
#
# container_name  — name of the running NetMRI Docker container
# host_files_dir  — path to the Files/ directory (defaults to ./Files)

# Example — deploy from the repo root:
./deploy_velocloud_to_ni.sh ni Files
```

For other vendors, create a similar deploy script following the same
file-mapping pattern shown in section C above, or copy files manually.

---

## CLI Flags Reference

| Flag | Required | Description |
|------|----------|-------------|
| `--vendor <Name>` | Always | Vendor name (e.g., `VeloCloud`, `Mist`, `Meraki`) |
| `--source <path>` | Step 1 | OpenAPI spec file or URL |
| `--step1` | Step 1 | Parse OpenAPI and generate payload JSON |
| `--step1.5` | Step 1.5 | Generate Postman Mock Collection |
| `--step2` | Step 2 | Generate Perl modules from filled payload |
| `--payload-input <path>` | Step 1.5, 2 | Path to the filled payload JSON |
| `--root <dir>` | Optional | Workspace root (default: `.`) |
| `--mock-count N` | Optional | Device count for mock data (default: 1000) |
| `--mock-org-count N` | Optional | Org count for mock data (default: 10) |
| `--threshold N` | Optional | Match confidence threshold (default: 0.25) |
| `--plugin-dir <dir>` | Optional | Plugin directory override |
| `--output-dir <dir>` | Optional | Output directory override |

---

## End-to-End Example (VeloCloud)

```bash
# 1. Parse OpenAPI spec
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --source VeloCloud/Velo-openapi.yaml \
  --vendor VeloCloud \
  --step1 --root .

# 2. (Manual) Fill customerData.sampleResponse in Payloads/VeloCloud-Payload.json

# 3. Generate mock collection and import into Postman
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor VeloCloud \
  --payload-input Payloads/VeloCloud-Payload.json \
  --step1.5 --root . \
  --mock-count 50 --mock-org-count 1

# 4. In Postman: Import JSON → Create Mock Server → Copy URL
# 5. Configure NetMRI with mock URL → Test collection poll

# 6. Generate production Perl modules
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor VeloCloud \
  --payload-input Payloads/VeloCloud-Payload.json \
  --step2 --root .

# 7. Deploy to NetMRI appliance
./deploy_velocloud_to_ni.sh ni Files
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Step 1 requires --source` | You forgot `--source`. Provide the OpenAPI file path or URL. |
| `Step 1.5 requires --payload-input` | Point `--payload-input` to your filled payload JSON. |
| Mock server returns `404` | Ensure the request URL matches the path in the collection exactly. Check that `base_url` variable is set to the mock server URL. |
| `0/N API calls have response data` | You haven't filled `customerData.sampleResponse` yet. This is OK — synthetic data will be used. |
| Connection check fails | Verify the mock server is active in Postman. Check that `--address` uses the host only (no `https://` prefix). |
| Generated code has skeleton transforms | Fill `customerData.sampleResponse` in the payload for informed field mappings. |
