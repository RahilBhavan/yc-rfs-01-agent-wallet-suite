"""Collector and command-boundary regressions; no Forge or network required."""
import contextlib
import copy
import io
import json
import os
import subprocess
import sys
import unittest
from unittest.mock import patch

import reproduce as r


def fixture():
    return {r.SUITE: {"test_results": {
        f"test_case{case}_example()": {
            "status": "Success",
            "decoded_logs": ["\t".join([
                "ROW", str(case), f"case {case}", r.CLASSES[case], "accepted", "rejected",
                "differ" if case in (2, 3, 10) else "agree",
                "lib/df/src/Example.sol:1; lib/sp/src/Example.sol:2",
            ])],
        } for case in r.CASES
    }}}


def first(data):
    return data[r.SUITE]["test_results"]["test_case1_example()"]


def proc(stdout="", stderr="", code=0):
    return subprocess.CompletedProcess([], code, stdout, stderr)


class CollectorTests(unittest.TestCase):
    def test_complete_and_headline(self):
        rows, failed, total = r.collect(fixture())
        self.assertEqual((len(rows), failed, total), (16, [], 16))
        ordered = [rows[c] for c in r.CASES]
        self.assertIn("Headline: case 2", r.headline(ordered))
        rows[2]["result"] = "agree"
        self.assertEqual(r.headline(ordered),
                         "Headline: the two agree on all 10 like-for-like cases (16 cases run).")

    def test_bad_envelopes(self):
        for data in (None, [], {}, {r.SUITE: None}, {r.SUITE: {}},
                     {r.SUITE: {"test_results": []}}):
            with self.subTest(data=data), self.assertRaises(r.ReproductionError):
                r.collect(data)

    def test_bad_results(self):
        for result in (None, {}, {"decoded_logs": None}, {"decoded_logs": [1]}):
            data = fixture()
            data[r.SUITE]["test_results"]["test_case1_example()"] = result
            with self.subTest(result=result), self.assertRaises(r.ReproductionError):
                r.collect(data)

    def test_missing_row_and_case(self):
        for remove_test in (False, True):
            data = fixture()
            if remove_test:
                del data[r.SUITE]["test_results"]["test_case1_example()"]
            else:
                first(data)["decoded_logs"] = []
            with self.assertRaises(r.ReproductionError):
                r.collect(data)

    def test_duplicate_rows_and_tests(self):
        for duplicate_test in (False, True):
            data = fixture()
            if duplicate_test:
                data[r.SUITE]["test_results"]["test_case1_duplicate()"] = copy.deepcopy(first(data))
            else:
                first(data)["decoded_logs"] *= 2
            with self.assertRaisesRegex(r.ReproductionError, "reported twice"):
                r.collect(data)

    def test_row_must_belong_to_corresponding_test_and_suite(self):
        for foreign_suite in (False, True):
            data = fixture()
            tests = data[r.SUITE]["test_results"]
            result = tests.pop("test_case1_example()")
            if foreign_suite:
                data["test/Other.t.sol:DifferentialTest"] = {"test_results": {"test_case1_example()": result}}
            else:
                tests["test_unrelated()"] = result
            with self.assertRaisesRegex(r.ReproductionError, "not attributable"):
                r.collect(data)

    def test_invalid_fields(self):
        for index, value in ((1, "no"), (1, "01"), (1, "17"), (1, "2"),
                             (2, ""), (2, "line\nbreak"), (3, "unknown"),
                             (6, "pass"), (7, "no citation"), (7, "lib/df/a.sol:0")):
            data = fixture()
            fields = first(data)["decoded_logs"][0].split("\t")
            fields[index] = value
            first(data)["decoded_logs"] = ["\t".join(fields)]
            with self.subTest(index=index, value=value), self.assertRaises(r.ReproductionError):
                r.collect(data)

    def test_malformed_row(self):
        for line in ("ROW bad", "ROW\t1", fixture()[r.SUITE]["test_results"]["test_case1_example()"]["decoded_logs"][0] + "\textra"):
            data = fixture()
            first(data)["decoded_logs"] = [line]
            with self.assertRaisesRegex(r.ReproductionError, "malformed row"):
                r.collect(data)

    def test_unsuccessful_test_cannot_publish(self):
        for status in ("Failure", "Skipped", None):
            data = fixture()
            first(data)["status"] = status
            with patch.object(r, "provenance", return_value="abc"), patch.object(r, "run_forge", return_value=data):
                output = io.StringIO()
                with contextlib.redirect_stdout(output), self.assertRaisesRegex(r.ReproductionError, "failing tests"):
                    r.main()
                self.assertEqual(output.getvalue(), "")

    def test_success_table_order_and_escaping(self):
        data = fixture()
        first(data)["decoded_logs"][0] = first(data)["decoded_logs"][0].replace("case 1\t", "case | 1\t")
        data[r.SUITE]["test_results"] = dict(reversed(list(data[r.SUITE]["test_results"].items())))
        with patch.object(r, "provenance", return_value="abc+dirty"), patch.object(r, "run_forge", return_value=data):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                r.main()
        text = output.getvalue()
        self.assertIn("commit abc+dirty", text)
        self.assertIn("16 cases ran; 16 tests passed, 0 failed.", text)
        self.assertIn("| 1. case \\| 1 |", text)
        self.assertLess(text.index("| 2. case 2"), text.index("| 10. case 10"))
        self.assertIn("Headline: case 2", text)


