-- BOILERPLATE EXAMPLE CODE. Adapt to your schema and governance requirements before use.
-- All database identifiers, domain names and sample values are illustrative.
-- The prerequisite bronze and gold layers are not included in this package.
-- =====================================================================
-- Collibra -> Snowflake starter kit | 02 CORTEX SEARCH + CORTEX AGENT
-- Search: find an asset by meaning or a partial name ("what does X mean",
--         "the analytics tables"). Agent: routes counts / lists / joins
--         to the semantic view and meaning lookups to search, and loads a
--         skill for the four repeatable workflows. Users reach the agent in
--         Snowflake Intelligence (CoWork); Cortex Code and the catalog app
--         can call it too.
--
-- Agent design patterns illustrated:
--   * instructions.orchestration: short routing rules only. It is re-sent on every
--     turn, so deep workflow rules live in skills, which load only when needed.
--   * skills: glossary-term-lookup, stewardship-and-access, vendor-risk-review,
--     migration-reconciliation. Editing a staged SKILL.md updates the agent
--     immediately; no agent redeploy needed.
--   * The analyst tool has an explicit warehouse (without it every run fails, error 391920).
--   * Search tool: columns_and_descriptions tells the agent what each returned
--     column means; filters by ASSET_TYPE / DOMAIN_NAME.
--   * budget caps time and tokens per question.
--
-- Run from this project folder (PUT uses relative paths).
-- Replace CATALOG_DEMO and COMPUTE_WH with your database and warehouse.
-- =====================================================================
USE SCHEMA CATALOG_DEMO.GOVERNED_DG;

-- One searchable document per asset. Columns are included only when they carry a curated description,
-- and auto-generated DQ rules are left out, so search returns things people actually look for.
CREATE OR REPLACE VIEW CATALOG_SEARCH_DOCS COMMENT = 'Documents indexed by CATALOG_SEARCH.' AS
SELECT a.ASSET_ID, a.ASSET_NAME, a.ASSET_TYPE, a.DOMAIN_NAME, a.COMMUNITY_NAME, a.STATUS, a.FULL_NAME,
       a.ASSET_TYPE || ': ' || a.ASSET_NAME
         || ' | Domain: ' || a.DOMAIN_NAME || ' (' || a.COMMUNITY_NAME || ')'
         || IFF(a.FULL_NAME <> a.ASSET_NAME, ' | Path: ' || a.FULL_NAME, '')
         || COALESCE(' | Definition: ' || a.DEFINITION, '')
         || COALESCE(' | Description: ' || a.DESCRIPTION, '')
         || COALESCE(' | Acronyms: ' || bt.ACRONYMS, '')
         || COALESCE(' | Synonyms: ' || bt.SYNONYMS, '') AS DOC_TEXT
FROM ASSET a
LEFT JOIN BUSINESS_TERM bt ON bt.TERM_ID = a.ASSET_ID
WHERE a.ASSET_TYPE NOT IN ('Data Quality Rule')
  AND (a.ASSET_TYPE <> 'Column' OR a.DESCRIPTION IS NOT NULL);

CREATE OR REPLACE CORTEX SEARCH SERVICE CATALOG_SEARCH
  ON DOC_TEXT
  ATTRIBUTES ASSET_TYPE, DOMAIN_NAME, COMMUNITY_NAME, STATUS
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Search the migrated Collibra catalog by meaning or partial name.'
  AS SELECT ASSET_ID, ASSET_NAME, ASSET_TYPE, DOMAIN_NAME, COMMUNITY_NAME, STATUS, FULL_NAME, DOC_TEXT
     FROM CATALOG_SEARCH_DOCS;

-- ---------- Agent skills (lazy-loaded workflow instructions) ----------
CREATE STAGE IF NOT EXISTS AGENT_SKILLS
  DIRECTORY = (ENABLE = TRUE)
  COMMENT = 'SKILL.md files for DATA_CATALOG_AGENT. One folder per skill.';
PUT file://skills/glossary-term-lookup/SKILL.md     @AGENT_SKILLS/skills/glossary-term-lookup     AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
PUT file://skills/stewardship-and-access/SKILL.md   @AGENT_SKILLS/skills/stewardship-and-access   AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
PUT file://skills/vendor-risk-review/SKILL.md       @AGENT_SKILLS/skills/vendor-risk-review       AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
PUT file://skills/migration-reconciliation/SKILL.md @AGENT_SKILLS/skills/migration-reconciliation AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
ALTER STAGE AGENT_SKILLS REFRESH;

CREATE OR REPLACE AGENT DATA_CATALOG_AGENT
  COMMENT = 'Example data catalog assistant over the metadata migrated from Collibra: what assets exist and where they live in Snowflake, what business terms mean, who owns or stewards them, vendor / application / system risk, and the conversion plan. Catalog metadata only; it does not read business data.'
  PROFILE = '{"display_name": "Data Catalog Assistant"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
orchestration:
  budget:
    seconds: 120
    tokens: 60000
