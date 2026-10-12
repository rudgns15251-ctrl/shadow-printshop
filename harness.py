"""Conservative Codex CLI game-development harness, milestone 0.1.

Only explicit --live triggers Codex usage. Human approval is required to cherry-pick.
External Codex authentication, sandbox support, and Windows Git must be validated on user PC.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

from research_validation import validate_research

ROOT = Path(__file__).resolve().parent
TASKS = ROOT / "tasks" / "backlog.json"
DATA = ROOT / ".data" / "state.sqlite3"
WORKTREES = ROOT / ".worktrees"
LOGS = ROOT / "logs"
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,48}$")
STATES = ("pending", "running", "review", "blocked", "completed")


def stamp():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def read_tasks():
    data = json.loads(TASKS.read_text(encoding="utf-8"))
    tasks = data["tasks"]
    ids = set()
    for task in tasks:
        name = task["id"]
        if not ID_RE.fullmatch(name) or name in ids:
            raise ValueError("Invalid or repeated task identifier")
        ids.add(name)
        for prefix in task["allowed_prefixes"]:
            validate_relpath(prefix.rstrip("/"))
        for rel in task["required_files"]:
            validate_relpath(rel)
            if not is_allowed(rel, task["allowed_prefixes"]):
                raise ValueError(f"Required file {rel} not in allowed paths")
    for task in tasks:
        if any(dep not in ids for dep in task["dependencies"]):
            raise ValueError(f"Unresolved task dependency: {task['id']}")
    return tasks


def validate_relpath(name):
    p = Path(name.replace("\\", "/"))
    if not name or p.is_absolute() or ".." in p.parts or ":" in name:
        raise ValueError(f"Unsafe relative path: {name}")
    return p.as_posix()


def is_allowed(name, prefixes):
    rel = validate_relpath(name)
    return any(rel.startswith(prefix.rstrip("/") + "/") for prefix in prefixes)


def db():
    DATA.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DATA)
    conn.execute("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, status TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, workspace TEXT, last_note TEXT, updated TEXT)")
    conn.commit()
    return conn


def initialize():
    tasks = read_tasks()
    with db() as conn:
        for task in tasks:
            conn.execute("INSERT OR IGNORE INTO tasks (id, status, attempts, updated) VALUES (?, 'pending', 0, ?)", (task["id"], stamp()))
    print(f"Initialized {len(tasks)} tasks. State: .data/state.sqlite3")


def run_command(args, cwd=ROOT, timeout=60, stdin=None):
    return subprocess.run(args, cwd=cwd, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding="utf-8", errors="replace", timeout=timeout, check=False)


def git(*args, cwd=ROOT, timeout=60):
    return run_command(["git", *args], cwd=cwd, timeout=timeout)


def require_git_base():
    if not shutil.which("git"):
        raise RuntimeError("Git not found. Install Git for Windows first.")
    if git("rev-parse", "--is-inside-work-tree").returncode != 0:
        raise RuntimeError("No Git repository. Run git init and commit the starter files.")
    if git("rev-parse", "HEAD").returncode != 0:
        raise RuntimeError("No initial commit. Run git add . ; git commit -m 'Initial harness'.")


def doctor():
    print("Tool availability:")
    for tool in ("python", "git", "node", "npm", "codex"):
        found = shutil.which(tool)
        print(f"- {tool:8} {'OK' if found else 'MISSING'}")
    if shutil.which("codex"):
        result = run_command(["codex", "--version"], timeout=20)
        print("Codex:", result.stdout.strip()[:200])
    print("Run scripts/doctor.ps1 in PowerShell for non-sensitive hardware details.")


def status():
    initialize()
    with db() as conn:
        for row in conn.execute("SELECT id, status, attempts, COALESCE(last_note,'') FROM tasks ORDER BY id"):
            print(f"{row[0]:12} {row[1]:10} tries={row[2]} {row[3][:90]}")


def changed_paths(worktree):
    output = git("status", "--porcelain=v1", "-z", "--untracked-files=all", cwd=worktree)
    if output.returncode:
        raise RuntimeError(output.stdout)
    items = output.stdout.split("\0")
    paths = []
    idx = 0
    while idx < len(items) and items[idx]:
        record = items[idx]
        code = record[:2]
        paths.append(record[3:].replace("\\", "/"))
        idx += 1
        if "R" in code or "C" in code:
            paths.append(items[idx].replace("\\", "/"))
            idx += 1
    return paths


def validate_workspace(worktree, task):
    paths = changed_paths(worktree)
    if not paths:
        return False, "Codex did not change any files."
    for rel in paths:
        if not is_allowed(rel, task["allowed_prefixes"]):
            return False, f"Out-of-scope file changed: {rel}"
        path = worktree / rel
        if path.is_symlink():
            return False, f"Symlink not allowed: {rel}"
    for rel in task["required_files"]:
        path = worktree / rel
        if not path.is_file() or path.is_symlink():
            return False, f"Required file missing: {rel}"
        if len(path.read_text(encoding="utf-8")) < task.get("min_file_chars", 1):
            return False, f"Required file too short: {rel}"
    check = git("diff", "--check", cwd=worktree)
    if check.returncode != 0:
        return False, f"git diff --check failed: {check.stdout[:300]}"
    # Refuse worktrees in which the agent created a Git commit instead of a file diff.
    if git("rev-parse", "HEAD", cwd=worktree).stdout.strip() != git("rev-parse", "HEAD").stdout.strip():
        return False, "Unexpected Git commit in worktree."
    return True, f"Allowed paths and required artifacts passed: {', '.join(paths)}"


def build_prompt(task, feedback=""):
    return f"""You are the autonomous indie-game planning/development agent.
