---
marp: true
title: SDN Agent Workflow
author: SDN Automation Team
paginate: true
theme: default
---

# SDN Agent Workflow
## End-to-End OpenAPI-Driven Collection Pipeline

### Team Presentation Deck
- Date: 19 March 2026
- Scope: Mist case, reusable for all SDN vendors

---

# 1) Why This Agent Exists

## Problem
- Vendor SDN APIs evolve quickly.
- Hand-written controller/client code is expensive to maintain.
- Mapping plugins to APIs is hard to scale across vendors.

## Goal
- Convert OpenAPI + reviewed payload into production-aligned Perl modules.
- Keep review and generation explicit, auditable, and repeatable.

---

# 2) High-Level Architecture

## Core Components
- OpenAPI input: vendor API definitions.
- Payload contract: reviewed API-to-plugin mapping.
- Code generator: creates Client and SDN controller modules.
- Production plugin framework: transforms and persists datasets.

## Key Principle
- Separate mapping decisions from code generation.

---

# 3) Repository Map (Relevant Paths)

- OpenAPI specs:
  - mist.openapi.json
  - Meraki-OpenAPI.json
- Payloads:
  - Payloads/Mist-Payload.json
- Production modules:
  - Client/Mist.pm
  - SDN/Mist.pm
- Generated output:
  - Output/Client/Mist.pm
  - Output/SDN/Mist.pm
- Generator code:
  - tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py
  - tools/openapi_codegen/src/python/netmri_sdn_openapi_codegen.py
- Templates:
  - tools/openapi_codegen/templates/Phase2-Client-Template.pm
  - tools/openapi_codegen/templates/Phase2-Controller-Template.pm

---

# 4) Two-Phase Workflow

## Phase 1: Payload Generation
- Input: OpenAPI source + vendor.
- Output: Payload JSON with candidate API mappings.

## Phase 2: Module Generation
- Input: reviewed payload JSON.
- Output:
  - Output/Client/<Vendor>.pm
  - Output/SDN/<Vendor>.pm

## Benefit
- Human review gates API selection before code emission.

---

# 5) Payload Contract Essentials

## Top-Level Fields
- vendor
- pluginCalls
- manualReview
- reviewQueue
- stats
- collectionPlan

## pluginCalls (Important Fields)
- operationId, method, path, parameters
- plugins
- enabled
- matched
- review: status/action/notes

---

# 6) Review Semantics (Critical)

## What We Learned
- Rejected calls may appear as:
  - review.action: Remove/Reject
  - review.status: Rejected

## Generator Fix Implemented
- Calls are excluded if review indicates drop/remove/reject/rejected.
- This now works consistently for payload-driven generation.

---

# 7) Mist Payload Example (Approved Set)

## Approved Operations (Current)
- listInstallerSites
- getSiteWirelessClientStats
- countOrgSwOrGwPorts
- getOrgInventory
- countOrgWirelessClientsSessions
- getSiteAllClientsStatsByDevice

## Rejected Calls
- Explicitly filtered out before module generation.

---

# 8) Generated Client Module Strategy

## Client Responsibilities
- Auth + base URL wiring.
- Operation methods for approved payload calls.
- Path parameter substitution.
- Request dispatch through Generic client.

## Improvement Implemented
- Path params are required only if placeholders exist in path.

---

# 9) Controller Generation: Old vs New

## Before
- Thin API proxy methods only.
- No collection orchestration.
- No dataset save scaffolding.

## Now
- Production-style controller skeleton:
  - obtainEverything
  - loadSdnDevices
  - dataset-oriented methods
  - API helper wrappers
  - guarded save-call scaffolding

---

# 10) Controller Scaffolding (Current)

## Generated Collection Methods
- obtainOrganizationsAndNetworks
- getDevices
- obtainSystemInfo
- obtainPerformance
- obtainEnvironment
- obtainInterfaces
- obtainTopologyAndEndpoints

## Generated API Helpers
- api_<operation_method>() wrappers from approved payload operations.

---

# 11) Smarter Context Scaffolding

## New Context Helpers
- _generated_organizations()
- _generated_networks()
- _generated_extract_dn_context()
- _generated_api_args_from_organization()
- _generated_api_args_from_network()
- _generated_api_args_from_device()

## Impact
- Generated loops now model org/site/device call patterns, not generic placeholders.

---

# 12) Production Alignment Pattern

## Production Controllers (Reference)
- SDN/Mist.pm
- SDN/Meraki.pm
- SDN/Viptela.pm

## Alignment Goals
- Keep Base framework behavior intact.
- Keep orchestration in controller layer.
- Keep API details in client layer.
- Keep plugin save flow explicit and testable.

---

# 13) End-to-End Command Flow

## Generate from reviewed payload
- /usr/local/bin/python3 tools/openapi_codegen/bin/generate_sdn_vendor_from_openapi.py --vendor Mist --payload-input Payloads/Mist-Payload.json --root .

## Outputs
- Output/Client/Mist.pm
- Output/SDN/Mist.pm

## Validation
- Parse/lint checks in editor problems.
- Manual comparison against production logic.

---

# 14) Quality Controls in Workflow

## Guardrails
- Reviewed payload is the source of truth.
- Rejected APIs are auto-excluded.
- Disabled calls are ignored.
- Approved calls are deduplicated by operationId.

## Engineering Review Points
- Operation coverage vs plugin expectations.
- Dataset transform correctness.
- Save method mapping correctness.

---

# 15) Current Status (Mist)

## Completed
- Rejection filter bug fixed.
- Client path-parameter bug fixed.
- Controller generator upgraded to production-style scaffolding.
- Context-aware loop/arg scaffolding added.

## Remaining
- Fill vendor-specific transforms in generated controller methods.
- Validate dataset-level parity with SDN/Mist.pm production behavior.

---

# 16) Demo Plan for Team Meeting

## Suggested Live Demo (10-12 min)
1. Show reviewed payload and rejected entries.
2. Run generation command.
3. Open generated Client and SDN files.
4. Highlight orchestration methods and context helpers.
5. Compare one method with production SDN/Mist.pm.
6. Show what remains manual and why.

---

# 17) Rollout Strategy

## Near-Term
- Use generated controller as structured scaffold.
- Implement transforms method-by-method with production parity checks.

## Mid-Term
- Add vendor-seed hooks to generator (for self/org discovery methods).
- Add golden payload tests for generator output stability.

## Long-Term
- Reuse workflow across Meraki, Viptela, SilverPeak, and new vendors.

---

# 18) Risks and Mitigations

## Risks
- False-positive API matches from OpenAPI intent mapping.
- Payload review drift from production plugin semantics.
- Overconfidence in generated scaffolding.

## Mitigations
- Enforce review discipline in payload JSON.
- Keep rejected/disabled semantics strict.
- Compare generated outputs with production modules before merge.
- Add integration tests on transformed datasets.

---

# 19) Key Takeaways

- The workflow is now review-first, deterministic, and reusable.
- Generator output has moved from proxy stubs to production-style scaffolding.
- Mist case proves the path from OpenAPI -> reviewed payload -> structured modules.
- Remaining work is business logic transformation, not plumbing.

---

# 20) Q&A

## Appendix References
- docs/SDN-Agent-Workflow-Deck.md
- tools/openapi_codegen/WORKFLOW.md
- Payloads/Mist-Payload.json
- SDN/Mist.pm
- Output/SDN/Mist.pm
