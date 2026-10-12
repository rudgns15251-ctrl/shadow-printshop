#!/usr/bin/env python3
"""Game Harness v0.7-B: conservative failure triage and EXPLICIT recovery.

Read-only classification by default.  A blocked task can only be reset after
all Windows Git, SQLite, lock, history and worktree checks pass; --apply must be
explicit.  Existing logs and the old Git worktree are retained. Never invokes
Codex, modifies Godot projects, or approves tasks.
"""
from __future__ import annotations

import argparse
from contextlib import closing
import datetime as dt
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import uuid
from dataclasses import dataclass

TASK_ID_RE = re.compile(r"[A-Za-z0-9_-]{1,48}\Z")
EXIT_RE = re.compile(r"^Codex exited with code [1-9][0-9]*\.")
POLICY_MARKERS = ("out-of-scope", "symlink", "protected file", "unexpected git commit", "blocked potentially destructive")


class RecoveryRefused(RuntimeError):
    pass


@dataclass(frozen=True)
class Assessment:
    task_id: str
    status: str
    attempts: int
    note: str
    category: str
    eligible: bool
    reason: str
    workspace: str | None


def _git(root: Path, *args: str, timeout: int = 25) -> str:
    env = os.environ.copy()
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        env.pop(key, None)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    result = subprocess.run(["git", *map(str, args)], cwd=root, env=env,
                            capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout)
    if result.returncode:
        raise RecoveryRefused(f"Windows Git failed ({' '.join(args[:3])}): {(result.stderr or result.stdout)[-500:]}")
    return result.stdout


