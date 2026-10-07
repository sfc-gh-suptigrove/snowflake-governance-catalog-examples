---
name: migration-reconciliation
description: Explain the Collibra-to-Snowflake conversion plan and prove completeness. Use for where an asset type lands in Snowflake, which lane it is in, whether every asset migrated, what is being retired, and bronze vs gold counts.
---

<!-- Boilerplate example skill. Fine-tune the steps and rules to your governance process. -->

# Migration reconciliation

## Lanes

- **A1 Native today**: lands on a native Snowflake object (database, schema, table, view, column, tag).
- **A2 Native roadmap**: lives in a governed table now and moves to a native feature later.
- **B1 Governed table**: stays in a governed table in Snowflake.
- **Retire**: kept for audit only. Not shown to users.
- **Open**: decision not made yet.

## Steps

1. Use `catalog_analyst` for the conversion plan: asset type, decision, lane, Snowflake home, bronze count,
   gold count and the difference.
2. For "did everything migrate", report total bronze, total gold and the difference. If the difference is
   zero, say "All <n> Collibra assets reconcile to gold." If not, list each asset type that does not match.
3. For "what is being retired", list asset types in the Retire lane and the attributes marked out of scope,
   with how many values each holds.
4. For one asset type, give its lane, its Snowflake home and its counts in one line.

## Answer format

- Lead with the reconciliation result in one sentence.
- Then a table grouped by lane: Asset type | Snowflake home | Bronze | Gold.
- List Open items last, labelled "Decision pending".

## Rules

- Retired does not mean deleted. Retired values stay in gold for audit.
- Do not describe a roadmap feature as available today.
- Counts come only from `catalog_analyst`. Never estimate.
