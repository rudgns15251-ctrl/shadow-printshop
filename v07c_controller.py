#!/usr/bin/env python3
"""v0.7-C bounded-run control: advisory stop and audit-only session reports.

No Codex invocation, Git changes, SQLite writes, approvals or worktree removal.
Stop is cooperative: never interrupts a running child.
"""
from __future__ import annotations

import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import uuid

STOP_NAME = 'autopilot.stop.json'


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds')


def stop_path(root):
    return Path(root) / '.data' / STOP_NAME


def _read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding='utf-8'))
    except (ValueError, OSError):
        return None


def same_worker(lock, request):
    return (isinstance(lock, dict) and isinstance(request, dict)
            and isinstance(lock.get('pid'), int)
            and isinstance(lock.get('started_at'), str)
            and bool(lock['started_at'])
            and request.get('pid') == lock['pid']
            and request.get('started_at') == lock['started_at'])


def request_stop(root, lock, pid_alive):
    """Request stop between tasks. Does not kill the active child."""
    if not isinstance(lock, dict) or not isinstance(lock.get('pid'), int) or not pid_alive(lock['pid']):
        raise RuntimeError('No verified running worker; stop not requested')
    if not lock.get('started_at'):
        raise RuntimeError('Worker lock lacks started_at; cannot bind stop request')
    path = stop_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = { 'pid': lock['pid'], 'started_at': lock['started_at'], 'requested_at': utc_now() }
    try:
        fd = os.open(str(path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        previous = _read_json(path)
        if same_worker(lock, previous):
            return 'ALREADY_REQUESTED'
        raise RuntimeError('Unknown or stale stop request exists. Inspect it before proceeding')
    with os.fdopen(fd, 'w', encoding='utf-8') as stream:
        json.dump(payload, stream)
    return 'REQUESTED'


def is_stop_requested(root, lock):
    return same_worker(lock, _read_json(stop_path(root)))


def clear_own_stop(root, lock):
    path = stop_path(root)
    if is_stop_requested(root, lock):
        path.unlink(missing_ok=True)
        return True
    return False


def _write_json_atomic(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=str(path.parent), prefix='.' + path.name + '-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


class RunReport:
    def __init__(self, root, *, max_tasks, minutes, max_retries, continue_after_review):
        self.root = Path(root)
        self.started = utc_now()
        self.run_id = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8]
        self.limits = {'max_tasks': max_tasks, 'minutes': minutes,
                       'max_retries': max_retries, 'continue_after_review': continue_after_review}
        self.attempts = []
        self.finished = False
        self.path = self.root / 'logs' / 'controller' / (self.run_id + '.json')

    def record(self, task_id, exit_code, status, note, log_path):
        log = Path(log_path)
        # Include only bounded metadata, never raw agent output or secrets.
        self.attempts.append({
            'task_id': str(task_id)[:48], 'exit_code': int(exit_code),
            'state': str(status)[:32], 'note': str(note or '')[:500],
            'log': str(log.name)[:200], 'finished_utc': utc_now()
        })

    def finish(self, outcome):
        if self.finished:
            return self.path
        self.finished = True
        payload = {'version': '0.7-C', 'id': self.run_id, 'started_utc': self.started,
                   'finished_utc': utc_now(), 'outcome': str(outcome)[:64],
                   'limits': self.limits, 'attempts': self.attempts,
                   'human_approval_required': True}
        _write_json_atomic(self.path, payload)
        return self.path


def status(root, lock):
    root = Path(root)
    stop = _read_json(stop_path(root))
    folder = root / 'logs' / 'controller'
    reports = sorted(folder.glob('*.json'), key=lambda p: p.name, reverse=True) if folder.is_dir() else []
    print('Worker lock:', lock if lock is not None else 'none')
    print('Stop request:', 'for current worker' if same_worker(lock, stop) else ('stale/unknown' if stop is not None or stop_path(root).exists() else 'none'))
    if reports:
        print('Latest report:', reports[0])
        summary = _read_json(reports[0])
        if summary:
            print('Last run outcome:', summary.get('outcome'), 'attempts:', len(summary.get('attempts', [])))
    else:
        print('Latest report: none')
