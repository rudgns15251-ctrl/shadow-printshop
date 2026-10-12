"""Game Harness v0.2: bounded, single-worker scheduler for existing v0.1 tasks.

Uses the existing harness.py for Codex execution/validation and human approval.
Does NOT automatically approve plans, write new tasks, search the web or ship games.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

import harness
import v07c_controller  # HARNESS_V07C_CONTROL_INTEGRATION

ROOT = Path(__file__).resolve().parent
LOCK = ROOT / '.data' / 'autopilot.lock'
REPORTS = ROOT / 'logs' / 'autopilot'
DEFAULT_POLL = 5


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')


def pid_alive(pid: int) -> bool:
    if not isinstance(pid, int) or pid <= 0:
        return False
    if os.name == 'nt':
        import ctypes
        from ctypes import wintypes
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if handle:
            kernel32.CloseHandle(handle)
            return True
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def current_lock():
    if not LOCK.exists():
        return None
    try:
        return json.loads(LOCK.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {'pid': None, 'note': 'Unreadable lock: manual inspection required'}


class SingleWorker:
    def __enter__(self):
        LOCK.parent.mkdir(parents=True, exist_ok=True)
        payload = {'pid': os.getpid(), 'started_at': now(), 'purpose': 'autopilot run'}
        try:
            fd = os.open(str(LOCK), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            other = current_lock()
            raise RuntimeError(f'Another worker or stale lock exists: {other}. Do not delete until confirmed safe.')
        with os.fdopen(fd, 'w', encoding='utf-8') as file:
            json.dump(payload, file)
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        # Never delete a lock written by another process.
        data = current_lock()
        if data and data.get('pid') == os.getpid():
            try:
                LOCK.unlink()
            except FileNotFoundError:
                pass


def snapshot():
    harness.initialize()
    tasks = harness.read_tasks()
    with harness.db() as conn:
        db_rows = {row[0]: {'status': row[1], 'attempts': row[2], 'note': row[3] or ''}
                   for row in conn.execute('SELECT id,status,attempts,last_note FROM tasks')}
    return tasks, db_rows


def ready_tasks(tasks, statuses):
    ready = [t for t in tasks if statuses[t['id']]['status'] == 'pending' and
             all(statuses[d]['status'] == 'completed' for d in t['dependencies'])]
    return sorted(ready, key=lambda t: (-int(t.get('priority', 0)), t['id']))


def show_plan():
    tasks, statuses = snapshot()
    active = current_lock()
    if active:
        print(f'WORKER LOCK: {active}; running={pid_alive(active.get("pid"))}')
    for t in tasks:
        state = statuses[t['id']]
        ready = t in ready_tasks(tasks, statuses)
        print(f'{t["id"]:12} {state["status"]:10} attempts={state["attempts"]} '
              f'{"READY" if ready else ""} {state["note"][:90]}')
    ordered = ready_tasks(tasks, statuses)
    print('NEXT:', ordered[0]['id'] if ordered else 'No runnable task. Approval or new manifest tasks needed.')
    for t in tasks:
        if statuses[t['id']]['status'] == 'running':
            print('WARNING: stale or active running task:', t['id'],
                  '- never automatically clear it without checking workspace and processes.')


def safe_retry_if_clean(task_id: str) -> bool:
    """Retry only an ended task with no output. Never reset uncertain work."""
    tasks = {t['id']: t for t in harness.read_tasks()}
    if task_id not in tasks:
        return False
    with harness.db() as conn:
        row = conn.execute('SELECT status,workspace,last_note FROM tasks WHERE id=?', (task_id,)).fetchone()
    if not row or row[0] != 'blocked' or not row[1]:
        return False
    note = row[2] or ''
    if not note.startswith('Codex exited with code '):
        print('No retry: failure is not a clean Codex exit. Manual inspection required.')
        return False
    workspace = Path(row[1]).resolve()
    worktrees_root = harness.WORKTREES.resolve()
    if workspace.parent != worktrees_root or workspace.name != task_id or not workspace.is_dir():
        print('No retry: unexpected worktree location.')
        return False
    if harness.changed_paths(workspace):
        print('No retry: task has generated or modified files to preserve.')
        return False
    # Do not touch a workspace with agent commits.
    if harness.git('rev-parse', 'HEAD', cwd=workspace).stdout.strip() != harness.git('rev-parse', 'HEAD').stdout.strip():
        print('No retry: worktree HEAD differs from main.')
        return False
    removal = harness.git('worktree', 'remove', str(workspace), timeout=120)
    if removal.returncode != 0:
        print('No retry: Git did not safely remove clean worktree:', removal.stdout)
        return False
    with harness.db() as conn:
        conn.execute('UPDATE tasks SET status=?,workspace=NULL,last_note=?,updated=? WHERE id=? AND status=?',
                     ('pending', 'v0.2 clean-exit auto-retry; previous Codex call ended without changes',
                      harness.stamp(), task_id, 'blocked'))
    return True


def call_harness(task_id: str, timeout: int):
    REPORTS.mkdir(parents=True, exist_ok=True)
    log_path = REPORTS / f'{task_id}-{int(time.time())}.log'
    cmd = [sys.executable, str(ROOT / 'harness.py'), 'run', task_id, '--live']
    print(f'START {task_id}; local log: {log_path.relative_to(ROOT)}', flush=True)
    with log_path.open('w', encoding='utf-8', errors='replace') as log:
        child_env = os.environ.copy()
        child_env['PYTHONIOENCODING'] = 'utf-8'
        child_env['PYTHONUTF8'] = '1'
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, env=child_env)
        start = time.monotonic()
        warned = False
        last_heartbeat = 0
        while proc.poll() is None:
            elapsed = int(time.monotonic()-start)
            if elapsed >= timeout and not warned:
                # Never abandon a live child while releasing the single-worker lock.
                # Existing harness has its own 900s execution timeout.
                print(f'WARNING: task exceeded soft deadline ({timeout}s).', flush=True)
                print('Waiting for existing harness to stop safely; no new tasks will be started.', flush=True)
                warned = True
            if elapsed - last_heartbeat >= 30:
                print(f'  {task_id} still executing ({elapsed}s); log: {log_path.name}', flush=True)
                last_heartbeat = elapsed
            time.sleep(DEFAULT_POLL)
        code = proc.wait()
    return code, log_path



# HARNESS_V07A_PREFLIGHT_INTEGRATION
def enforce_v07a_preflight():
    """Fail closed on FAIL/WARN before a live Codex task is dispatched."""
    import doctor_v07a

    distro = os.environ.get("GAME_HARNESS_WSL_DISTRO", "Ubuntu")
    codex_path = os.environ.get("GAME_HARNESS_WSL_CODEX", "/home/newsjw/.local/bin/codex")
    checks = doctor_v07a.preflight(ROOT, distro=distro, codex_path=codex_path)
    if len(checks) != 8:
        raise RuntimeError(f"v0.7-A: Expected 8 checks, received {len(checks)}; refusing live execution")
    for check in checks:
        print(f"[PREFLIGHT {check.status}] {check.name}: {check.detail}", flush=True)
    problems = [f"{check.name}={check.status}" for check in checks if check.status != "PASS"]
    if problems:
        raise RuntimeError("v0.7-A preflight stopped live work: " + ", ".join(problems))
    print("v0.7-A PREFLIGHT PASS (8/8).", flush=True)
    return checks


def run_worker(live: bool, max_tasks: int, max_minutes: int, retries: int, task_timeout: int, continue_after_review: bool = False):
    if not live:
        print('DRY RUN - no Codex usage or writes beyond state initialization.')
        show_plan()
        print('Use: .\\.venv\\Scripts\\python.exe autopilot.py run --live --max-tasks 2 --minutes 45')
        return
    harness.require_git_base()
    if harness.git('status', '--porcelain').stdout.strip():
        raise RuntimeError('Main Git checkout is not clean. Do not run autonomous work until reviewed/committed.')
    if not harness.shutil.which('codex'):
        raise RuntimeError('Codex CLI not on PATH.')
    start = time.monotonic()
    handled = 0
    with SingleWorker():
        # Soft-stop requests are scoped to the exact worker PID and start token.
        worker_lock = current_lock()
        if v07c_controller.stop_path(ROOT).exists():
            raise RuntimeError('An unresolved stop request exists; inspect via controller-status')
        report = v07c_controller.RunReport(ROOT, max_tasks=max_tasks, minutes=max_minutes,
                                             max_retries=retries, continue_after_review=continue_after_review)
        preflight_done = False
        try:
            while handled < max_tasks and time.monotonic()-start < max_minutes*60:
                if v07c_controller.is_stop_requested(ROOT, worker_lock):
                    print('PAUSED: stop requested; no new task started.', flush=True)
                    break
                tasks, statuses = snapshot()
                # Unresolved running jobs must be reviewed, not silently duplicated.
                in_flight = [t['id'] for t in tasks if statuses[t['id']]['status'] == 'running']
                if in_flight:
                    print('PAUSED: task(s) marked running:', ', '.join(in_flight),
                          '- investigate before restarting.')
                    break
                ready = ready_tasks(tasks, statuses)
                if not ready:
                    print('No more runnable tasks. Review/approve outputs or add tasks.')
                    break
                task = ready[0]
                task_id = task['id']
                remaining = int(max_minutes*60-(time.monotonic()-start))
                if remaining < 15:
                    print('Time budget reached. Stopping before next task.')
                    break
                per_attempt = min(task_timeout, remaining)
                if not preflight_done:
                    enforce_v07a_preflight()
                    preflight_done = True
                attempts = 0
                while True:
                    # Parent harness has its own 900s timeout; leave some margin for its cleanup.
                    returncode, log_path = call_harness(task_id, per_attempt)
                    with harness.db() as conn:
                        state = conn.execute('SELECT status,last_note FROM tasks WHERE id=?',(task_id,)).fetchone()
                    print(f'FINISHED {task_id}: CLI exit={returncode}, state={state[0]}, note={state[1]}')
                    report.record(task_id, returncode, state[0], state[1], log_path)
                    # HARNESS_V07B_SAFE_RECOVERY_INTEGRATION
                    if state[0] == 'blocked':
                        try:
                            import v07b_recovery
                            assessment = v07b_recovery.assess(ROOT, task_id)
                            print(f'v0.7-B TRIAGE: {assessment.category}; eligible={assessment.eligible}; {assessment.reason}')
                            print(f'Inspect: python autopilot.py triage {task_id}')
                        except Exception as triage_error:
                            print(f'v0.7-B TRIAGE UNAVAILABLE: {triage_error}; manual investigation required')
                    if (state[0] == 'blocked' and attempts < retries
                            and not v07c_controller.is_stop_requested(ROOT, worker_lock)
                            and safe_retry_if_clean(task_id)):
                        attempts += 1
                        print(f'Retrying {task_id} ({attempts}/{retries}) after clean Codex exit...')
                        continue
                    break
                handled += 1
                if state[0] == 'review':
                    print(f'REVIEW REQUIRED: {task_id} was not merged or approved automatically.')
                    if not continue_after_review:
                        print('PAUSED: human review required; further tasks await explicit next run.')
                        break
                elif state[0] != 'review' and state[0] != 'completed':
                    print(f'Attention required: {task_id} state={state[0]}, see {log_path}')
                if harness.git('status', '--porcelain').stdout.strip():
                    print('PAUSED: main Git checkout changed during execution.')
                    break
        finally:
            try:
                outcome = 'interrupted' if sys.exc_info()[0] else ('stopped' if v07c_controller.is_stop_requested(ROOT, worker_lock) else 'completed')
                report_file = report.finish(outcome)
                print('v0.7-C report:', report_file, flush=True)
            finally:
                v07c_controller.clear_own_stop(ROOT, worker_lock)
    print(f'Worker stopped. Tasks attempted: {handled}. Run autopilot.py plan to see next actions.')


def main(argv=None):
    parser = argparse.ArgumentParser(description='Game Harness v0.2 — bounded single-worker task scheduler')
    sub = parser.add_subparsers(dest='cmd', required=True)
    sub.add_parser('plan', help='Read-only report and next-task plan')
    sub.add_parser('preflight', help='Run v0.7-A read-only checks before live execution')
    sub.add_parser('controller-status', help='Read-only worker and last-run report')
    sub.add_parser('stop', help='Request a cooperative stop AFTER the current task')
    triage = sub.add_parser('triage', help='Read-only diagnosis of a task')
    triage.add_argument('task_id')
    recover = sub.add_parser('recover', help='Explicit approval-gated blocked task recovery')
    recover.add_argument('task_id')
    recovery_mode = recover.add_mutually_exclusive_group()
    recovery_mode.add_argument('--check', action='store_true', help='Read-only recovery eligibility')
    recovery_mode.add_argument('--apply', action='store_true', help='Back up and restore only an eligible task')
    p = sub.add_parser('run', help='Run ready tasks, stopping at configured limits')
    p.add_argument('--live', action='store_true', help='Actually invoke Codex; consumes quota')
    p.add_argument('--max-tasks', type=int, default=2)
    p.add_argument('--minutes', type=int, default=45)
    p.add_argument('--max-retries', type=int, default=0)  # v0.7-B: explicit opt-in required for legacy clean-exit retry
    p.add_argument('--task-timeout', type=int, default=930)
    p.add_argument('--continue-after-review', action='store_true', help='Opt in to additional independent ready tasks, never auto-approve')
    args = parser.parse_args(argv)
    try:
        if args.cmd == 'plan':
            show_plan()
        elif args.cmd == 'preflight':
            enforce_v07a_preflight()
        elif args.cmd == 'controller-status':
            v07c_controller.status(ROOT, current_lock())
        elif args.cmd == 'stop':
            result = v07c_controller.request_stop(ROOT, current_lock(), pid_alive)
            print(f'v0.7-C STOP {result}: active child is allowed to finish')
        elif args.cmd == 'triage':
            import v07b_recovery
            return v07b_recovery.main(['triage', args.task_id], root=ROOT)
        elif args.cmd == 'recover':
            import v07b_recovery
            selection = '--apply' if args.apply else '--check'
            return v07b_recovery.main(['recover', args.task_id, selection], root=ROOT)
        else:
            if not (1 <= args.max_tasks <= 10 and 1 <= args.minutes <= 240 and 0 <= args.max_retries <= 2
                    and 30 <= args.task_timeout <= 1200):
                raise ValueError('Unsafe limit: max-tasks=1..10, minutes=1..240, retries=0..2, task-timeout=30..1200')
            run_worker(args.live, args.max_tasks, args.minutes, args.max_retries, args.task_timeout,
                       continue_after_review=args.continue_after_review)
    except (ValueError, RuntimeError, OSError, sqlite3.Error) as exc:
        print('ERROR:', exc, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