TASK: {task['id']} — {task['title']}
INSTRUCTIONS:\n{task['instructions']}
ACCEPTANCE FILES: {json.dumps(task['required_files'], ensure_ascii=False)}
ONLY ALLOWED EDIT PATHS: {json.dumps(task['allowed_prefixes'], ensure_ascii=False)}
No Git commits. Do not weaken tests or approval criteria. Do not fabricate market data.
Provide final short Korean work summary and actual validation performed.
PREVIOUS VALIDATION FAILURE (if any): {feedback or 'none'}
"""


def codex_command_for_task(task, workspace):
    """Enable live Codex search only for explicitly marked research tasks."""
    search = ['--search'] if task.get('web_search') else []
    return ['codex', *search, 'exec', '--sandbox', 'workspace-write',
            '-C', str(workspace), '--json', '-']


def execute(task_id, live):
    initialize()
    tasks = {t["id"]: t for t in read_tasks()}
    task = tasks.get(task_id)
    if task is None:
        raise RuntimeError(f"Unknown task: {task_id}")
    with db() as conn:
        row = conn.execute("SELECT status, attempts FROM tasks WHERE id=?", (task_id,)).fetchone()
        if row[0] != "pending":
            raise RuntimeError(f"Task is {row[0]}; only pending tasks can run.")
        for dep in task["dependencies"]:
            s = conn.execute("SELECT status FROM tasks WHERE id=?", (dep,)).fetchone()
            if s is None or s[0] != "completed":
                raise RuntimeError(f"Blocked by dependency {dep}")
    require_git_base()
    if not live:
        print(f"DRY RUN: {task_id} is ready. Would create an isolated worktree and invoke Codex once.")
        print("Use 'python harness.py run PLAN-001 --live' after logging in to Codex. May consume usage quota.")
        return
    if not shutil.which("codex"):
        raise RuntimeError("Codex CLI missing. Install @openai/codex, run 'codex login'.")
    WORKTREES.mkdir(exist_ok=True)
    LOGS.mkdir(exist_ok=True)
    workspace = WORKTREES / task_id
    if workspace.exists():
        raise RuntimeError(f"Workspace already exists: {workspace}. Inspect before retrying.")
    result = git("worktree", "add", "--detach", str(workspace), "HEAD", timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout)
    with db() as conn:
        conn.execute("UPDATE tasks SET status='running', workspace=?, attempts=attempts+1, updated=? WHERE id=?", (str(workspace), stamp(), task_id))
    log_path = LOGS / f"{task_id}.jsonl.log"
    try:
        prompt = build_prompt(task)
        cmd = codex_command_for_task(task, workspace)
        result = run_command(cmd, cwd=workspace, stdin=prompt, timeout=900)
        log_path.write_text(result.stdout, encoding="utf-8")
        if result.returncode:
            note = f"Codex exited with code {result.returncode}. See {log_path.relative_to(ROOT)}"
            final = "blocked"
        else:
            passed, note = validate_workspace(workspace, task)
            if passed and task.get("research_validation"):
                passed, note = validate_research(workspace, task, result.stdout)
            final = "review" if passed else "blocked"
    except subprocess.TimeoutExpired:
        final = "blocked"
        note = "Codex timed out after 900 seconds. Investigate workspace before retrying."
    except Exception as e:
        final = "blocked"
        note = f"Execution or validation failed: {e}"
    with db() as conn:
        conn.execute("UPDATE tasks SET status=?, last_note=?, updated=? WHERE id=?", (final, note, stamp(), task_id))
    print(f"{task_id}: {final} — {note}")
    print(f"Workspace: {workspace}")
    if final == "review":
        print(f"Inspect: python harness.py inspect {task_id}")
        print(f"If accepted: python harness.py approve {task_id}")
    else:
        print("This starter intentionally does NOT automatically retry or discard failed workspaces.")


def inspect(task_id):
    with db() as conn:
        row = conn.execute("SELECT status, workspace, last_note FROM tasks WHERE id=?", (task_id,)).fetchone()
    if not row or not row[1] or not Path(row[1]).exists():
        raise RuntimeError("No workspace available for this task.")
    ws = Path(row[1])
    print(f"Status: {row[0]} — {row[2]}")
    print(f"Workspace: {ws}")
    print("Changed files:", changed_paths(ws))
    print("Tracked changes:")
    print(git("diff", "--stat", cwd=ws).stdout)
    for task in read_tasks():
        if task["id"] == task_id:
            for rel in task["required_files"]:
                print("Artifact:", ws / rel)


def approve(task_id):
    tasks = {t["id"]: t for t in read_tasks()}
    task = tasks.get(task_id)
    if not task:
        raise RuntimeError("Unknown task")
    with db() as conn:
        row = conn.execute("SELECT status, workspace FROM tasks WHERE id=?", (task_id,)).fetchone()
        if not row or row[0] != "review":
            raise RuntimeError("Task is not in human-review state")
        ws = Path(row[1])
    require_git_base()
    if git("status", "--porcelain").stdout.strip():
        raise RuntimeError("Main repository has uncommitted changes. Commit or clean them first.")
    valid, note = validate_workspace(ws, task)
    if valid and task.get("research_validation"):
        audit_log = LOGS / f"{task_id}.jsonl.log"
        if not audit_log.is_file():
            raise RuntimeError("Research evidence log missing; cannot approve")
        valid, note = validate_research(ws, task, audit_log.read_text(encoding="utf-8"))
    if not valid:
        raise RuntimeError(note)
    changed = changed_paths(ws)
    result = git("add", "--", *changed, cwd=ws)
    if result.returncode:
        raise RuntimeError(result.stdout)
    commit = git("commit", "-m", f"{task_id}: {task['title']}", cwd=ws, timeout=120)
    if commit.returncode:
        raise RuntimeError("Git commit failed. Configure Git name/email if needed. " + commit.stdout)
    commit_id = git("rev-parse", "HEAD", cwd=ws).stdout.strip()
    cherry = git("cherry-pick", commit_id, timeout=120)
    if cherry.returncode:
        raise RuntimeError("Cherry-pick conflict. Main checkout requires manual resolution. " + cherry.stdout)
    with db() as conn:
        conn.execute("UPDATE tasks SET status='completed', last_note=?, updated=? WHERE id=?", ("Human approved and committed", stamp(), task_id))
    print(f"APPROVED {task_id} -> commit {commit_id}")
    print("Worktree is retained for audit. Clean it manually after checking Git worktrees.")


def main():
    parser = argparse.ArgumentParser(description="Conservative autonomous game harness - milestone 0.1")
    sub = parser.add_subparsers(dest="cmd", required=True)
    for command in ("doctor", "init", "status"):
        sub.add_parser(command)
    p = sub.add_parser("run")
    p.add_argument("task_id")
    p.add_argument("--live", action="store_true", help="Actually invoke Codex. May use paid quota.")
    for command in ("inspect", "approve"):
        sp = sub.add_parser(command)
        sp.add_argument("task_id")
    args = parser.parse_args()
    try:
        if args.cmd == "doctor": doctor()
        elif args.cmd == "init": initialize()
        elif args.cmd == "status": status()
        elif args.cmd == "run": execute(args.task_id, args.live)
        elif args.cmd == "inspect": inspect(args.task_id)
        elif args.cmd == "approve": approve(args.task_id)
    except (RuntimeError, ValueError) as exc:
        print("ERROR:", exc, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