instructions:
  orchestration: >
    You answer questions about a data catalog, which was migrated from Collibra.
    Tools: use catalog_analyst for anything that needs counts, lists, filters or joins (assets by community,
    domain, type or status; business terms, CDEs and the columns they represent; owners and stewards;
    applications, systems and vendors and their risk; policies and standards; the conversion plan and
    reconciliation). Use catalog_search first when the user gives a loose, partial, misspelled or descriptive
    name, or asks what something means; then pass the exact name to catalog_analyst. Use data_to_chart only when
    the user asks for a chart or the answer is a comparison across more than five groups.
    Skills: load glossary-term-lookup for term meaning and usage, stewardship-and-access for who-owns and access
    questions, vendor-risk-review for vendor, AI or PII risk, and migration-reconciliation for where an asset type
    lands and whether the migration is complete. Follow the loaded skill's steps.
    Scope: catalog metadata only. If asked for values inside a catalogued table, explain that the catalog shows
    where the data lives and who owns it, and name the steward. You cannot change the catalog, grant access or
    change status; say who can.
  response: >
    Lead with the answer in one or two sentences, then a short table when there are several rows. Use names,
    never internal IDs. Show at most 15 rows and give the total when there are more. Every total or count you
    state must come from a query result; never add up rows yourself. If you need a total, ask catalog_analyst for
    it. Quote definitions exactly as stored. When the answer is about access or a change, name the responsible person. If nothing matches, say so
    plainly and offer up to three close matches from search; never invent an asset, definition, person or number.
    State any assumption you made (for example which of two same-named terms you used) in one line.
  sample_questions:
    - question: "What is in the Analytics Mart domain, and what is still Candidate?"
    - question: "What does Surrender Charge mean and which columns use it?"
    - question: "Which vendors with High AI risk provide the most applications?"
    - question: "Who do I ask for access to the Analytics Mart data?"
    - question: "Did every Collibra asset make it into Snowflake?"
    - question: "Which critical data elements are not linked to any column?"
skills:
  - name: glossary-term-lookup
    source:
      type: STAGE
      path: "@CATALOG_DEMO.GOVERNED_DG.AGENT_SKILLS/skills/glossary-term-lookup"
  - name: stewardship-and-access
    source:
      type: STAGE
      path: "@CATALOG_DEMO.GOVERNED_DG.AGENT_SKILLS/skills/stewardship-and-access"
  - name: vendor-risk-review
    source:
      type: STAGE
      path: "@CATALOG_DEMO.GOVERNED_DG.AGENT_SKILLS/skills/vendor-risk-review"
  - name: migration-reconciliation
    source:
      type: STAGE
      path: "@CATALOG_DEMO.GOVERNED_DG.AGENT_SKILLS/skills/migration-reconciliation"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: catalog_analyst
      description: >
        Governed catalog migrated from Collibra. Returns exact counts and lists over: assets (name, type, community,
        domain, status, Snowflake database / schema / object), attributes, relationships between assets, effective
        accountability per domain (stewards plus owners inherited from the community), the business glossary with CDE flags and term-to-column links, application / system /
        vendor inventory with risk, PII and DR tier, policies and standards, and the Collibra conversion plan with
        bronze vs gold reconciliation. Use for any question that needs a number, a list, a filter or a join.
  - tool_spec:
      type: cortex_search
      name: catalog_search
      description: >
        Meaning and fuzzy-name search over asset names, paths, definitions, descriptions, acronyms and synonyms.
        Use to explain what something means or to find the exact stored name of something described loosely.
        Filter by ASSET_TYPE (for example Business Term, Acronym, Vendor, Application, System, Table) or DOMAIN_NAME
        when the user names one. Does not count; use catalog_analyst for counts.
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: Charts a result set when the user asks for a chart or a comparison across many groups.
tool_resources:
  catalog_analyst:
    semantic_view: CATALOG_DEMO.GOVERNED_DG.SV_DATA_CATALOG
    execution_environment:
      type: warehouse
      warehouse: COMPUTE_WH
      query_timeout: 120
  catalog_search:
    search_service: CATALOG_DEMO.GOVERNED_DG.CATALOG_SEARCH
    max_results: 8
    title_column: ASSET_NAME
    id_column: ASSET_ID
    columns_and_descriptions:
      ASSET_NAME:
        description: "Display name of the asset."
        type: string
        searchable: true
        filterable: false
      ASSET_TYPE:
        description: "Collibra asset type, e.g. Business Term, Acronym, Table, Column, Vendor, Application, System."
        type: string
        searchable: false
        filterable: true
      DOMAIN_NAME:
        description: "Collibra domain the asset belongs to."
        type: string
        searchable: false
        filterable: true
      COMMUNITY_NAME:
        description: "Collibra community that contains the domain."
        type: string
        searchable: false
        filterable: true
      STATUS:
        description: "Workflow status: Candidate, In Progress, Under Review or Approved."
        type: string
        searchable: false
        filterable: true
      FULL_NAME:
        description: "Full path; for physical assets DATABASE.SCHEMA.OBJECT[.COLUMN]."
        type: string
        searchable: true
        filterable: false
      DOC_TEXT:
        description: "Indexed text: type, name, domain, path, definition, description, acronyms and synonyms."
        type: string
        searchable: true
        filterable: false
$$;
