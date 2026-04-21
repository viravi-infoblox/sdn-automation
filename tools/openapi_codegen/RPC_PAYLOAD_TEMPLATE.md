# RPC Payload Standard Template

This is the standard JSON contract for the two-step SDN code generation workflow.

## Workflow

1. **Step 1**: Generate payload from OpenAPI source (API calls with empty customerData).
2. User collects actual API response data from customer and fills `customerData.sampleResponse`.
3. **Step 2**: Use filled payload JSON as input to generate Client/Controller modules.

## Top-level fields

- schema: Object with name/version
- vendor: Vendor name
- generatedAt: UTC timestamp of generation
- manualReview: Review metadata
- authentication: (optional) Authentication configuration
- pagination: (optional) Pagination configuration (see below)
- pluginCalls: Selected API calls used for generation
- skippedPlugins: Plugins that were not mapped
- reviewQueue: Low-confidence mappings and skipped plugins with reasons
- stats: Coverage statistics
- collectionPlan: 5-stage SDN collection blueprint

## pagination field (optional)

Controls how the generated Client module paginates API responses. Add this to
the top-level payload JSON. If omitted, the template's default Link-header
pagination is used.

```json
"pagination": {
  "strategy": "body_cursor",
  "dataField": "data",
  "cursorField": "metaData.nextPageLink",
  "cursorQueryParam": "nextPageLink",
  "maxPages": 100,
  "notes": "Description of how this vendor paginates"
}
```

Supported strategies:

| strategy | Description | Required fields |
|---|---|---|
| `body_cursor` | Response body contains a data array and a cursor token (e.g., VeloCloud `metaData.nextPageLink`) | `dataField`, `cursorField`, `cursorQueryParam` |
| `link_header` | HTTP `Link: <url>; rel="next"` header (default) | none |
| `offset` | Offset/limit numeric paging | `offsetParam`, `limitParam`, `pageSize` |

## pluginCalls entry fields

- callId: Stable ID (e.g., CALL-001)
- enabled: 1/0 (disabled calls are ignored by module generation)
- plugin: Primary plugin label (deprecated, use plugins)
- plugins: List of plugins covered by this API call
- operationId: OpenAPI operationId
- method: HTTP method
- path: OpenAPI endpoint path
- parameters: { path: [], query: [], body: 0|1 }
- score: Match confidence score
- coverageCount: Number of covered plugins
- coverageScore: coverageCount / totalPlugins
- apiExamples: request/response examples from OpenAPI spec (if available)
- customerData: Customer-provided API response data (see below)
- review: { status, action, notes }
- matched: 1/0

## customerData fields (filled by user between Step 1 and Step 2)

Each pluginCall entry contains a `customerData` object:

```json
"customerData": {
  "sampleResponse": null,
  "sampleRequest": null,
  "responseNotes": "",
  "collectedAt": ""
}
```

- **sampleResponse**: The actual JSON response from the customer's API. Paste the full JSON response here.
  - For list endpoints, include at least 1-2 representative items.
  - Can be an object or an array depending on the API.
- **sampleRequest**: The actual request made (URL + parameters). Optional but helpful.
- **responseNotes**: Any notes about the response (e.g., "truncated to 2 items", "auth required first").
- **collectedAt**: ISO timestamp of when the data was collected from the customer.

### How to fill customerData

1. Open the generated `Payloads/<Vendor>-Payload.json` file.
2. For each enabled pluginCall, find the `customerData` section.
3. Execute the API call described by `method` + `path` with the required `parameters`.
4. Paste the JSON response into `customerData.sampleResponse`.
5. Save the file and proceed to Step 2.

## Manual review rules

- To replace an API call, edit operationId/method/path/parameters in the target call entry.
- To drop a call, set review.action to "drop" (or enabled to 0).
- To keep a call, use review.action = "keep".
- After review, set manualReview.status to "approved" and fill reviewer fields.

## Commands

Step 1 (payload only):
```
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --source <URL_OR_FILE> --vendor <Vendor> --step1 --root .
```

Step 2 (modules from filled payload):
```
python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py \
  --vendor <Vendor> --payload-input Payloads/<Vendor>-Payload.json --step2 --root .
```
