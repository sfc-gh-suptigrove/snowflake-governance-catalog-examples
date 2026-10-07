-- BOILERPLATE EXAMPLE CODE. Adapt to your schema and governance requirements before use.
-- All database identifiers, domain names and sample values are illustrative.
-- The prerequisite bronze and gold layers are not included in this package.
-- =====================================================================
-- Collibra -> Snowflake starter kit | 01 SEMANTIC VIEW
-- One semantic view over the gold layer. Cortex Analyst, the Cortex Agent
-- (Snowflake Intelligence / CoWork) and Cortex Code all use it, so a
-- question asked any of those ways gets the same governed answer.
--
-- Patterns illustrated by this template:
--   * Every table, dimension, fact and metric has a business description.
--   * Ownership inheritance (community -> domain) is resolved in a view, not a prompt.
--   * Low-cardinality columns carry SAMPLE_VALUES; closed lists are IS_ENUM.
--   * High-cardinality names (terms, vendors, applications, systems, domains)
--     are matched through a Cortex Search literal service, so "surrender charges"
--     or "acme" still resolve to the exact stored value.
--   * Named filters (LABELS = (FILTER)) for the conditions people ask about most.
--   * Synonyms for governance / Collibra vocabulary (CDE, NPPI, RTO, DR tier), per
--     current Snowflake guidance; generic synonyms were removed.
--   * AI_SQL_GENERATION holds only logic not already in a description.
--   * AI_QUESTION_CATEGORIZATION keeps the view to catalog metadata.
--   * 15 example verified queries. Validate them after adapting the template.
--     In verified-query SQL, __table.col resolves to the LOGICAL
--     name (t.term_domain, not t.domain_name).
--
-- Replace CATALOG_DEMO with your target database and COMPUTE_WH with your warehouse.
-- =====================================================================
USE SCHEMA CATALOG_DEMO.GOVERNED_DG;

CREATE OR REPLACE VIEW RECON_RELATIONSHIP_COUNTS COMMENT = 'Bronze vs gold relation counts per relation type (gold collapses duplicate pairs).' AS
SELECT b.SOURCE_TYPE, b.ROLE, b.TARGET_TYPE, b.BRONZE_COUNT, COALESCE(g.GOLD_COUNT, 0) AS GOLD_COUNT
FROM (SELECT SOURCE_TYPE, ROLE, TARGET_TYPE, COUNT(*) AS BRONZE_COUNT FROM CATALOG_DEMO.BRONZE_DG.DG_ASSET_RELATION GROUP BY ALL) b
LEFT JOIN (SELECT SOURCE_TYPE, ROLE, TARGET_TYPE, COUNT(*) AS GOLD_COUNT FROM ASSET_RELATIONSHIP GROUP BY ALL) g
  USING (SOURCE_TYPE, ROLE, TARGET_TYPE);

-- Accountability with inheritance resolved: one row per domain per responsible person. Community-level
-- owners apply to every domain in the community. Modelling this here (not in a prompt) makes "who owns X"
-- consistent across requests without relying on the model to infer inheritance.
CREATE OR REPLACE VIEW EFFECTIVE_RESPONSIBILITY COMMENT = 'Who is accountable for each domain, including owners inherited from the community.' AS
SELECT d.DOMAIN_ID, d.DOMAIN_NAME, d.COMMUNITY_NAME, r.ROLE_NAME, r.USER_NAME, r.EMAIL,
       r.RESOURCE_LEVEL AS ASSIGNED_AT, r.RESOURCE_LEVEL = 'Community' AS IS_INHERITED
FROM DOMAIN d
JOIN ASSET_RESPONSIBILITY r
  ON (r.RESOURCE_LEVEL = 'Domain' AND r.RESOURCE_ID = d.DOMAIN_ID)
  OR (r.RESOURCE_LEVEL = 'Community' AND r.RESOURCE_ID = d.COMMUNITY_ID);

-- ---------- Literal search: exact stored names for fuzzy user wording ----------
-- One small service over the names people type. Analyst uses it to pick the right
-- literal for a WHERE clause; it is not the meaning search used by the agent.
CREATE OR REPLACE VIEW CATALOG_NAME_LITERALS COMMENT = 'Distinct business-facing names, indexed by CATALOG_NAME_SEARCH for literal matching.' AS
SELECT DISTINCT NAME, NAME_TYPE FROM (
  SELECT TERM AS NAME, 'Business Term' AS NAME_TYPE FROM BUSINESS_TERM
  UNION ALL SELECT VENDOR, 'Vendor' FROM VENDOR
  UNION ALL SELECT APPLICATION, 'Application' FROM APPLICATION
  UNION ALL SELECT SYSTEM, 'System' FROM SYSTEM
  UNION ALL SELECT DOMAIN_NAME, 'Domain' FROM DOMAIN)
