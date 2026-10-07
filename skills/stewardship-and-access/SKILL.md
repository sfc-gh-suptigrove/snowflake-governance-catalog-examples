---
name: stewardship-and-access
description: Find who owns, stewards or supports a domain, community or asset, and who to contact to request access or a change. Use for who-owns, who-stewards, who-do-I-ask and how-do-I-get-access questions.
---

<!-- Boilerplate example skill. Fine-tune the steps and rules to your governance process. -->

# Stewardship and access

## Who does what

- **Data Owner**: approves access requests.
- **Data Steward**: owns definitions, quality and status changes in a domain.
- **Technical Owner/Custodian**: supports the platform and pipelines.

## Steps

1. Resolve the domain, community or asset name. If it is loose, use `catalog_search` first.
2. Ask `catalog_analyst` for the effective accountability of the domain. It already includes owners
   inherited from the community, flagged as inherited. For an asset or term, use the domain it belongs to.
3. If a role is missing at both domain and community level, say so; do not substitute silently.
4. Match the person to the intent:
   - access request -> Data Owner. If no Data Owner is recorded, give the Data Steward as the person who
     can route the request, and say that no Data Owner is recorded.
   - wrong definition, status or description -> Data Steward
   - broken pipeline, load or platform issue -> Technical Owner/Custodian

## Answer format

- "For <intent> on <resource>, contact <name> (<role>, <email>)."
- Then the full list: Level | Role | Name | Email.
- If there is no assignment at any level, say "No owner or steward is recorded for <resource>" and suggest
  the governance team record one.

## Rules

- You cannot grant access, change ownership or change status. Say who can.
- Never invent a person or an email.
