#!/usr/bin/env python3
"""Run the differential suite and print the results table and the headline.

Deterministic: `forge test --offline`, fixed timestamps set by vm.warp in the tests, no fuzzing, no RPC, no clock.
Each test logs one tab-separated ROW line; this script checks that every scope case ran and passed, prints one row
per case, then picks the headline by the scope's rule (docs/scope.md, decision 2): only like-for-like rows can be the
headline. Exits non-zero if forge fails, a test fails, or a case row is missing or duplicated.
"""

import json
from pathlib import Path
import re
import subprocess
import sys

CASES = range(1, 17)
LIKE_FOR_LIKE = "like-for-like"
ROOT = Path(__file__).resolve().parents[1]
SUITE = "test/Differential.t.sol:DifferentialTest"
PINS = {
    "lib/df": "b4b8c41fc912455a1af2300bfcd1276676b92a2e",
    "lib/sp": "e0004e63edc4e17de7aa978293800ac7a16892e5",
}
CLASSES = {c: LIKE_FOR_LIKE for c in CASES}
CLASSES.update({
    3: "revocation model", 10: "recipient (CB cannot name one)",
    11: "no CB calldata path", 12: "no CB method path",
    14: "configuration (kit refuses per source, not run)",
    15: "expressibility (CB is uint160)",
})


class ReproductionError(Exception):
    """A command or its evidence could not be trusted."""


def command(args):
    try:
        return subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    except OSError as exc:
        raise ReproductionError(f"cannot run {args[0]}: {exc}") from exc


def git(*args):
    proc = command(["git", *args])
    if proc.returncode:
        fail(f"git {' '.join(args)} exited {proc.returncode}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def fail(msg):
    raise ReproductionError(msg)


def provenance():
    for path, pin in PINS.items():
        for revision in ("HEAD", ":"):
            spec = f"HEAD:{path}" if revision == "HEAD" else f":{path}"
            if git("rev-parse", spec) != pin:
                fail(f"{path} {revision} gitlink differs from pinned commit {pin}")
        if git("-C", path, "rev-parse", "HEAD") != pin:
            fail(f"{path} checkout differs from pinned commit {pin}")
    # Nested dependencies are pinned by each upstream's gitlinks as well.
    status = git("submodule", "status", "--recursive")
    if any(line.startswith(("-", "+", "U")) for line in status.splitlines()):
        fail("submodules missing or not at pinned gitlinks; initialize recursively before reproducing")
    dirty = git("status", "--porcelain", "--untracked-files=all", "--ignore-submodules=none")
    return git("rev-parse", "HEAD") + ("+dirty" if dirty else "")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def run_forge():
    version = command(["forge", "--version"])
    if version.returncode or not re.search(r"\bVersion: 1\.8\.6(?:[+\s]|$)", version.stdout):
        fail("requires pinned forge 1.8.6")
    proc = command(["forge", "test", "--offline", "--json", "-vv"])
    if proc.returncode:
        fail(f"forge exited {proc.returncode}: {proc.stderr.strip() or proc.stdout.strip()}")
    out = proc.stdout
    start = out.find("{")
    if start < 0:
        fail("forge printed no JSON (if solc is missing, run `make test` once to install it)")
    try:
        suites = json.loads(out[start:], object_pairs_hook=unique_object)
    except (json.JSONDecodeError, ValueError) as exc:
        fail(f"could not parse forge JSON: {exc}")
    return suites


def collect(suites):
    rows, failed, total = {}, [], 0
    if not isinstance(suites, dict) or SUITE not in suites:
        fail(f"missing suite {SUITE}")
    for suite_name, suite in suites.items():
        if not isinstance(suite, dict) or not isinstance(suite.get("test_results"), dict):
            fail(f"malformed suite {suite_name}")
        for name, result in suite["test_results"].items():
            total += 1
            if not isinstance(result, dict) or not isinstance(result.get("decoded_logs"), list):
                fail(f"malformed test result {name}")
            logs = result["decoded_logs"]
            if not all(isinstance(line, str) for line in logs):
                fail(f"malformed logs from {name}")
            if result.get("status") != "Success":
                failed.append(f"{name}: {result.get('reason') or 'not successful'}")
            match = re.fullmatch(r"test_case([1-9][0-9]*)_[A-Za-z0-9_]+\(\)", name)
            expected = int(match[1]) if match and suite_name == SUITE else None
            count = 0
            for line in logs:
                if not line.startswith("ROW"):
                    continue
                count += 1
                fields = line.split("\t")[1:]
                if not line.startswith("ROW\t") or len(fields) != 7:
                    fail(f"malformed row from {name}: {line!r}")
                if not re.fullmatch(r"[1-9][0-9]*", fields[0]):
                    fail(f"invalid case ID from {name}: {fields[0]!r}")
                case = int(fields[0])
                if case not in CASES:
                    fail(f"unexpected case {case}")
                if case != expected:
                    fail(f"case {case} is not attributable to {suite_name}:{name}")
                if case in rows:
                    fail(f"case {case} reported twice")
                if any(not field.strip() or any(ord(c) < 32 or ord(c) == 127 for c in field) for field in fields):
                    fail(f"empty or control characters in row from {name}")
                if fields[2] != CLASSES[case] or fields[5] not in ("agree", "differ"):
                    fail(f"invalid class or result from {name}")
                if not all(re.fullmatch(r"lib/(?:df|sp)/[^ :;]+:[1-9][0-9]*", cite)
                           for cite in fields[6].split("; ")):
                    fail(f"invalid citation from {name}")
                rows[case] = dict(zip(["case", "name", "cls", "mm", "cb", "result", "cite"], fields))
            if expected is not None and count != 1:
                fail(f"{name} must emit exactly one row")
    missing = sorted(set(CASES) - rows.keys())
    if missing:
        fail(f"no result row for cases {missing}")
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
    commit = provenance()
    suites = run_forge()
    rows, failed, total = collect(suites)
    if failed:
        fail("failing tests:\n  " + "\n  ".join(failed))
    if provenance() != commit:
        fail("repository state changed during reproduction")
    print(f"commit {commit}")
    print(
        f"MetaMask delegation-framework {PINS['lib/df']}, "
        f"Coinbase spend-permissions {PINS['lib/sp']}"
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
    try:
        main()
    except ReproductionError as exc:
        print(f"reproduce: {exc}", file=sys.stderr)
        sys.exit(1)