WHERE NAME IS NOT NULL;

CREATE OR REPLACE CORTEX SEARCH SERVICE CATALOG_NAME_SEARCH
  ON NAME
  ATTRIBUTES NAME_TYPE
  WAREHOUSE = COMPUTE_WH
  TARGET_LAG = '1 day'
  COMMENT = 'Literal matching for semantic view dimensions (terms, vendors, applications, systems, domains).'
  AS SELECT NAME, NAME_TYPE FROM CATALOG_NAME_LITERALS;

CREATE OR REPLACE SEMANTIC VIEW SV_DATA_CATALOG
  TABLES (
    assets AS CATALOG_DEMO.GOVERNED_DG.ASSET PRIMARY KEY (ASSET_ID)
      WITH SYNONYMS = ('Collibra assets')
      COMMENT = 'One row per catalog asset: every asset migrated from Collibra plus assets created in the catalog app after cutover. Covers physical objects (databases, schemas, tables, views, columns) and logical ones (business terms, systems, applications, vendors, policies, standards). Physical assets carry their parsed Snowflake path.',
    attributes AS CATALOG_DEMO.GOVERNED_DG.ASSET_ATTRIBUTE
      COMMENT = 'Every attribute value on every asset in long form (one row per asset, attribute type and value). Use it for attributes that are not already a dimension elsewhere, and for questions about retired attributes.',
    relationships AS CATALOG_DEMO.GOVERNED_DG.ASSET_RELATIONSHIP
      COMMENT = 'Every relation between two assets, normalised to read SOURCE --role--> TARGET and de-duplicated. Includes containment (column is part of table) and business links (term represents column, vendor provides application).',
    responsibilities AS CATALOG_DEMO.GOVERNED_DG.ASSET_RESPONSIBILITY PRIMARY KEY (RESPONSIBILITY_ID)
      WITH SYNONYMS = ('stewardship', 'ownership')
      COMMENT = 'Who is accountable for what: Data Owners, Data Stewards and Technical Owners/Custodians assigned at community, domain or asset level. Use for any who-owns / who-stewards / who-do-I-ask question.',
    accountability AS CATALOG_DEMO.GOVERNED_DG.EFFECTIVE_RESPONSIBILITY
      WITH SYNONYMS = ('who to contact', 'access approver')
      COMMENT = 'Effective accountability per domain: the domain''s own stewards plus the Data Owner and Technical Owner inherited from its community. Use this, not responsibilities, to answer who owns, stewards or approves access to a domain or to anything inside it.',
    terms AS CATALOG_DEMO.GOVERNED_DG.BUSINESS_TERM PRIMARY KEY (TERM_ID)
      WITH SYNONYMS = ('business glossary', 'glossary')
      COMMENT = 'Business glossary: one row per business term with its definition, status, Critical Data Element flag, acronyms, synonyms and the number of physical columns it represents. The same term name can exist in more than one domain.',
    term_columns AS CATALOG_DEMO.GOVERNED_DG.TERM_COLUMN PRIMARY KEY (TERM_ID, COLUMN_ID)
      COMMENT = 'Bridge from a business term to each physical Snowflake column it represents, read in both Collibra relation directions. One row per term-column pair.',
    applications AS CATALOG_DEMO.GOVERNED_DG.APPLICATION PRIMARY KEY (APPLICATION_ID)
      COMMENT = 'Application inventory fed by the the disaster-recovery inventory system: hosting platform, recovery time objective, risk level and DR tier for each application.',
    systems AS CATALOG_DEMO.GOVERNED_DG.SYSTEM PRIMARY KEY (SYSTEM_ID)
      WITH SYNONYMS = ('system inventory', 'source systems')
      COMMENT = 'System inventory: commercial or internally built software that holds or moves data (not Snowflake objects), with owners and whether the system handles PII / NPPI.',
    vendors AS CATALOG_DEMO.GOVERNED_DG.VENDOR PRIMARY KEY (VENDOR_ID)
      WITH SYNONYMS = ('third parties', 'suppliers')
      COMMENT = 'Third-party vendors fed by Vendor Management: status, vendor risk, AI risk, service model and whether the vendor handles PII / NPPI.',
    vendor_apps AS CATALOG_DEMO.GOVERNED_DG.VENDOR_APPLICATION PRIMARY KEY (VENDOR_ID, APPLICATION_ID)
      COMMENT = 'Bridge: which vendor provides which application. One row per vendor-application pair.',
    system_apps AS CATALOG_DEMO.GOVERNED_DG.SYSTEM_APPLICATION PRIMARY KEY (SYSTEM_ID, APPLICATION_ID)
      COMMENT = 'Bridge: which system utilizes (or targets data from) which application. One row per system-application pair.',
    policy_standards AS CATALOG_DEMO.GOVERNED_DG.POLICY_STANDARD PRIMARY KEY (STANDARD_ID)
      COMMENT = 'Data standards and the governance policy each standard is included in (for example Data Retention Policy, Privacy (GLBA/CCPA) Policy).',
    migration AS CATALOG_DEMO.GOVERNED_DG.RECON_ASSET_COUNTS PRIMARY KEY (ASSET_TYPE)
      WITH SYNONYMS = ('migration status', 'conversion plan')
      COMMENT = 'Collibra-to-Snowflake conversion plan: one row per Collibra asset type with its decision (native now, native roadmap, governed table, retire), lane, Snowflake landing spot, and bronze vs gold counts that prove nothing was lost.'
  )
  RELATIONSHIPS (
    attributes_to_assets    AS attributes (ASSET_ID)          REFERENCES assets,
    relationships_to_assets AS relationships (SOURCE_ASSET_ID) REFERENCES assets,
    terms_to_assets         AS terms (TERM_ID)                REFERENCES assets,
    term_columns_to_terms   AS term_columns (TERM_ID)         REFERENCES terms,
    vendor_apps_to_vendors  AS vendor_apps (VENDOR_ID)        REFERENCES vendors,
    vendor_apps_to_apps     AS vendor_apps (APPLICATION_ID)   REFERENCES applications,
    system_apps_to_systems  AS system_apps (SYSTEM_ID)        REFERENCES systems,
    system_apps_to_apps     AS system_apps (APPLICATION_ID)   REFERENCES applications
  )
  FACTS (
    terms.linked_columns_fact AS LINKED_COLUMNS
      COMMENT = 'Number of physical columns this business term represents. Zero means the term is not yet linked to any column.',
    migration.bronze_count_fact AS BRONZE_COUNT
      COMMENT = 'Assets of this type in the raw Collibra extract (bronze).',
    migration.gold_count_fact AS GOLD_COUNT
      COMMENT = 'Assets of this type in the governed gold layer. Equal to bronze when the migration is complete for the type.'
  )
  DIMENSIONS (
    -- assets
    assets.asset_name AS ASSET_NAME
      COMMENT = 'Display name of the asset as shown in the catalog, e.g. a table, column, term or system name.',
    assets.asset_full_name AS FULL_NAME
      WITH SYNONYMS = ('fully qualified name')
      COMMENT = 'Full Collibra name. For physical assets this is the Snowflake path DATABASE.SCHEMA.OBJECT[.COLUMN].',
    assets.asset_type AS ASSET_TYPE
      COMMENT = 'Collibra asset type. Column and Data Quality Rule make up most rows; Business Term, Table, Application, Vendor and System are the types people usually ask about.'
      SAMPLE_VALUES ('Column', 'Table', 'Database View', 'Schema', 'Database', 'Business Term', 'Acronym', 'Abbreviation', 'Application', 'System', 'Vendor', 'Policy', 'Standard', 'Data Quality Rule', 'Department', 'Data Category', 'Code Set', 'Code Value')
      IS_ENUM,
    assets.domain_name AS DOMAIN_NAME
      COMMENT = 'Collibra domain the asset belongs to (second level of the catalog tree), e.g. Analytics Mart, Applications, Operations Data.'
      WITH CORTEX SEARCH SERVICE CATALOG_DEMO.GOVERNED_DG.CATALOG_NAME_SEARCH USING NAME,
    assets.community_name AS COMMUNITY_NAME
      COMMENT = 'Collibra community (top level of the catalog tree) that contains the domain.'
      SAMPLE_VALUES ('Data Dictionaries', 'Data Quality', 'Data Lake', 'Analytics', 'Business Community', 'Snowflake Presentation Layer', 'Technology Community', 'Governance Community', 'Reference Data', 'Catalog Metadata')
      IS_ENUM,
    assets.status AS STATUS
      COMMENT = 'Workflow status of the asset after any status change made in the catalog app.'
      SAMPLE_VALUES ('Candidate', 'In Progress', 'Under Review', 'Approved')
      IS_ENUM,
    assets.asset_description AS DESCRIPTION
      COMMENT = 'Curated free-text description of the asset. Empty for most columns.',
    assets.asset_definition AS DEFINITION
      COMMENT = 'Formal definition; populated mainly for business terms, acronyms and abbreviations.',
    assets.origin AS ORIGIN
      COMMENT = 'Where the asset came from: migrated from Collibra, or created in the catalog app after migration.'
      SAMPLE_VALUES ('Collibra', 'Catalog app')
      IS_ENUM,
    assets.solution_type AS SOLUTION_TYPE
      COMMENT = 'Conversion decision for the asset type: native Snowflake feature now, native on the roadmap (governed table in the interim), governed table, or retire.'
      SAMPLE_VALUES ('Native - now', 'Native - roadmap (interim: governed table)', 'Governed table (custom)', 'Retire')
      IS_ENUM,
    assets.sf_database AS SF_DATABASE
      COMMENT = 'Snowflake database of a physical asset, parsed from FULL_NAME. Empty for logical assets.',
    assets.sf_schema AS SF_SCHEMA
      COMMENT = 'Snowflake schema of a physical asset, parsed from FULL_NAME. Empty for databases and logical assets.',
    assets.sf_object AS SF_OBJECT
      COMMENT = 'Snowflake table or view name of a table, view or column asset, parsed from FULL_NAME.',
    assets.created_on AS CREATED_ON
      COMMENT = 'When the asset was created in Collibra or in the catalog app.',
    assets.modified_on AS MODIFIED_ON
      COMMENT = 'Last time the asset or its status changed, in Collibra or in the catalog app.',
    assets.is_physical_asset LABELS = (FILTER) AS ASSET_TYPE IN ('Database', 'Schema', 'Table', 'Database View', 'Column')
      COMMENT = 'Filter: TRUE for Snowflake objects (database, schema, table, view, column); FALSE for glossary, inventory and policy assets.',
    assets.is_not_approved LABELS = (FILTER) AS STATUS <> 'Approved'
      COMMENT = 'Filter: TRUE for assets still in Candidate, In Progress or Under Review, i.e. open stewardship work.',
    -- attributes
    attributes.attribute_asset_type AS ASSET_TYPE
      COMMENT = 'Asset type of the asset that carries the attribute.',
    attributes.attribute_type AS ATTRIBUTE_TYPE
      COMMENT = 'Name of the Collibra attribute, e.g. Description, Definition, Technical Data Type, Source Tags, Popularity Score.',
    attributes.attribute_value AS ATTRIBUTE_VALUE
      COMMENT = 'The attribute value as text.',
    attributes.in_scope AS IN_SCOPE
      COMMENT = 'FALSE when the conversion plan retires this attribute; retired values are kept for audit only.',
    -- relationships
    relationships.source_name AS SOURCE_NAME
      COMMENT = 'Name of the asset on the source side of the relation.',
    relationships.source_type AS SOURCE_TYPE
      COMMENT = 'Asset type on the source side, e.g. Column, Business Term, Vendor, System.',
    relationships.relation_role AS ROLE
      COMMENT = 'Relation verb read source-to-target.'
      SAMPLE_VALUES ('is part of', 'targets', 'represents', 'governs', 'contains', 'provides', 'has acronym', 'utilizes', 'is included in', 'synonym', 'has', 'targets from', 'is source of'),
    relationships.target_name AS TARGET_NAME
      COMMENT = 'Name of the asset on the target side of the relation.',
    relationships.target_type AS TARGET_TYPE
      COMMENT = 'Asset type on the target side, e.g. Table, Column, Application, Policy.',
    relationships.is_containment AS IS_CONTAINMENT
      COMMENT = 'TRUE for structural containment (database has schema, schema contains table, column is part of table); FALSE for business relations.',
    -- responsibilities
    responsibilities.resource_name AS RESOURCE_NAME
      COMMENT = 'Name of the community, domain or asset the person is responsible for.',
    responsibilities.resource_level AS RESOURCE_LEVEL
      COMMENT = 'Level at which the responsibility is assigned.'
      SAMPLE_VALUES ('Community', 'Domain', 'Asset')
      IS_ENUM,
    responsibilities.role_name AS ROLE_NAME
      WITH SYNONYMS = ('custodian')
      COMMENT = 'Responsibility role. Data Owner approves access; Data Steward owns definitions and quality; Technical Owner/Custodian supports the platform.'
      SAMPLE_VALUES ('Data Owner', 'Data Steward', 'Technical Owner/Custodian')
      IS_ENUM,
    responsibilities.user_name AS USER_NAME
      COMMENT = 'Full name of the person holding the responsibility.',
    responsibilities.email AS EMAIL
      COMMENT = 'Email of the person holding the responsibility.',
    responsibilities.resp_community AS COMMUNITY_NAME
      COMMENT = 'Community the responsibility sits in (directly or through its domain).',
    responsibilities.resp_domain AS DOMAIN_NAME
      COMMENT = 'Domain the responsibility applies to. Empty for community-level assignments, which cover every domain in the community.',
    -- accountability
    accountability.acc_domain AS DOMAIN_NAME
      COMMENT = 'Domain the person is accountable for.'
      WITH CORTEX SEARCH SERVICE CATALOG_DEMO.GOVERNED_DG.CATALOG_NAME_SEARCH USING NAME,
    accountability.acc_community AS COMMUNITY_NAME
      COMMENT = 'Community that contains the domain.',
    accountability.acc_role AS ROLE_NAME
      COMMENT = 'Data Owner approves access; Data Steward owns definitions and quality; Technical Owner/Custodian supports the platform.'
      SAMPLE_VALUES ('Data Owner', 'Data Steward', 'Technical Owner/Custodian')
      IS_ENUM,
    accountability.acc_person AS USER_NAME
      COMMENT = 'Person accountable.',
    accountability.acc_email AS EMAIL
      COMMENT = 'Email of the person accountable.',
    accountability.is_inherited AS IS_INHERITED
      COMMENT = 'TRUE when the responsibility is assigned at community level and inherited by the domain.',
    -- terms
    terms.term AS TERM
      COMMENT = 'Business term name. Not unique: the same name can be defined in several domains.'
      WITH CORTEX SEARCH SERVICE CATALOG_DEMO.GOVERNED_DG.CATALOG_NAME_SEARCH USING NAME,
    terms.term_definition AS DEFINITION
      COMMENT = 'Approved business definition of the term.',
    terms.term_status AS STATUS
      COMMENT = 'Workflow status of the term.'
      SAMPLE_VALUES ('Candidate', 'In Progress', 'Under Review', 'Approved')
      IS_ENUM,
    terms.term_domain AS DOMAIN_NAME
      COMMENT = 'Domain the term is defined in; use it to tell apart two terms with the same name.',
    terms.is_cde AS IS_CDE
      WITH SYNONYMS = ('critical data element', 'CDE')
      COMMENT = 'TRUE when the term is flagged as a Critical Data Element.',
    terms.acronyms AS ACRONYMS
      COMMENT = 'Comma-separated acronyms linked to the term.',
    terms.synonyms AS SYNONYMS
      COMMENT = 'Comma-separated business terms recorded as synonyms of this term.',
    terms.is_unlinked_term LABELS = (FILTER) AS LINKED_COLUMNS = 0
      COMMENT = 'Filter: TRUE when the term is not linked to any physical column yet.',
    -- term_columns
    term_columns.column_term AS TERM
      COMMENT = 'Business term name on the term-to-column link.',
    term_columns.column_path AS COLUMN_PATH
      COMMENT = 'Full Snowflake path of the column the term represents: DATABASE.SCHEMA.TABLE.COLUMN.',
    term_columns.column_name AS COLUMN_NAME
      COMMENT = 'Column name only, without its table path.',
    term_columns.column_database AS SF_DATABASE
      COMMENT = 'Snowflake database of the linked column.',
    term_columns.column_schema AS SF_SCHEMA
      COMMENT = 'Snowflake schema of the linked column.',
    term_columns.column_object AS SF_OBJECT
      COMMENT = 'Snowflake table or view that holds the linked column.',
    term_columns.column_domain AS COLUMN_DOMAIN
      COMMENT = 'Collibra domain of the linked column (the data dictionary it was catalogued in).',
    -- applications
    applications.application AS APPLICATION
      COMMENT = 'Application name.'
      WITH CORTEX SEARCH SERVICE CATALOG_DEMO.GOVERNED_DG.CATALOG_NAME_SEARCH USING NAME,
    applications.platform AS PLATFORM
      COMMENT = 'Where the application is hosted.'
      SAMPLE_VALUES ('Azure', 'AWS', 'SaaS', 'On-prem', 'Mainframe'),
    applications.rto AS RTO
      WITH SYNONYMS = ('recovery time objective')
      COMMENT = 'Recovery time objective from the disaster-recovery inventory, stored as text (4 hours, 8 hours, 24 hours, 72 hours, 1 week).'
      SAMPLE_VALUES ('4 hours', '8 hours', '24 hours', '72 hours', '1 week'),
    applications.app_risk_level AS RISK_LEVEL
      COMMENT = 'Application risk level from the disaster-recovery inventory.'
      SAMPLE_VALUES ('High', 'Medium', 'Low', 'Not Assessed')
      IS_ENUM,
    applications.tier_level AS TIER_LEVEL
      WITH SYNONYMS = ('DR tier')
      COMMENT = 'Disaster-recovery tier; Tier 1 is the most critical.'
      SAMPLE_VALUES ('Tier 1', 'Tier 2', 'Tier 3', 'Tier 4')
      IS_ENUM,
    -- systems
    systems.system AS SYSTEM
      COMMENT = 'System name.'
      WITH CORTEX SEARCH SERVICE CATALOG_DEMO.GOVERNED_DG.CATALOG_NAME_SEARCH USING NAME,
    systems.mnemonic AS MNEMONIC
      COMMENT = 'Short code used for the system in the catalog naming conventions.',
    systems.business_owner AS BUSINESS_OWNER
      COMMENT = 'Business owner of the system, as recorded in the system inventory.',
    systems.technical_owner AS TECHNICAL_OWNER
      COMMENT = 'Technical owner of the system, as recorded in the system inventory.',
    systems.system_pii AS HANDLES_PII_NPPI
      WITH SYNONYMS = ('NPPI')
      COMMENT = 'Whether the system handles personally identifiable or non-public personal information.'
      SAMPLE_VALUES ('Yes', 'No', 'Unknown')
      IS_ENUM,
    -- vendors
    vendors.vendor AS VENDOR
      COMMENT = 'Vendor name.'
      WITH CORTEX SEARCH SERVICE CATALOG_DEMO.GOVERNED_DG.CATALOG_NAME_SEARCH USING NAME,
    vendors.vendor_status AS VENDOR_STATUS
      COMMENT = 'Relationship status with the vendor.'
      SAMPLE_VALUES ('Active', 'Inactive', 'Onboarding')
      IS_ENUM,
    vendors.vendor_risk_level AS VENDOR_RISK_LEVEL
      COMMENT = 'Overall third-party risk rating from Vendor Management.'
      SAMPLE_VALUES ('High', 'Medium', 'Low', 'Not Assessed')
      IS_ENUM,
    vendors.ai_risk_level AS AI_RISK_LEVEL
      COMMENT = 'Risk rating for the vendor''s use of AI, from Vendor Management.'
      SAMPLE_VALUES ('High', 'Medium', 'Low', 'Not Assessed')
      IS_ENUM,
    vendors.service_model AS SERVICE_MODEL
      COMMENT = 'How the vendor delivers its service.'
      SAMPLE_VALUES ('Managed Service', 'SaaS', 'PaaS', 'IaaS', 'On-prem License'),
    vendors.vendor_pii AS HANDLES_PII_NPPI
      COMMENT = 'Whether the vendor handles personally identifiable or non-public personal information.'
      SAMPLE_VALUES ('Yes', 'No', 'Unknown')
      IS_ENUM,
    vendors.is_high_risk_vendor LABELS = (FILTER) AS VENDOR_RISK_LEVEL = 'High' OR AI_RISK_LEVEL = 'High'
      COMMENT = 'Filter: TRUE when either the vendor risk or the AI risk is High.',
    -- policies and standards
    policy_standards.policy AS POLICY
      COMMENT = 'Governance policy that includes the standard.',
    policy_standards.standard AS STANDARD
      COMMENT = 'Data standard name.',
    policy_standards.standard_description AS STANDARD_DESCRIPTION
      COMMENT = 'What the standard requires.',
    -- migration plan
    migration.migrated_asset_type AS ASSET_TYPE
      COMMENT = 'Collibra asset type the conversion decision applies to.',
    migration.migration_solution AS SOLUTION_TYPE
      COMMENT = 'Conversion decision for the asset type.'
      SAMPLE_VALUES ('Native - now', 'Native - roadmap (interim: governed table)', 'Governed table (custom)', 'Retire')
      IS_ENUM,
    migration.lane AS LANE
      COMMENT = 'Delivery lane: A1 native today, A2 native on the roadmap, B1 governed table, Retire, or Open (decision pending).'
      SAMPLE_VALUES ('A1 Native today', 'A2 Native roadmap', 'B1 Governed table', 'Retire', 'Open')
      IS_ENUM,
    migration.snowflake_home AS SNOWFLAKE_HOME
      WITH SYNONYMS = ('landing spot')
      COMMENT = 'Where the asset type lives in Snowflake after conversion, e.g. Table (Horizon Catalog), BUSINESS_TERM view, Tag with allowed values.'
  )
  METRICS (
    assets.asset_count AS COUNT(assets.ASSET_ID)
      COMMENT = 'Number of catalog assets.',
    assets.approved_asset_count AS COUNT_IF(assets.STATUS = 'Approved')
      COMMENT = 'Number of assets in Approved status.',
    assets.approval_rate AS DIV0(COUNT_IF(assets.STATUS = 'Approved'), COUNT(assets.ASSET_ID))
      COMMENT = 'Share of assets that are Approved, from 0 to 1. Use for "how complete is the review of domain X".',
    attributes.attribute_value_count AS COUNT(attributes.ATTRIBUTE_VALUE)
      COMMENT = 'Number of attribute values.',
    relationships.relationship_count AS COUNT(relationships.SOURCE_ASSET_ID)
      COMMENT = 'Number of relations between assets.',
    responsibilities.assignment_count AS COUNT(responsibilities.RESPONSIBILITY_ID)
      COMMENT = 'Number of owner, steward or custodian assignments.',
    responsibilities.people_count AS COUNT(DISTINCT responsibilities.USER_NAME)
      COMMENT = 'Number of distinct people holding a responsibility.',
    accountability.accountable_people AS COUNT(DISTINCT accountability.USER_NAME)
      COMMENT = 'Number of distinct people accountable for a domain, including inherited owners.',
    terms.term_count AS COUNT(terms.TERM_ID)
      COMMENT = 'Number of business terms.',
    terms.cde_count AS COUNT_IF(terms.IS_CDE)
      COMMENT = 'Number of business terms flagged as Critical Data Elements.',
    terms.unlinked_cde_count AS COUNT_IF(terms.IS_CDE AND terms.LINKED_COLUMNS = 0)
      COMMENT = 'Critical Data Elements not yet linked to any physical column: a governance gap.',
    term_columns.linked_column_count AS COUNT(DISTINCT term_columns.COLUMN_ID)
      COMMENT = 'Number of distinct physical columns linked to business terms.',
    applications.application_count AS COUNT(applications.APPLICATION_ID)
      COMMENT = 'Number of applications.',
    systems.system_count AS COUNT(systems.SYSTEM_ID)
      COMMENT = 'Number of systems.',
    systems.pii_system_count AS COUNT_IF(systems.HANDLES_PII_NPPI = 'Yes')
      COMMENT = 'Number of systems that handle PII / NPPI.',
    vendors.vendor_count AS COUNT(vendors.VENDOR_ID)
      COMMENT = 'Number of vendors.',
    vendors.high_risk_vendor_count AS COUNT_IF(vendors.VENDOR_RISK_LEVEL = 'High' OR vendors.AI_RISK_LEVEL = 'High')
      COMMENT = 'Number of vendors whose vendor risk or AI risk is High.',
    vendor_apps.vendor_application_links AS COUNT(vendor_apps.APPLICATION_ID)
      COMMENT = 'Number of vendor-provides-application links. Group by vendor for applications per vendor.',
    policy_standards.standard_count AS COUNT(policy_standards.STANDARD_ID)
      COMMENT = 'Number of data standards.',
    migration.total_bronze_assets AS SUM(migration.BRONZE_COUNT)
      COMMENT = 'Total assets in the raw Collibra extract.',
    migration.total_gold_assets AS SUM(migration.GOLD_COUNT)
      COMMENT = 'Total assets in the governed gold layer.',
    migration.unreconciled_asset_count AS SUM(migration.BRONZE_COUNT - migration.GOLD_COUNT)
      COMMENT = 'Bronze minus gold. Zero means every Collibra asset arrived in gold.'
  )
  COMMENT = 'Example data catalog migrated from Collibra to Snowflake: assets and their Snowflake paths, attributes, relationships, owners and stewards, business glossary with term-to-column links and CDEs, application / system / vendor inventory, policies and standards, and the conversion plan with reconciliation counts. Catalog metadata only; it does not contain the business data inside the catalogued tables.'
  AI_SQL_GENERATION 'Return names, never internal IDs. A vendor reaches a system only through an application (vendor -> vendor_apps -> application <- system_apps <- system). For applications per vendor, group by vendor only. When a business term name matches more than one row, return every match with its domain and definition rather than picking one. Exclude attributes where IN_SCOPE is FALSE unless the user asks about retired attributes. For who owns, stewards or approves access to a domain, or to a term or asset in a domain, use accountability filtered by the domain. Count columns with COUNT(DISTINCT) when joining through term_columns. Order lists by the main count descending and limit lists to 50 rows unless the user asks for all.'
  AI_QUESTION_CATEGORIZATION 'This view describes catalog metadata only. If the user asks for business data values held inside a catalogued table (for example a policy holder''s contract value or a sales total), explain that the catalog shows where that data lives and who owns it, not the values themselves. If a business term, vendor, application or system name is too vague to match, ask which one they mean. Treat questions about access approval as questions about the Data Owner.'
  AI_VERIFIED_QUERIES (
    apps_per_vendor AS (
      QUESTION 'How many applications does each vendor provide?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT v.vendor, COUNT(DISTINCT va.application_id) AS application_count FROM __vendors AS v JOIN __vendor_apps AS va ON va.vendor_id = v.vendor_id GROUP BY v.vendor ORDER BY application_count DESC LIMIT 50'
    ),
    domain_counts AS (
      QUESTION 'How many assets are in each domain?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT a.community_name, a.domain_name, COUNT(a.asset_id) AS asset_count FROM __assets AS a GROUP BY a.community_name, a.domain_name ORDER BY asset_count DESC LIMIT 50'
    ),
    term_columns_for_term AS (
      QUESTION 'Which columns does the business term Contract Value represent?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT tc.column_term, tc.column_path, tc.column_domain FROM __term_columns AS tc WHERE tc.column_term ILIKE ''Contract Value'' ORDER BY tc.column_path'
    ),
    domain_status_breakdown AS (
      QUESTION 'What is in the Analytics Mart domain by asset type and status?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT COALESCE(a.asset_type, ''ALL TYPES'') AS asset_type, COALESCE(a.status, ''ALL STATUSES'') AS status, COUNT(a.asset_id) AS asset_count FROM __assets AS a WHERE a.domain_name = ''Analytics Mart'' GROUP BY ROLLUP (a.asset_type, a.status) ORDER BY GROUPING(a.asset_type), a.asset_type, GROUPING(a.status), asset_count DESC'
    ),
    domain_stewards AS (
      QUESTION 'Who stewards the Analytics Mart domain?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT ac.acc_domain, ac.acc_role, ac.acc_person, ac.acc_email, ac.is_inherited FROM __accountability AS ac WHERE ac.acc_domain = ''Analytics Mart'' ORDER BY ac.is_inherited, ac.acc_role'
    ),
    term_definition_all_domains AS (
      QUESTION 'What does Surrender Charge mean?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT t.term, t.term_domain, t.term_definition, t.term_status, t.is_cde, t.linked_columns_fact FROM __terms AS t WHERE t.term ILIKE ''Surrender Charge'' ORDER BY t.term_domain'
    ),
    cde_coverage_gap AS (
      QUESTION 'Which critical data elements are not linked to any column?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT t.term, t.term_domain, t.term_status FROM __terms AS t WHERE t.is_cde AND t.linked_columns_fact = 0 ORDER BY t.term_domain, t.term LIMIT 50'
    ),
    cde_by_domain AS (
      QUESTION 'How many CDEs are there per domain and how many are linked to columns?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT t.term_domain, COUNT_IF(t.is_cde) AS cde_count, COUNT_IF(t.is_cde AND t.linked_columns_fact > 0) AS linked_cde_count FROM __terms AS t GROUP BY t.term_domain HAVING COUNT_IF(t.is_cde) > 0 ORDER BY cde_count DESC'
    ),
    high_risk_vendor_apps AS (
      QUESTION 'Which vendors with High AI risk provide the most applications?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT v.vendor, v.vendor_risk_level, v.vendor_pii, COUNT(DISTINCT va.application_id) AS application_count FROM __vendors AS v JOIN __vendor_apps AS va ON va.vendor_id = v.vendor_id WHERE v.ai_risk_level = ''High'' GROUP BY v.vendor, v.vendor_risk_level, v.vendor_pii ORDER BY application_count DESC LIMIT 20'
    ),
    pii_vendor_to_system AS (
      QUESTION 'Which systems depend on applications from vendors that handle PII?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT DISTINCT s.system, s.system_pii, ap.application, v.vendor FROM __vendors AS v JOIN __vendor_apps AS va ON va.vendor_id = v.vendor_id JOIN __applications AS ap ON ap.application_id = va.application_id JOIN __system_apps AS sa ON sa.application_id = ap.application_id JOIN __systems AS s ON s.system_id = sa.system_id WHERE v.vendor_pii = ''Yes'' ORDER BY s.system, ap.application'
    ),
    tier1_apps_rto AS (
      QUESTION 'List the Tier 1 applications with their platform and RTO.'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT ap.application, ap.platform, ap.rto, ap.app_risk_level FROM __applications AS ap WHERE ap.tier_level = ''Tier 1'' ORDER BY ap.application'
    ),
    migration_plan AS (
      QUESTION 'Where does each Collibra asset type land in Snowflake, and did everything migrate?'
      ONBOARDING_QUESTION TRUE
      SQL 'SELECT m.migrated_asset_type, m.migration_solution, m.lane, m.snowflake_home, m.bronze_count_fact, m.gold_count_fact, m.bronze_count_fact - m.gold_count_fact AS missing_in_gold FROM __migration AS m ORDER BY m.lane, m.bronze_count_fact DESC'
    ),
    policy_standards_list AS (
      QUESTION 'How many standards does each policy include?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT p.policy, COUNT(p.standard_id) AS standard_count FROM __policy_standards AS p GROUP BY p.policy ORDER BY standard_count DESC'
    ),
    term_steward AS (
      QUESTION 'Who is responsible for the business term Contract Value?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT t.term, t.term_domain, ac.acc_role, ac.acc_person, ac.acc_email, ac.is_inherited FROM __terms AS t JOIN __accountability AS ac ON ac.acc_domain = t.term_domain WHERE t.term ILIKE ''Contract Value'' ORDER BY t.term_domain, ac.is_inherited, ac.acc_role'
    ),
    retired_attributes AS (
      QUESTION 'Which Collibra attributes are being retired and how many values do they hold?'
      ONBOARDING_QUESTION FALSE
      SQL 'SELECT at.attribute_asset_type, at.attribute_type, COUNT(at.attribute_value) AS value_count FROM __attributes AS at WHERE NOT at.in_scope GROUP BY at.attribute_asset_type, at.attribute_type ORDER BY value_count DESC'
    )
  );
