---
name: vendor-risk-review
description: Third-party and AI risk review across vendors, the applications they provide and the systems that depend on them. Use for vendor risk, AI risk, PII or NPPI exposure, and "what is affected if vendor X has an incident" questions.
---

<!-- Boilerplate example skill. Fine-tune the steps and rules to your governance process. -->

# Vendor risk review

## The chain

Vendors connect to systems only through applications:

vendor --provides--> application <--utilizes-- system

Always walk the whole chain with `catalog_analyst`. Never link a vendor straight to a system.

## Steps

1. **Scope.** For a named vendor, resolve the exact name first. If the name is loose, use `catalog_search`
   filtered to `ASSET_TYPE = 'Vendor'`. For a portfolio question ("which vendors are high risk"), the scope is
   every vendor where vendor risk or AI risk is High.
2. **Vendor profile.** Get vendor status, vendor risk level, AI risk level, service model and PII / NPPI flag.
3. **Applications.** Get the applications the vendor provides, with tier, RTO and platform.
4. **Dependent systems.** Get the systems that use those applications, and whether each system handles PII / NPPI.
5. **Owners.** For each dependent system, give its business owner and technical owner.

## Answer format

- Headline: "<Vendor>: vendor risk <x>, AI risk <y>, PII <yes/no/unknown>, <n> applications, <m> dependent systems."
- Table: Application | Tier | RTO | Dependent systems.
- Flag in one line each:
  - any Tier 1 application from a High-risk vendor
  - any PII-handling system that depends on a vendor whose PII flag is Unknown or Not Assessed
  - any Inactive vendor that still provides applications
- For a portfolio question, rank vendors by number of applications, then by number of dependent PII systems.

## Rules

- "Not Assessed" and "Unknown" are findings, not missing data. Report them.
- Do not give a risk score of your own. Use only the stored ratings.
- This is catalog metadata. It does not show contracts, incidents or SLAs; say so if asked.
