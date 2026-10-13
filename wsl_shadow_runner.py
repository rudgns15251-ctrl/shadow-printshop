"""Run Codex in a WSL-native *throwaway Git repository*, then selectively copy results.

Invoked by the Windows harness, never as a replacement for human approval or QA.
Source is a clean Windows-created detached Git worktree.  Never changes its .git
pointer, SQLite state, or Git history.  Fail closed on path violations, symlinks,
deletions, concurrent source changes, failed Codex calls, or Codex Git commits.
Requires Python 3 and Git in WSL; creates no network connections itself.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

EXCLUDED_NAMES = {'.git', '.godot', '.import', '__pycache__'}
MAX_FILE_BYTES = 256 * 1024 * 1024
MAX_TOTAL_BYTES = 1024 * 1024 * 1024
VALID_ID = re.compile(r'^[A-Za-z0-9_-]{1,48}$')


class GuardError(RuntimeError):
    pass


def file_map(root: Path) -> dict[str, str]:
    """List and hash regular files (even Git-ignored files). Never follow symlinks."""
    files = {}
    total = 0
    def visit(folder: Path, parts: tuple[str, ...] = ()):
        nonlocal total
        for child in folder.iterdir():
            if child.name in EXCLUDED_NAMES:
                continue
            rel = parts + (child.name,)
            if child.is_symlink():
                raise GuardError('Symlink in workspace: ' + '/'.join(rel))
            if child.is_dir():
                visit(child, rel)
            elif child.is_file():
                size = child.stat().st_size
                total += size
                if size > MAX_FILE_BYTES or total > MAX_TOTAL_BYTES:
                    raise GuardError('Workspace too large to mirror safely')
                digest = hashlib.sha256()
                with child.open('rb') as stream:
                    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                        digest.update(chunk)
                files['/'.join(rel)] = digest.hexdigest()
            else:
                raise GuardError('Unsupported file type: ' + '/'.join(rel))
    visit(root)
    return files


def guarded_relpath(value: str) -> str:
    if (not value or '\\' in value or ':' in value or value.startswith('/')
            or any(p in ('', '.', '..') for p in value.split('/'))):
        raise GuardError('Unsafe relative path: ' + repr(value))
    return value


def load_policy(source: Path) -> tuple[list[str], set[str]]:
    task_id = source.name
    if not VALID_ID.fullmatch(task_id) or source.parent.name != '.worktrees':
        raise GuardError('Source must be a named .worktrees/<task-id> directory')
    manifest = source.parent.parent / 'tasks' / 'backlog.json'
    tasks = json.loads(manifest.read_text(encoding='utf-8'))['tasks']
    task = next((t for t in tasks if t.get('id') == task_id), None)
    if not task:
        raise GuardError('No matching task in backlog: ' + task_id)
    allowed = [guarded_relpath(p.rstrip('/')) + '/' for p in task['allowed_prefixes']]
    protected = {guarded_relpath(p) for p in task.get('protected_files', [])}
    if not allowed:
        raise GuardError('Empty allowlist')
    return allowed, protected


def ensure_git_clean(source: Path):
    """Windows Git is authoritative; status is supplied by the Windows harness.

    Git inside WSL must NOT stage or modify the Windows repository: only inspect
    the native shadow copy. Recheck all source hashes before synchronizing.
    """
    if not (source / '.git').is_file():
        raise GuardError('Expected Windows linked worktree .git pointer')


def copy_source(source: Path, target: Path):
    def ignore(path, entries):
        return EXCLUDED_NAMES.intersection(entries)
    # source was scanned beforehand; file_map detects and refuses symlinks.
    shutil.copytree(source, target, ignore=ignore)


def git(*args, cwd: Path) -> str:
    result = subprocess.run(['git', '-C', str(cwd), *args], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding='utf-8',
                            errors='replace', timeout=120)
    if result.returncode:
        raise GuardError('Native Git failed: ' + result.stdout[-500:])
    return result.stdout.strip()


def init_shadow_git(stage: Path) -> str:
    git('init', '-q', cwd=stage)
    git('config', 'core.autocrlf', 'false', cwd=stage)
    git('add', '-A', cwd=stage)
    git('-c', 'user.name=Harness Temporary Baseline',
        '-c', 'user.email=local-harness@invalid', 'commit', '-qm',
        'Temporary WSL snapshot; never transfer Git history', cwd=stage)
    return git('rev-parse', 'HEAD', cwd=stage)


def changed_files(original: dict, updated: dict) -> list[str]:
    return sorted(p for p in original.keys() | updated.keys() if original.get(p) != updated.get(p))


def validate_result(before: dict, after: dict, allow: list[str], protected: set[str]):
    changed = changed_files(before, after)
    deleted = [p for p in changed if p not in after]
    if deleted:
        raise GuardError('Deleting existing files is not permitted in shadow mode: ' + ', '.join(deleted[:3]))
    for p in changed:
        guarded_relpath(p)
        if p in protected:
            raise GuardError('Protected file changed: ' + p)
        if not any(p.startswith(prefix) for prefix in allow):
            raise GuardError('Out-of-scope file changed: ' + p)
    return changed


def verify_source(source: Path, before: dict):
    current = file_map(source)
    if current != before:
        raise GuardError('Source worktree changed during Codex execution; nothing copied')


def sync_files(source: Path, stage: Path, changed: list[str], before: dict, after: dict, lease_guard=None):
    """Copy only validated paths. Keep stage on any failure for manual recovery."""
    # Stage all output as temporary sibling files BEFORE replacing any originals.
    pending: list[tuple[Path, Path, bytes | None]] = []
    applied: list[tuple[Path, bytes | None]] = []
    token = uuid.uuid4().hex
    try:
        for p in changed:
            dest = source / p
            if dest.is_symlink() or any(q.is_symlink() for q in dest.parents if q != source.parent):
                raise GuardError('Symlink in destination path: ' + p)
            dest.parent.mkdir(parents=True, exist_ok=True)
            prior = dest.read_bytes() if dest.exists() else None
            temp = dest.with_name('.' + dest.name + '.harness-stage-' + token)
            with (stage / p).open('rb') as src, temp.open('xb') as dst:
                shutil.copyfileobj(src, dst)
            if hashlib.sha256(temp.read_bytes()).hexdigest() != after[p]:
                raise GuardError('Copied file does not match staged content: ' + p)
            pending.append((temp, dest, prior))
        for temp, dest, prior in pending:
            if lease_guard is not None:
                lease_guard()
            os.replace(temp, dest)
            applied.append((dest, prior))
    except Exception:
        # Best effort restore; don't hide an underlying I/O or permission failure.
        for dest, prior in reversed(applied):
            try:
                if prior is None:
                    dest.unlink(missing_ok=True)
                else:
                    dest.write_bytes(prior)
            except OSError as e:
                print('WARNING: manual restore required for ' + str(dest) + ': ' + str(e), file=sys.stderr)
        raise
    finally:
        for temp, _, _ in pending:
            temp.unlink(missing_ok=True)


def acquire_lease(lock_path: Path | None):
    """Verify the parent autopilot still owns this run before ANY file sync.

    This protects against Windows timing out/killing wsl.exe while an orphaned
    Linux Codex process is still finishing in the background.
    """
    if lock_path is None:
        return lambda: None  # Isolated unit tests and explicit standalone calls.
    try:
        raw = lock_path.read_bytes()
        data = json.loads(raw)
    except (OSError, ValueError) as e:
        raise GuardError('Autopilot worker lease missing or unreadable: ' + str(e))
    if not isinstance(data.get('pid'), int) or data['pid'] <= 0 or data.get('purpose') != 'autopilot run' or not data.get('started_at'):
        raise GuardError('Invalid autopilot worker lease')
    def check():
        try:
            if lock_path.read_bytes() != raw:
                raise GuardError('Autopilot worker lease replaced; refusing file sync')
        except OSError as e:
            raise GuardError('Autopilot worker lease no longer exists: ' + str(e))
    return check


def run(source: Path, cli: str, cli_args: list[str], prompt: str, *, stage_root: Path | None = None, lock_path: Path | None = None) -> int:
    source = source.resolve(strict=True)
    if not source.is_dir():
        raise GuardError('Source is not a directory')
    if cli_args and cli_args[0] == '--':
        cli_args = cli_args[1:]
    if cli_args.count('-C') != 1 or 'exec' not in cli_args:
        raise GuardError('Expected Codex exec with exactly one -C')
    pos = cli_args.index('-C') + 1
    if pos >= len(cli_args) or Path(cli_args[pos]).resolve() != source:
        raise GuardError('Codex -C must be the source worktree')
    if '--sandbox' not in cli_args or cli_args[cli_args.index('--sandbox') + 1] != 'workspace-write':
        raise GuardError('workspace-write sandbox required')
    allow, protected = load_policy(source)
    lease_guard = acquire_lease(lock_path)
    ensure_git_clean(source)
    before = file_map(source)
    if stage_root is None:
        stage_root = Path.home() / '.cache' / 'game-harness-shadow'
    stage_root.mkdir(parents=True, exist_ok=True)
    if source == stage_root or stage_root.is_relative_to(source):
        raise GuardError('Shadow directory must be outside source')
    stage = Path(tempfile.mkdtemp(prefix=source.name + '-', dir=stage_root))
    print('SHADOW_STAGE=' + str(stage), flush=True)
    complete = False
    try:
        workspace = stage / 'workspace'
        copy_source(source, workspace)
        if file_map(workspace) != before:
            raise GuardError('Shadow copy differs from source')
        base = init_shadow_git(workspace)
        actual_args = cli_args[:]
        actual_args[pos] = str(workspace)
        child_env = os.environ.copy()
        child_env.pop('GIT_DIR', None)
        child_env.pop('GIT_WORK_TREE', None)
        child = subprocess.run([cli, *actual_args], input=prompt,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               encoding='utf-8', errors='replace', check=False,
                               env=child_env, cwd=workspace)
        print(child.stdout, end='' if child.stdout.endswith('\n') else '\n', flush=True)
        if child.returncode:
            raise GuardError(f'Codex exited with code {child.returncode}; shadow kept')
        if git('rev-parse', 'HEAD', cwd=workspace) != base:
            raise GuardError('Codex created Git commit; shadow kept')
        after = file_map(workspace)
        changes = validate_result(before, after, allow, protected)
        verify_source(source, before)
        lease_guard()
        sync_files(source, workspace, changes, before, after, lease_guard)
        print(f'SHADOW_SYNC_OK count={len(changes)}', flush=True)
        complete = True
        return 0
    finally:
        if complete:
            shutil.rmtree(stage)
        else:
            print('SHADOW_PRESERVED=' + str(stage), file=sys.stderr, flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True)
    parser.add_argument('--cli', required=True)
    parser.add_argument('--lock', required=True)
    parser.add_argument('codex_args', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    try:
        return run(Path(args.source), args.cli, args.codex_args, sys.stdin.read(), lock_path=Path(args.lock))
    except (GuardError, OSError, ValueError, json.JSONDecodeError, subprocess.TimeoutExpired) as e:
        print('SHADOW_ERROR: ' + str(e), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