class CommandTests(unittest.TestCase):
    def test_cli_command_failure_is_nonzero_without_table_or_traceback(self):
        result = subprocess.run(
            [sys.executable, str(r.ROOT / "tools/reproduce.py")],
            cwd=r.ROOT / "tools", env={**os.environ, "PATH": ""},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertIn("reproduce: cannot run git", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_missing_executable(self):
        with patch.object(r.subprocess, "run", side_effect=FileNotFoundError("missing")):
            with self.assertRaisesRegex(r.ReproductionError, "cannot run forge"):
                r.command(["forge"])

    def test_commands_are_anchored_to_worktree(self):
        with patch.object(r.subprocess, "run", return_value=proc()) as run:
            r.command(["git", "status"])
        self.assertEqual(run.call_args.kwargs["cwd"], r.ROOT)

    def test_git_failure(self):
        with patch.object(r, "command", return_value=proc(stderr="fatal", code=128)):
            with self.assertRaisesRegex(r.ReproductionError, "git status exited 128: fatal"):
                r.git("status")

    def test_forge_nonzero_even_with_valid_json(self):
        with patch.object(r, "command", side_effect=[proc("forge Version: 1.8.6"), proc(json.dumps(fixture()), "compile failed", 1)]):
            with self.assertRaisesRegex(r.ReproductionError, "forge exited 1: compile failed"):
                r.run_forge()

    def test_pinned_forge_required(self):
        for version in (proc("forge Version: 1.8.5"), proc("forge Version: 1.8.60"), proc(code=1)):
            with patch.object(r, "command", return_value=version) as run:
                with self.assertRaisesRegex(r.ReproductionError, "pinned forge"):
                    r.run_forge()
                self.assertEqual(run.call_count, 1)

    def test_malformed_json(self):
        for output in ("no output", "{bad", '{"x":{},"x":{}}', json.dumps(fixture()) + " trailing"):
            with patch.object(r, "command", side_effect=[proc("forge Version: 1.8.6"), proc(output)]):
                with self.subTest(output=output), self.assertRaises(r.ReproductionError):
                    r.run_forge()

    def test_forge_json_with_compiler_preamble(self):
        data = fixture()
        with patch.object(r, "command", side_effect=[proc("forge Version: 1.8.6"), proc("Compiling...\n" + json.dumps(data))]) as run:
            self.assertEqual(r.run_forge(), data)
        self.assertEqual(run.call_args.args[0], ["forge", "test", "--offline", "--json", "-vv"])

    def test_no_table_on_command_failure(self):
        with patch.object(r, "provenance", return_value="abc"), patch.object(r, "run_forge", side_effect=r.ReproductionError("forge failed")):
            output = io.StringIO()
            with contextlib.redirect_stdout(output), self.assertRaises(r.ReproductionError):
                r.main()
            self.assertEqual(output.getvalue(), "")


class ProvenanceTests(unittest.TestCase):
    def git(self, *args):
        if args[0] == "rev-parse" and args[1] != "HEAD":
            return r.PINS[args[1].split(":")[-1]]
        if args[0] == "-C":
            return r.PINS[args[1]]
        if args[0] == "submodule":
            return " b4b8 lib/df\n e000 lib/sp"
        if args[0] == "status":
            self.assertIn("--untracked-files=all", args)
            self.assertIn("--ignore-submodules=none", args)
            return ""
        return "parent-commit"

    def test_clean_and_dirty_including_untracked(self):
        for status in ("", "?? untracked.sol", " m lib/df", " M tools/reproduce.py"):
            def git(*args):
                return status if args[0] == "status" else self.git(*args)
            with patch.object(r, "git", side_effect=git):
                self.assertEqual(r.provenance(), "parent-commit" + ("+dirty" if status else ""))

    def test_wrong_head_index_or_checkout_pin(self):
        for changed in (("rev-parse", "HEAD:lib/df"), ("rev-parse", ":lib/sp"), ("-C", "lib/df", "rev-parse", "HEAD")):
            def git(*args):
                return "wrong" if args == changed else self.git(*args)
            with patch.object(r, "git", side_effect=git), self.assertRaisesRegex(r.ReproductionError, "pinned commit"):
                r.provenance()

    def test_nested_uninitialized_moved_or_conflicted(self):
        for marker in ("-", "+", "U"):
            def git(*args):
                return " b4b8 lib/df\n" + marker + "abc lib/df/lib/dependency" if args[0] == "submodule" else self.git(*args)
            with patch.object(r, "git", side_effect=git), self.assertRaisesRegex(r.ReproductionError, "pinned gitlinks"):
                r.provenance()


if __name__ == "__main__":
    unittest.main()
