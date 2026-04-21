# SDN OpenAPI Codegen Workflow

This code generator uses a **three-step process** with customer data collection and mock testing gates.

## Overview

```
Step 1:   OpenAPI Spec → Parse & Identify API Calls → Payload JSON (empty customerData)
                                                            ↓
                User shares API calls with customer, collects response data
                User fills customerData.sampleResponse in the payload JSON
                                                            ↓
Step 1.5: Filled Payload → Postman Mock Collection → Import into Postman Mock Server
                           → Test from NetMRI/NI against mock endpoints
                                                            ↓
Step 2:   Filled Payload → Generate Production-Ready Perl Modules
                           → Output/Client/<Vendor>.pm
                           → Output/SDN/<Vendor>.pm
```

## Step 1: API Discovery & Payload Generation

Input:
- OpenAPI source URL or file (YAML or JSON)
- Vendor name
- Optional plugin list

Output:
- `Payloads/<Vendor>-Payload.json` with empty `customerData` placeholders

Command:
```
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --source <URL_OR_FILE> --vendor <Vendor> --step1 --root .
```

Behavior:
- Parses the OpenAPI spec and identifies API operations matching SDN plugins.
- Uses plugin-field-intent matching and greedy set-cover selection.
- Writes ONLY the payload JSON file — no Perl modules are generated.
- Each `pluginCall` entry includes an empty `customerData` block:
  ```json
  "customerData": {
    "sampleResponse": null,
    "sampleRequest": null,
    "responseNotes": "",
    "collectedAt": ""
  }
  ```
- Prints a summary of identified API calls with next steps for the user.

### Customer Data Collection Gate

After Step 1, the user must:
1. Review the identified API calls in the payload JSON.
2. Share the API call list with their customer or test environment.
3. Execute each API call and collect the actual JSON responses.
4. Fill `customerData.sampleResponse` in the payload with the real response data.
5. Optionally fill `customerData.sampleRequest` and `customerData.responseNotes`.
6. Set `review.action = "drop"` for calls to exclude.
7. Set `manualReview.status = "approved"` once all data is collected.

## Step 1.5: Generate Postman Mock Collection (Optional)

Input:
- Filled payload JSON file from Step 1 (with customerData populated)
- Vendor name

Output:
- `Payloads/<Vendor>-Mock-Collection.postman_collection.json`

Command:
```
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <Vendor> --payload-input Payloads/<Vendor>-Payload.json --step1.5 --root .
```

Behavior:
- Reads the filled payload and generates a Postman Collection v2.1 JSON file.
- Each enabled pluginCall becomes a request item with a saved example response:
  - **customerData.sampleResponse** is used if available (preferred).
  - Falls back to **apiExamples.response** from the OpenAPI spec.
  - If neither exists, generates **synthetic mock data** based on plugin type.
- Authentication headers and path parameter variables are pre-configured.
- Reports the response source (customer / OpenAPI example / synthetic) for each endpoint.

### How to use the Mock Collection:
1. Open Postman and import the generated `.postman_collection.json` file.
2. Go to Collections → select the imported collection → Create Mock Server.
3. Copy the mock server URL (e.g., `https://xxxxxxxx.mock.pstmn.io`).
4. In NetMRI/NI, configure the SDN controller with the mock URL as the address.
5. Start a collection poll — the mock server returns the saved example responses.
6. Validate that the Client/Controller modules handle the responses correctly.

## Step 2: Generate Perl Modules from Filled Payload

Input:
- Filled payload JSON file from Step 1 (with customerData populated)
- Vendor name

Output:
- `Output/Client/<Vendor>.pm`
- `Output/SDN/<Vendor>.pm`

Command:
```
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <Vendor> --payload-input Payloads/<Vendor>-Payload.json --step2 --root .
```

Behavior:
- Reads the customer-filled payload JSON.
- Reports which calls have customerData filled vs empty.
- Generates Client module with per-operation API methods.
- Generates Controller module with collection methods and data transforms.
- When `customerData.sampleResponse` is available, generates informed field mappings.
- When `customerData.sampleResponse` is missing, generates skeleton transforms.

## Production-Compatible Features

- If a vendor template payload exists (e.g., `Payloads/<Vendor>-Payload-from-code.json`),
  Step 1 automatically uses that template as the baseline and enriches it from OpenAPI.
- Phase-2 templates (`Phase2-Client-Template.pm`, `Phase2-Controller-Template.pm`)
  provide production-aligned scaffolding.
- SDN collection blueprint embedded in payload JSON as `collectionPlan`.
- Preferred flow: Organizations → Sites → Devices → Device tables/state → Topology/endpoints.

## Defaults

When `--root .` is used:
- Payload directory: `Payloads`
- Perl output base: `Output`
- Client module: `Output/Client/<Vendor>.pm`
- Controller module: `Output/SDN/<Vendor>.pm`

