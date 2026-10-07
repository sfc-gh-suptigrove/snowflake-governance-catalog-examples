#!/usr/bin/env python3
"""Pressure test for DATA_CATALOG_AGENT (boilerplate example).

The expected values below are illustrative fixtures, not customer facts or a validated dataset.
Replace each case with questions and ground-truth answers from your own catalog before use.

Runs each case through the Agent API (`cortex agents run`), reads the saved trace,
and checks three things per case:
  * the answer contains the ground-truth facts (any-of keyword groups, all groups required)
  * the expected tool was called
  * the expected skill was loaded (when one is expected)
The prerequisite data is not distributed with these examples.

Usage: python3 tools/pressure_test.py -c <connection> [--agent <fully-qualified-agent>] [-k case_id ...]
"""
import argparse, concurrent.futures as cf, json, re, subprocess, sys, time

AGENT = "CATALOG_DEMO.GOVERNED_DG.DATA_CATALOG_AGENT"

# id, question, required keyword groups (each group: any one must appear), expected tool, expected skill, forbidden
CASES = [
    ("domain_contents", "What is in the Analytics Mart domain, and what is still Candidate?",
     [["12"], ["40"]], "catalog_analyst", None, []),
    ("term_meaning", "What does Surrender Charge mean and which columns use it?",
     [["three", "3 "], ["Alex Parker"]], "catalog_analyst", "glossary-term-lookup", []),
    ("misspelled_term", "what's a surender charg?",
     [["Surrender Charge"]], "catalog_search", "glossary-term-lookup", []),
    ("nonexistent_term", "What does Quantum Ledger Factor mean?",
     [["no ", "not ", "couldn't", "could not", "doesn't", "does not"]], "catalog_search", None,
     ["Quantum Ledger Factor is defined as", "Quantum Ledger Factor means"]),
    ("access_request", "Who do I ask for access to the Analytics Mart data?",
     [["Avery Reed"], ["no Data Owner", "No Data Owner", "not recorded", "none is", "no data owner"]], "catalog_analyst", "stewardship-and-access", ["Alex Parker"]),
    ("term_steward", "Who is responsible for the business term Contract Value?",
     [["Alex Parker"]], "catalog_analyst", None, []),
    ("domain_steward", "Who stewards the Analytics Mart domain?",
     [["Avery Reed"]], "catalog_analyst", None, []),  # matches a verified query: answered directly, no skill needed
    ("vendor_portfolio", "Which vendors with High AI risk provide the most applications?",
     [["one application", "1 application", "exactly one", "exactly **one**", "tie"]], "catalog_analyst", None, []),  # verified-query hit
    ("pii_chain", "How many systems depend on applications from vendors that handle PII?",
     [["10"]], "catalog_analyst", None, []),
    ("vendor_impact", "If Example Vendor had an incident, which applications and systems would be affected?",
     [["Example Vendor"]], "catalog_analyst", "vendor-risk-review", []),
    ("migration_complete", "Did every Collibra asset make it into Snowflake?",
     [["1,000", "1000"], ["0 ", "zero", "all ", "All "]], "catalog_analyst", "migration-reconciliation", []),
    ("cde_gap", "Which critical data elements are not linked to any column?",
     [["none", "None", "no ", "0", "all "]], "catalog_analyst", None, []),
    ("tier1", "How many Tier 1 applications are there?",
     [["20"]], "catalog_analyst", None, []),
    ("policies", "How many standards does each policy include?",
     [["Data Quality Policy"], ["5"], ["4"]], "catalog_analyst", None, []),
    ("out_of_scope_values", "What is the average contract value of our annuity policyholders?",
     [["catalog", "metadata"]], None, None, []),
    ("write_attempt", "Change the status of the Analytics Mart domain to Approved.",
     [["cannot", "can't", "not able", "unable"]], None, None, ["has been changed", "I've updated", "I have updated"]),
]

TRACE_RE = re.compile(r"saved to (\S+\.json)")


def run_case(case, conn, agent):
    cid, q, groups, tool, skill, forbidden = case
    t0 = time.time()
    p = subprocess.run(["cortex", "agents", "run", "-c", conn, agent, q],
                       capture_output=True, text=True, timeout=600)
    secs = round(time.time() - t0)
    out = p.stdout + p.stderr
    m = TRACE_RE.search(out.replace("\n", ""))
    tools, skills, answer = set(), set(), out
    if m:
        try:
            events = json.load(open(m.group(1)))
            texts = []
            for e in events:
                d = e.get("data", {})
                if e.get("event") == "response.tool_use":
                    tools.add(d.get("name"))
                    sk = (d.get("input") or {}).get("skill_name")
                    if sk:
                        skills.add(sk)
                elif e.get("event") in ("response.text", "response.text.delta"):
                    texts.append(d.get("text", ""))
                elif e.get("event") == "response.table":
                    texts.append(json.dumps(d))
            if texts:
                answer = out + "\n" + "".join(texts)
        except Exception as ex:  # trace unreadable: fall back to stdout only
            answer = out + f"\n[trace error {ex}]"
    norm = answer.replace("\n", " ")
    missing = [g for g in groups if not any(k in norm for k in g)]
    bad = [f for f in forbidden if f in norm]
    tool_ok = tool is None or tool in tools or (tool == "catalog_analyst" and "system_execute_sql" in tools)
    skill_ok = skill is None or skill in skills
    ok = not missing and not bad and tool_ok and skill_ok and p.returncode == 0
    return dict(id=cid, ok=ok, secs=secs, tools=sorted(t for t in tools if t), skills=sorted(skills),
                missing=missing, forbidden_hit=bad, tool_ok=tool_ok, skill_ok=skill_ok,
                answer=re.sub(r"\[Trace:.*", "", out, flags=re.S).strip()[:1500])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-c", "--connection", required=True)
    ap.add_argument("--agent", default=AGENT)
    ap.add_argument("--output", default="pressure_test_results.json")
    ap.add_argument("-k", "--keys", nargs="*")
    ap.add_argument("-j", "--jobs", type=int, default=4)
    a = ap.parse_args()
    if a.jobs < 1:
        ap.error("--jobs must be at least 1")
    known_keys = {case[0] for case in CASES}
    unknown_keys = set(a.keys or []) - known_keys
    if unknown_keys:
        ap.error("unknown case IDs: " + ", ".join(sorted(unknown_keys)))
    cases = [c for c in CASES if not a.keys or c[0] in a.keys]
    with cf.ThreadPoolExecutor(a.jobs) as ex:
        results = list(ex.map(lambda c: run_case(c, a.connection, a.agent), cases))
    for r in results:
        flag = "PASS" if r["ok"] else "FAIL"
        print(f"{flag} {r['id']:<22} {r['secs']:>4}s tools={r['tools']} skills={r['skills']}")
        if not r["ok"]:
            print(f"     missing={r['missing']} forbidden={r['forbidden_hit']} tool_ok={r['tool_ok']} skill_ok={r['skill_ok']}")
            print("     " + r["answer"].replace("\n", " ")[:900])
    n = sum(r["ok"] for r in results)
    print(f"\n{n}/{len(results)} passed")
    with open(a.output, "w", encoding="utf-8") as output_file:
        json.dump(results, output_file, indent=1)
    sys.exit(0 if n == len(results) else 1)


if __name__ == "__main__":
    main()
