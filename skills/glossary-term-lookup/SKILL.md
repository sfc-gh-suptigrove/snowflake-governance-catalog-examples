---
name: glossary-term-lookup
description: Explain what a business term means and where it lives in Snowflake. Use when the user asks what a term, acronym or CDE means, which columns or tables use it, or whether it is a critical data element.
---

<!-- Boilerplate example skill. Fine-tune the steps and rules to your governance process. -->

# Glossary term lookup

## Steps

1. **Resolve the exact term name.** If the user's wording is loose, misspelled, plural, or an acronym, call
   `catalog_search` filtered to `ASSET_TYPE = 'Business Term'` (or `'Acronym'`) and take the closest names.
   If nothing scores close, say so and list up to three nearby terms. Do not guess.
2. **Get every definition.** Ask `catalog_analyst` for the term's domain, definition, status, CDE flag and
   linked column count. Term names are not unique: if more than one row comes back, show every row with its
   domain. Do not merge or pick one.
3. **Get the physical columns.** Ask `catalog_analyst` which columns the term represents (column path and
   domain). If there are more than 15, show the first 15 and give the total.
4. **Name who is accountable.** Ask `catalog_analyst` for the effective accountability of the term's domain
   (this already includes owners inherited from the community). Give the Data Steward if there is one;
   otherwise give the inherited Data Owner and say it is inherited from the community.

## Answer format

- One sentence with the definition, or one per domain when there are several.
- Then a short table: Domain | Status | CDE | Linked columns.
- Then the column paths.
- End with: "Accountable: <name> (<role>, <email>)". Always include this line; do not offer to look it up later.
- If status is not Approved, add: "This definition is still <status> and may change."

## Rules

- Quote definitions exactly as stored. Do not paraphrase a definition into something it does not say.
- A term with zero linked columns that is a CDE is a governance gap; call it out in one line.
- Never invent a definition, a column or a steward.
