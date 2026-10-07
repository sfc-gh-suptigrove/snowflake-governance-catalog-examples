# Snowflake Governance Catalog Examples

Boilerplate SQL, agent skills and a Python smoke-test harness for querying a Collibra-style governance catalog with a Snowflake semantic view and Cortex Agent.

**Start with [GUIDE.md](GUIDE.md).** It covers prerequisites, schema mapping, deployment order and testing.

## Included

- [Semantic view and literal-name search](sql/01_semantic_view.sql): field descriptions, 22 metrics and 15 example verified queries.
- [Catalog search and Cortex Agent](sql/02_search_and_agent.sql): tool routing, response instructions and staged skills.
- [Agent skills](skills/): glossary lookup, stewardship and access, vendor risk, and migration reconciliation.
- [Pressure-test script](tools/pressure_test.py): 16 illustrative cases checking keywords, tool calls and skill loading.

## Before you use it

These are adaptation templates, not a standalone demo. You must supply the prerequisite bronze and gold catalog objects, map the schema, and replace the sample questions and expected answers. All names and test fixtures are illustrative. No customer extracts or credentials are included.

Review the `CREATE OR REPLACE` statements before running them. Deploying search services and invoking the agent can incur Snowflake charges. The public version has not been executed against a target account, and its test fixtures do not represent a supplied dataset.

## Get the files

Read individual files directly in GitHub, download them using each file's **Raw** view, or clone the repository:

```bash
git clone https://github.com/sfc-gh-suptigrove/snowflake-governance-catalog-examples.git
cd snowflake-governance-catalog-examples
```

Keep credentials, private keys, real catalog exports, agent traces and test outputs outside this repository.
