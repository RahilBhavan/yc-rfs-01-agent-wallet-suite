#!/usr/bin/env python3
"""Run the differential suite and print the results table and the headline.

Deterministic: `forge test --offline`, fixed timestamps set by vm.warp in the tests, no fuzzing, no RPC, no clock.
Each test logs one tab-separated ROW line; this script checks that every scope case ran and passed, prints one row
per case, then picks the headline by the scope's rule (docs/scope.md, decision 2): only like-for-like rows can be the
headline. Exits non-zero if forge fails, a test fails, or a case row is missing or duplicated.
"""

import json
import subprocess
import sys

CASES = range(1, 17)
LIKE_FOR_LIKE = "like-for-like"


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def fail(msg):
    print(f"reproduce: {msg}", file=sys.stderr)
    sys.exit(1)


def run_forge():
    proc = subprocess.run(["forge", "test", "--offline", "--json", "-vv"], capture_output=True, text=True)
    out = proc.stdout
    start = out.find("{")
    if start < 0:
        sys.stderr.write(proc.stderr)
        fail("forge printed no JSON (if solc is missing, run `make test` once to install it)")
    try:
        suites = json.loads(out[start:])
    except json.JSONDecodeError as e:
        fail(f"could not parse forge JSON: {e}")
    return proc.returncode, suites


def collect(suites):
    rows, failed, total = {}, [], 0
    for suite in suites.values():
        for name, result in suite["test_results"].items():
            total += 1
            if result["status"] != "Success":
                failed.append(f"{name}: {result.get('reason')}")
            for line in result["decoded_logs"]:
                if not line.startswith("ROW\t"):
                    continue
                fields = line.split("\t")[1:]
                if len(fields) != 7:
                    fail(f"malformed row from {name}: {line!r}")
                case = int(fields[0])
                if case in rows:
                    fail(f"case {case} reported twice")
                rows[case] = dict(zip(["case", "name", "cls", "mm", "cb", "result", "cite"], fields))
    return rows, failed, total


def headline(rows):
    lfl = [r for r in rows if r["cls"] == LIKE_FOR_LIKE]
    differ = [r for r in lfl if r["result"] == "differ"]
    if not differ:
        return f"Headline: the two agree on all {len(lfl)} like-for-like cases ({len(rows)} cases run)."
    first = differ[0]
    text = (
        f"Headline: case {first['case']} ({first['name']}) differs like-for-like: "
        f"MetaMask {first['mm']}; Coinbase {first['cb']}."
    )
    if len(differ) == 1:
        text += f" The other {len(lfl) - 1} like-for-like cases agree."
    else:
        text += " Like-for-like differences also in cases " + ", ".join(r["case"] for r in differ[1:]) + "."
    return text


def cell(s):
    return s.replace("|", "\\|")


def main():
    code, suites = run_forge()
    rows, failed, total = collect(suites)
    if failed:
        fail("failing tests:\n  " + "\n  ".join(failed))
    if code != 0:
        fail(f"forge exited {code}")
    missing = [c for c in CASES if c not in rows]
    if missing:
        fail(f"no result row for cases {missing}")
    extra = sorted(set(rows) - set(CASES))
    if extra:
        fail(f"unexpected cases {extra}")

    dirty = "+dirty" if git("status", "--porcelain", "--untracked-files=no") else ""
    print(f"commit {git('rev-parse', 'HEAD')}{dirty}")
    print(
        f"MetaMask delegation-framework {git('-C', 'lib/df', 'rev-parse', '--short', 'HEAD')}, "
        f"Coinbase spend-permissions {git('-C', 'lib/sp', 'rev-parse', '--short', 'HEAD')}"
    )
    print()
    print("| Case | Class | MetaMask (HybridDeleGator + kit ERC-20 periodic scope) | Coinbase (SpendPermissionManager) | Result | file:line |")
    print("|---|---|---|---|---|---|")
    ordered = [rows[c] for c in CASES]
    for r in ordered:
        print(
            f"| {r['case']}. {cell(r['name'])} | {cell(r['cls'])} | {cell(r['mm'])} | {cell(r['cb'])} | "
            f"{r['result']} | {cell(r['cite'])} |"
        )
    print()
    print(f"{len(ordered)} cases ran; {total} tests passed, 0 failed.")
    print(headline(ordered))


if __name__ == "__main__":
    main()
