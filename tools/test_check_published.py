"""Tests for tools/check_published.py and the corpus containment it guards.

Run from the repository root: python -m unittest tools.test_check_published -v
Each detection case builds its own temporary git repository.
"""
import ast
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GUARD = os.path.join(ROOT, "tools", "check_published.py")
INVENTORY = os.path.join(ROOT, "tools", "corpus-inventory.txt")

# Sweep for this card: git ls-files | rg '^(out/|HubNode/HubNode/Resources/Corpus/)'
SWEPT_FILE_COUNT = 133


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True,
                          capture_output=True, text=True).stdout


def write(root, rel, text):
    path = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(text, bytes):
        with open(path, "wb") as fh:
            fh.write(text)
        return
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)


class TempRepo:
    """A throwaway git repository with an inventory and the given files committed."""

    def __init__(self, files, inventory="out/\nsecret/plan.txt\n"):
        self._tmp = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)
        self.path = self._tmp.name
        git(self.path, "init", "-q")
        git(self.path, "config", "user.email", "test@example.invalid")
        git(self.path, "config", "user.name", "test")
        git(self.path, "config", "core.autocrlf", "false")
        write(self.path, "tools/corpus-inventory.txt", inventory)
        write(self.path, "README.md", "fictional demo\n")
        for rel, text in files.items():
            write(self.path, rel, text)
        git(self.path, "add", "-A")
        git(self.path, "commit", "-q", "-m", "fixture")

    def run_guard(self):
        return subprocess.run([sys.executable, GUARD], cwd=self.path,
                              capture_output=True, text=True)

    def close(self):
        self._tmp.cleanup()


class CheckPublishedTest(unittest.TestCase):

    def guard(self, files, **kw):
        repo = TempRepo(files, **kw)
        self.addCleanup(repo.close)
        return repo.run_guard()

    def assertFlags(self, result, rel):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(rel, result.stdout)

    def test_detects_inventory_path(self):
        cases = {
            "listed file": "secret/plan.txt",
            "file under a listed directory": "out/pdf/hub.txt",
        }
        for label, rel in cases.items():
            with self.subTest(label):
                self.assertFlags(self.guard({rel: "anything\n"}), rel)
        with self.subTest("unlisted path sharing a listed file's prefix"):
            result = self.guard({"secret/plan.txt.md": "anything\n"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_detects_restricted_row(self):
        header = "hub,kind,asset,sensitivity\n"
        restricted = header + "Hub A,school,Hall,public\nHub A,care,Rest Home,restricted\n"
        with self.subTest("restricted row"):
            self.assertFlags(self.guard({"data/people.csv": restricted}),
                             "data/people.csv")
        with self.subTest("public rows and a CSV without a sensitivity column"):
            public = header + "Hub A,school,Hall,public\n"
            result = self.guard({"data/people.csv": public,
                                 "data/hubs.csv": "hub,ta_name\nHub A,Wellington City\n"})
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        first = "sensitivity,hub,asset\npublic,Hub A,Hall\nrestricted,Hub A,Rest Home\n"
        with self.subTest("UTF-8 byte order mark before a first sensitivity column"):
            self.assertFlags(self.guard({"data/bom.csv": "﻿" + first}), "data/bom.csv")
        with self.subTest("UTF-16 file with its byte order mark"):
            self.assertFlags(self.guard({"data/wide.csv": first.encode("utf-16")}),
                             "data/wide.csv")
        with self.subTest("upper and mixed case .csv extension"):
            result = self.guard({"data/people.CSV": restricted, "data/staff.Csv": restricted})
            self.assertFlags(result, "data/people.CSV")
            self.assertFlags(result, "data/staff.Csv")
        with self.subTest("header and value differ in case or surrounding space"):
            loose = "hub, Sensitivity \nHub A, Restricted \n"
            self.assertFlags(self.guard({"data/loose.csv": loose}), "data/loose.csv")

    def test_detects_guide_marker(self):
        # Line breaks inside each phrase, as PDF text extraction produces.
        markers = [
            "Locate the Community\nEmergency Hub kit 6",
            "Give an overview of who might\nbe available to help 30",
            "What can our community do to help each other\nthrough the recovery? 41",
        ]
        for text in markers:
            with self.subTest(text):
                result = self.guard({"notes/guide.txt": "Section 1\n" + text + "\n"})
                self.assertFlags(result, "notes/guide.txt")

    def test_inventory_paths_untracked(self):
        with open(INVENTORY, encoding="utf-8") as fh:
            entries = [line.strip() for line in fh if line.strip()]
        files = [e for e in entries if not e.endswith("/")]
        dirs = [e for e in entries if e.endswith("/")]
        self.assertEqual(len(files), SWEPT_FILE_COUNT)
        self.assertIn("out/", dirs)
        self.assertIn("HubNode/HubNode/Resources/Corpus/", dirs)
        tracked = git(ROOT, "ls-files").splitlines()
        still_tracked = [p for p in tracked
                         if p in files or any(p.startswith(d) for d in dirs)]
        self.assertEqual(still_tracked, [])

    def test_default_out_dir(self):
        for tool in ("ingest_wremo.py", os.path.join("tools", "build_plan_chunks.py")):
            with self.subTest(tool):
                self.assertEqual(out_default(os.path.join(ROOT, tool)), "corpus")
        with open(os.path.join(ROOT, ".gitignore"), encoding="utf-8") as fh:
            self.assertIn("corpus/", [line.strip() for line in fh])


def out_default(path):
    """The literal default of the tool's argparse --out option, normalised."""
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and getattr(node.func, "attr", None) == "add_argument"
                and node.args and isinstance(node.args[0], ast.Constant)
                and node.args[0].value == "--out"):
            for kw in node.keywords:
                if kw.arg == "default":
                    return os.path.normpath(ast.literal_eval(kw.value)).replace("\\", "/")
    return None


if __name__ == "__main__":
    unittest.main()