def _run_git_mutation(root: Path, *args: str, timeout: int = 90):
    env = os.environ.copy()
    for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        env.pop(key, None)
    result = subprocess.run(["git", *map(str, args)], cwd=root, env=env,
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    if result.returncode:
        raise RecoveryRefused(f"Git worktree move failed: {(result.stderr or result.stdout)[-500:]}")


def _db_row(root: Path, task_id: str):
    source = root / ".data" / "state.sqlite3"
    if not source.is_file():
        raise RecoveryRefused("state.sqlite3 is missing")
    try:
        with closing(sqlite3.connect(source.resolve().as_uri() + "?mode=ro", uri=True, timeout=3)) as conn:
            return conn.execute(
                "SELECT status, attempts, COALESCE(last_note,''), workspace FROM tasks WHERE id=?", (task_id,)
            ).fetchone()
    except sqlite3.Error as exc:
        raise RecoveryRefused(f"SQLite read failed: {exc}") from exc


def _registered_worktrees(root: Path) -> set[str]:
    lines = _git(root, "worktree", "list", "--porcelain").splitlines()
    return {_canonical(Path(line[9:])) for line in lines if line.startswith("worktree ")}


def _canonical(path: Path) -> str:
    return os.path.normcase(str(path.resolve()))


def _active_lock(root: Path) -> bool:
    # Refuse even a stale lock; explicit investigation must precede a destructive operation.
    return (root / ".data" / "autopilot.lock").exists()


def _category(note: str) -> tuple[str, bool]:
    low = note.lower()
    if any(marker in low for marker in POLICY_MARKERS):
        return "POLICY_VIOLATION", False
    if note.strip() == "Codex did not change any files.":
        return "NO_OUTPUT", True
    if EXIT_RE.match(note):
        return "CODEX_EXIT_NO_OUTPUT_POSSIBLE", True
    if "timed out" in low:
        return "TIMEOUT_UNCERTAIN", False
    if low.startswith(("godot ", "harness qa ", "independent validation failed:")):
        return "QA_FAILURE", False
    if low.startswith("execution or validation failed:"):
        return "EXECUTION_ERROR", False
    return "UNCLASSIFIED", False


def assess(root: Path, task_id: str) -> Assessment:
    root = root.resolve()
    if not TASK_ID_RE.fullmatch(task_id):
        raise RecoveryRefused("Invalid task identifier")
    manifest = root / "tasks" / "backlog.json"
    try:
        tasks = json.loads(manifest.read_text(encoding="utf-8"))["tasks"]
    except (OSError, KeyError, ValueError, TypeError) as exc:
        raise RecoveryRefused(f"Task manifest unavailable: {exc}") from exc
    if not any(isinstance(t, dict) and t.get("id") == task_id for t in tasks):
        raise RecoveryRefused("Task ID not listed in the approved manifest")
    row = _db_row(root, task_id)
    if row is None:
        raise RecoveryRefused("Task not initialized in SQLite")
    status, attempts, note, workspace = row
    category, note_eligible = _category(note)
    if status != "blocked":
        return Assessment(task_id, status, attempts, note, "NOT_BLOCKED", False,
                          "Only blocked tasks can be recovered", workspace)
    if not note_eligible:
        return Assessment(task_id, status, attempts, note, category, False,
                          "Failure category is not eligible for reset; manual investigation required", workspace)
    if not workspace:
        return Assessment(task_id, status, attempts, note, category, False,
                          "SQLite does not record a worktree", workspace)
    ws = Path(workspace)
    expected = root / ".worktrees" / task_id
    if ws.is_symlink() or expected.is_symlink() or _canonical(ws) != _canonical(expected) or not ws.is_dir():
        return Assessment(task_id, status, attempts, note, category, False,
                          "Worktree is missing, linked, or outside the expected directory", workspace)
    if _active_lock(root):
        return Assessment(task_id, status, attempts, note, category, False,
                          "Autopilot lock exists; investigate running processes before recovery", workspace)
    try:
        if _canonical(ws) not in _registered_worktrees(root):
            raise RecoveryRefused("Worktree is not registered in Windows Git")
        if _git(root, "status", "--porcelain=v1", "--untracked-files=all").strip():
            raise RecoveryRefused("Main Git checkout is dirty; review or commit changes first")
        if _git(root, "-C", str(ws), "status", "--porcelain=v1", "--untracked-files=all").strip():
            raise RecoveryRefused("Blocked worktree contains changes; preserve and inspect manually")
        # The worker creates detached worktrees. Never rewrite a normal branch checkout.
        proc = subprocess.run(["git", "-C", str(ws), "symbolic-ref", "-q", "HEAD"],
                              capture_output=True, timeout=15)
        if proc.returncode == 0:
            raise RecoveryRefused("Worktree is attached to a branch, not detached")
        ws_head = _git(root, "-C", str(ws), "rev-parse", "HEAD").strip()
        main_head = _git(root, "rev-parse", "HEAD").strip()
        ancestor = subprocess.run(["git", "-C", str(ws), "merge-base", "--is-ancestor", ws_head, main_head],
                                  capture_output=True, timeout=20)
        if ancestor.returncode != 0:
            raise RecoveryRefused("Worktree commit is not an ancestor of main; possible agent commit")
    except (RecoveryRefused, OSError, subprocess.TimeoutExpired) as exc:
        return Assessment(task_id, status, attempts, note, category, False, str(exc), workspace)
    return Assessment(task_id, status, attempts, note, category, True,
                      "Clean detached worktree; explicit backup + move + guarded SQLite reset available", workspace)


def _backup_sqlite(root: Path, backup_file: Path):
    src = root / ".data" / "state.sqlite3"
    with closing(sqlite3.connect(src, timeout=10)) as source:
        with closing(sqlite3.connect(backup_file, timeout=10)) as target:
            source.backup(target)


def recover(root: Path, task_id: str) -> dict:
    root = root.resolve()
    current = assess(root, task_id)
    if not current.eligible:
        raise RecoveryRefused(current.reason)
    unique = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
    backup_dir = root / ".data" / "recovery-v07b" / f"{task_id}-{unique}"
    archive_dir = root / ".data" / "recovered-worktrees" / f"{task_id}-before-{unique}"
    if backup_dir.exists() or archive_dir.exists():
        raise RecoveryRefused("Recovery target unexpectedly exists")
    backup_dir.mkdir(parents=True, exist_ok=False)
    _backup_sqlite(root, backup_dir / "state-before.sqlite3")
    # Check again *after* backup. A running worker or Git changes must stop recovery.
    latest = assess(root, task_id)
    if not latest.eligible or latest != current:
        raise RecoveryRefused("State changed during backup; no worktree or DB changes made")
    archive_dir.parent.mkdir(parents=True, exist_ok=True)
    old_ws = Path(current.workspace)
    prepared = {"task_id": task_id, "stage": "prepared", "sqlite_backup": str(backup_dir / "state-before.sqlite3"),
                "intended_archive": str(archive_dir), "attempts": current.attempts, "note": current.note}
    (backup_dir / "recovery.json").write_text(json.dumps(prepared, ensure_ascii=False, indent=2), encoding="utf-8")
    moved = False
    committed = False
    try:
        _run_git_mutation(root, "worktree", "move", str(old_ws), str(archive_dir))
        moved = True
        with closing(sqlite3.connect(root / ".data" / "state.sqlite3", timeout=10)) as conn:
            updated = conn.execute(
                "UPDATE tasks SET status='pending', workspace=NULL, updated=? "
                "WHERE id=? AND status='blocked' AND attempts=? AND workspace=? AND COALESCE(last_note,'')=?",
                (dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
                 task_id, current.attempts, current.workspace, current.note)
            )
            if updated.rowcount != 1:
                conn.rollback()
                raise RecoveryRefused("SQLite state changed; refusing recovery")
            conn.commit()
        committed = True
        record = {
            "task_id": task_id, "before_status": current.status, "after_status": "pending",
            "attempts_preserved": current.attempts, "prior_note": current.note,
            "failure_category": current.category, "archived_worktree": str(archive_dir),
            "sqlite_backup": str(backup_dir / "state-before.sqlite3"),
            "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat()
        }
        try:
            (backup_dir / "recovery.json").write_text(json.dumps({**record, "stage": "completed"}, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError:
            # The source worktree and DB already moved; do not roll them back for a report error.
            print("WARNING: recovery audit finalization failed; SQLite backup and archive were retained", file=sys.stderr)
        return record
    except Exception:
        if moved and not committed:
            try:
                _run_git_mutation(root, "worktree", "move", str(archive_dir), str(old_ws))
            except Exception as rollback_err:
                raise RecoveryRefused("Recovery error and worktree rollback failed; inspect archive and DB backup: " +
                                       str(archive_dir) + "; " + str(rollback_err)) from rollback_err
        raise


def main(argv=None, root=None):
    root = Path(root) if root is not None else Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="v0.7-B read-only triage / explicitly approved recovery")
    parser.add_argument("action", choices=("triage", "recover"))
    parser.add_argument("task_id")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true")
    group.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)
    try:
        assessment = assess(root, args.task_id)
        print(f"{assessment.task_id}: {assessment.status} attempts={assessment.attempts}")
        print(f"CATEGORY: {assessment.category}")
        print(f"ELIGIBLE: {assessment.eligible}")
        print("REASON:", assessment.reason)
        if args.action == "triage" or not args.apply:
            print("READ ONLY: no SQLite status, worktree, logs or Git history modified")
            return 0 if args.action == "triage" or assessment.eligible else 2
        if not assessment.eligible:
            raise RecoveryRefused("Recovery denied: " + assessment.reason)
        report = recover(root, args.task_id)
        print("SUCCESS: task reset to pending; original attempts and last_note preserved")
        print("ARCHIVED WORKTREE:", report["archived_worktree"])
        print("DB BACKUP:", report["sqlite_backup"])
        print("NEXT: python autopilot.py plan (DO NOT automatically launch live work)")
        return 0
    except (RecoveryRefused, sqlite3.Error, OSError, subprocess.TimeoutExpired) as exc:
        print("RECOVERY STOPPED:", exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
