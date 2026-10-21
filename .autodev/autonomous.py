"""Durable, bounded coordinator layered on the existing AutoDev game runner.

Policy and QA are trusted local code. Model output supplies proposals and game
edits only. Snapshots are isolation from accidental edits, not a hostile-code VM.
"""
from __future__ import annotations
import argparse
import contextlib
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import subprocess
import sys
import time
import uuid

import auto

ROOT = auto.ROOT
HERE = auto.HERE
STATE = HERE / 'state'
PLAN = STATE / 'plan.json'
LOCK = STATE / 'worker.lock'
PAUSE = STATE / 'pause.json'
ERROR = auto.StopRun
require = auto.require
# A trusted production coordinator can require an independent review before integration.
# Ordinary CLI tasks retain their existing behavior when no reviewer is installed.
TASK_REVIEWER = None
FULL_GATES = ('STATIC', 'IMPORT', 'SMOKE', 'REGRESSION', 'SLICE', 'OFFLINE', 'QUALITY', 'EXPORT', 'BUILD_RUN')
ACCEPTANCE_PROBES = {'context_tooltips': ('context_tooltips.gd', 'TOOLTIP_ACCEPTANCE_PASS'),
                     'save_settings': ('save_settings.gd', 'SAVE_SETTINGS_PASS'),
                     'audio_immediate': ('../audio_lab/original_immediate.gd', 'RAPID_SFX_IMMEDIATE_EXIT'),
                     'story_orders': ('story_orders.gd', 'STORY_ORDERS_PASS'),
                     'story_archive': ('story_archive.gd', 'STORY_ARCHIVE_PASS'),
                     'story_archive_extended': ('story_archive_extended.gd', 'ARCHIVE_EXTENDED_PASS'),
                     'campaign_shell': ('campaign_shell.gd', 'CAMPAIGN_SHELL_PASS'),
                     'campaign_recovery': ('campaign_recovery.gd', 'CAMPAIGN_RECOVERY_PASS'),
                     'campaign_hints': ('campaign_hints.gd', 'CAMPAIGN_HINT_PASS'),
                     'campaign_full': ('campaign_full.gd', 'CAMPAIGN_FULL_PASS'),
                     'sound_content': ('sound_content.gd', 'SOUND_CONTENT_PASS'),
                     'release_candidate': ('release_candidate.gd', 'RELEASE_CANDIDATE_PASS'),
                     # S07 release polish, written test-first by the Claude Code operator.
                     'modal_motion': ('modal_motion.gd', 'MODAL_MOTION_PASS'),
                     'campaign_titles': ('campaign_titles.gd', 'CAMPAIGN_TITLES_PASS'),
                     'chapter_transition': ('chapter_transition.gd', 'CHAPTER_TRANSITION_PASS'),
                     'asset_licenses': ('asset_licenses.gd', 'ASSET_LICENSES_PASS'),
                     # S08 product identity and keyboard dialog reading.
                     'product_identity': ('product_identity.gd', 'PRODUCT_IDENTITY_PASS'),
                     'dialog_scroll': ('dialog_scroll.gd', 'DIALOG_SCROLL_PASS'),
                     'window_icon': ('window_icon.gd', 'WINDOW_ICON_PASS'),
                     'transition_sections': ('transition_sections.gd', 'TRANSITION_SECTIONS_PASS'),
                     # S09 visual foundation (second production pass).
                     'fonts_theme': ('fonts_theme.gd', 'FONTS_THEME_PASS'),
                     'night_atmosphere': ('night_atmosphere.gd', 'NIGHT_ATMOSPHERE_PASS'),
                     'title_screen': ('title_screen.gd', 'TITLE_SCREEN_PASS'),
                     # S10 workbench UI.
                     'player_labels': ('player_labels.gd', 'PLAYER_LABELS_PASS'),
                     'workbench_layout': ('workbench_layout.gd', 'WORKBENCH_LAYOUT_PASS'),
                     # S11 story scenes.
                     'story_stage': ('story_stage.gd', 'STORY_STAGE_PASS'),
                     'story_portraits': ('story_portraits.gd', 'STORY_PORTRAITS_PASS'),
                     'scene_backgrounds': ('scene_backgrounds.gd', 'SCENE_BACKGROUNDS_PASS'),
                     'scene_motion': ('scene_motion.gd', 'SCENE_MOTION_PASS')}
TASK_ID = '^[a-z][a-z0-9_-]{2,60}$'
MODEL_ERRORS = re.compile(r'(?im)(?:usage limit|quota exceeded|rate.limit|not authenticated|unauthorized|401\b|403\b|insufficient credits)')

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp')
    with temporary.open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    # Windows readers/antivirus may briefly hold the destination without delete sharing.
    # Retry only the atomic replacement, never regenerate content or weaken a QA verdict.
    deadline = time.monotonic() + 2.0
    while True:
        try:
            os.replace(temporary, path)
            break
        except PermissionError as exc:
            if getattr(exc, 'winerror', None) not in {5, 32, 33} or time.monotonic() >= deadline:
                raise  # Preserve the unique temporary file as failure evidence.
            time.sleep(0.025)

def git(*args, cwd=None, env=None):
    p = subprocess.run(['git', '-C', str(cwd or ROOT), *args], capture_output=True,
                       encoding='utf-8', errors='replace', timeout=90, env=env)
    # Never include command arguments or remote diagnostics containing credentials.
    require(p.returncode == 0, 'GIT_FAILURE: ' + args[0])
    return p.stdout.strip()

def safe_rel(value):
    require(isinstance(value, str) and value and '\\' not in value, 'Invalid relative path')
    posix = PurePosixPath(value)
    require(not posix.is_absolute() and not PureWindowsPath(value).drive and
            all(p not in ('', '.', '..') for p in value.split('/')) and
            not any(c in value for c in ':*?[]\x00\r\n'), 'Unsafe path: ' + repr(value))
    return value

def linked(path):
    return path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction())

def inside(root, relative):
    safe_rel(relative)
    require(not linked(root), 'Linked root refused')
    dest = root / relative
    for item in (dest, *dest.parents):
        if item == root.parent:
            break
        require(not linked(item), 'Symlink/junction refused')
    require(dest.resolve().is_relative_to(root.resolve()), 'Path escape refused')
    return dest

def snapshot(root):
    require(root.is_dir() and not linked(root), 'Missing or linked snapshot')
    out = {}
    # Walk explicitly: never traverse junctions or symlinks before detecting them.
    def visit(folder):
        for p in sorted(folder.iterdir()):
            require(not linked(p), 'Symlink/junction refused: ' + p.name)
            if p.name in {'.git', '.godot', '__pycache__'} and p.is_dir():
                continue
            if p.is_dir():
                visit(p)
            elif p.is_file():
                out[p.relative_to(root).as_posix()] = auto.sha(p)
    visit(root)
    return out

def checked_changes(before, after, task, policy):
    changes = auto.diff(before, after)
    allowed = set(task['allowed'])
    require(allowed <= set(policy['approved_game_files']), 'Task exceeds trusted policy')
    for rel in changes:
        require(rel in allowed and rel in policy['approved_game_files'], 'SCOPE: ' + rel)
        require(rel in after, 'Deletion forbidden: ' + rel)
    return changes

def run_changes(data, current, task, p):
    baseline = dict(data['baseline'])
    for rel, digest in data.get('trusted_import_metadata', {}).items():
        generated_new = rel in data.get('trusted_new_import_metadata', [])
        require((rel.endswith('.import') or (generated_new and rel.endswith('.uid'))) and
                (rel in baseline or generated_new) and current.get(rel) == digest,
                'SCOPE: trusted import metadata changed: ' + rel)
        if not generated_new:
            baseline[rel] = digest
    return checked_changes(baseline, current, task, p)

def record_import_metadata(stage, before, data, process_record, approved_new=()):
    current = snapshot(stage)
    changes = auto.diff(before, current)
    allowed_new=set(approved_new)
    new=[rel for rel in changes if rel not in before]
    require(all(rel in current and ((rel.endswith('.import') and rel in before) or
                (rel not in before and rel in allowed_new and rel.endswith(('.import','.uid')))) for rel in changes),
            'SCOPE: trusted importer changed substantive content')
    if changes:
        data.setdefault('trusted_new_import_metadata', []).extend(rel for rel in new if rel not in data.get('trusted_new_import_metadata', []))
        data.setdefault('trusted_import_metadata', {}).update({rel: current[rel] for rel in changes})
        data.setdefault('import_metadata_history', []).append({
            'time': now(), 'process_log': process_record.get('log'), 'log_sha256': process_record.get('sha256'),
            'before': {rel: before.get(rel) for rel in changes}, 'after': {rel: current[rel] for rel in changes}})

def probes(task, c):
    names = list(dict.fromkeys(task.get('acceptance_probes', []) + c.get('trusted_handoff_probes', []) +
                               c.get('recovery_probes', {}).get(task['id'], [])))
    require(set(names) <= set(ACCEPTANCE_PROBES), 'Unknown trusted acceptance probe')
    return names

def handoff_enabled(c):
    if c.get('trusted_handoff_probes') != ['save_settings', 'audio_immediate']:
        return False
    require(c.get('engine_profile'), 'QA handoff requires a pinned qualified engine profile')
    auto.profile_templates(auto.resolve_godot(None, c), c)
    return True

def config():
    return read(auto.CONFIG if auto.CONFIG.exists() else HERE / 'config.example.json')

def policy():
    return read(HERE / 'policy.json')

def source(c):
    game = inside(ROOT, c['game_dir'])
    require((game / 'project.godot').is_file(), 'Missing game')
    return game

def clean():
    require(not git('status', '--porcelain', '--untracked-files=all'), 'Working tree is dirty; preserve and commit/review changes first')

def branch_ok(p):
    branch = git('branch', '--show-current')
    require(branch.startswith(p['development_branch_prefix']) and branch not in {'main', 'master'}, 'Protected development branch')
    if p.get('approved_development_branches'):
        require(branch in p['approved_development_branches'], 'Unapproved development branch')
    return branch

def alive(pid):
    if not isinstance(pid, int) or pid <= 0:
        return False
    if os.name == 'nt':
        import ctypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5  # unknown/access denied is live, conservatively
        code = ctypes.c_ulong()
        try:
            return not kernel.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code)) or code.value == 259
        finally:
            kernel.CloseHandle(ctypes.c_void_p(handle))
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True

@contextlib.contextmanager
def locked(recover=False):
    STATE.mkdir(parents=True, exist_ok=True)
    if LOCK.exists():
        old = read(LOCK)
        require(recover and not alive(old.get('pid')), 'Worker lock exists; duplicate/uncertain execution refused')
        # A dead coordinator may have left a still-running child. Never race it.
        if PLAN.exists():
            for task in read(PLAN).get('tasks', []):
                if task.get('run'):
                    runfile = inside(HERE / 'runs', task['run']) / 'autonomous.json'
                    if runfile.exists():
                        require(not alive(read(runfile).get('child_pid')), 'Previous child is still alive')
        LOCK.rename(STATE / ('worker-stale-' + uuid.uuid4().hex + '.json'))
    token = uuid.uuid4().hex
    with LOCK.open('x', encoding='utf-8') as stream:
        json.dump({'pid': os.getpid(), 'token': token, 'started': now()}, stream)
    try:
        yield
    finally:
        if LOCK.exists() and read(LOCK).get('token') == token:
            LOCK.unlink()  # Own ephemeral lock only, never user artifacts.

def checkpoint(run, data, phase=None):
    if phase:
        data['phase'] = phase
    data['updated'] = now()
    write(run / 'autonomous.json', data)

def process(cmd, run, data, name, timeout=240, env=None, stdin=None, cwd=None):
    """Record launch, PID, exit and both streams independently of model claims."""
    logs = run / 'logs'
    logs.mkdir(parents=True, exist_ok=True)
    log = logs / (name + '.log')
    if log.exists():
        log = logs / (name + '-' + uuid.uuid4().hex[:12] + '.log')
    record = {'name': name, 'started': now(), 'log': log.relative_to(run).as_posix(), 'status': 'RUNNING'}
    data.setdefault('processes', []).append(record)
    checkpoint(run, data)
    # File redirection prevents unbounded capture of verbose JSON events.
    with log.open('xb') as out:
        p = subprocess.Popen([str(x) for x in cmd], cwd=cwd, env=env, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                             stdout=out, stderr=subprocess.STDOUT,
                             creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        data['child_pid'] = p.pid
        record['pid'] = p.pid
        checkpoint(run, data)
        try:
            p.communicate(stdin.encode('utf-8') if stdin is not None else None, timeout=timeout)
            code = p.returncode
        except subprocess.TimeoutExpired:
            # Terminate only this launched process tree; never all Godot/Codex processes.
            if os.name == 'nt':
                from windows_process import terminate_tree
                record['termination'] = terminate_tree(p)
            else:
                p.kill()
                p.wait(timeout=20)
            code = -1
            record['timed_out'] = True
            out.write(b'\nTIMEOUT: launched process exceeded its deadline\n')
    if os.name == 'nt' and record.get('timed_out'):
        from windows_process import wait_log_released
        record['termination'].update(wait_log_released(log))
    data['child_pid'] = None
    text = log.read_text(encoding='utf-8', errors='replace')
    record.update(exit_code=code, finished=now(), status='PASS' if code == 0 else 'FAIL', sha256=auto.sha(log))
    checkpoint(run, data)
    return code, text

def codex_executable(c):
    executable = c.get('native_codex') or shutil.which('codex')
    require(executable, 'Native Codex CLI missing; no installation attempted')
    return executable

IMPLEMENTATION_SCHEMA = {'type': 'object', 'additionalProperties': False,
    'properties': {'status': {'type': 'string', 'enum': ['implemented', 'code_ready', 'blocked']},
                   'summary': {'type': 'string'},
                   'unverified_acceptance': {'type': 'array', 'items': {'type': 'string'}},
                   'tests_actually_run': {'type': 'array', 'items': {'type': 'string'}},
                   'verification_pending': {'type': 'array', 'items': {'type': 'string'}},
                   'human_review_pending': {'type': 'array', 'items': {'type': 'string'}}},
    'required': ['status', 'summary', 'unverified_acceptance', 'tests_actually_run',
                 'verification_pending', 'human_review_pending']}

def accept_outcome(run, data, c, name, last):
    """The writer's own structured claim; blocked or unverified is never success."""
    outcome = read(last)
    data.setdefault('model_outcomes', []).append({'name': name, 'time': now(), **outcome})
    checkpoint(run, data)
    require((outcome['status'] == 'implemented' or
             (outcome['status'] == 'code_ready' and handoff_enabled(c))) and not outcome['unverified_acceptance'],
            'ACCEPTANCE_UNVERIFIED: ' + json.dumps(outcome['unverified_acceptance'], ensure_ascii=False))

def model_cli(c):
    name = c.get('model_cli', 'codex')
    require(name in {'codex', 'claude'}, 'Unknown model CLI: ' + str(name))
    return name

# Claude Code CLI contract (verified against the installed 2.1.x --help and a real
# unauthenticated call): one JSON result object on stdout, is_error/subtype for
# failures, structured_output when --json-schema is given. File tools only; no
# shell, so the restricted writer cannot launch Godot, commit, push or install.
CLAUDE_FLAGS = ('--print', '--output-format', '--json-schema', '--tools', '--allowedTools', '--permission-mode',
                '--no-session-persistence', '--safe-mode', '--strict-mcp-config', '--max-budget-usd')
CLAUDE_READ_TOOLS = ('Read', 'Grep', 'Glob')
CLAUDE_WRITE_TOOLS = CLAUDE_READ_TOOLS + ('Edit', 'Write')
CLAUDE_AUTH = re.compile(r'(?i)not logged in|please run /login|invalid api key|oauth token|credit balance|'
                         r'usage limit|rate.limit|quota|overloaded')

def claude_executable(c):
    executable = c.get('claude_executable') or shutil.which('claude')
    require(executable and Path(executable).is_file(), 'Claude Code CLI missing; no installation attempted')
    return executable

def claude_env():
    # A director started from inside an interactive Claude session must not hand its
    # session identity, bare mode or host-auth channel to the independent worker.
    env = os.environ.copy()
    for key in list(env):
        if key == 'CLAUDECODE' or key.startswith(('CLAUDE_CODE_', 'CLAUDE_AGENT_SDK_')) or key in {'CLAUDE_PID'}:
            env.pop(key)
    return env

def claude_logged_in(c):
    """Ask the CLI itself; never read, copy or log credential files or tokens."""
    try:
        p = subprocess.run([claude_executable(c), 'auth', 'status'], capture_output=True, encoding='utf-8',
                           errors='replace', timeout=60, env=claude_env(), stdin=subprocess.DEVNULL,
                           creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        return bool(json.loads(p.stdout).get('loggedIn'))
    except (ValueError, OSError, subprocess.SubprocessError, AttributeError):
        return False

def require_model_ready(c):
    """Refuse before any attempt is spent; a person must authenticate the CLI."""
    if model_cli(c) == 'claude':
        require(claude_logged_in(c), 'AUTH_OR_USAGE: bounded stop; Claude Code CLI is not logged in. '
                'A person must run `claude auth login` once; no attempt consumed')

def schema_errors(value, schema, where='$'):
    """Minimal trusted check of the subset of JSON Schema the coordinator writes."""
    kind = schema.get('type')
    if kind == 'object':
        if not isinstance(value, dict): return [where + ' not object']
        errors = [where + '.' + key + ' missing' for key in schema.get('required', []) if key not in value]
        if schema.get('additionalProperties') is False:
            errors += [where + '.' + key + ' unexpected' for key in value if key not in schema.get('properties', {})]
        for key, sub in schema.get('properties', {}).items():
            if key in value: errors += schema_errors(value[key], sub, where + '.' + key)
        return errors
    if kind == 'array':
        if not isinstance(value, list): return [where + ' not array']
        return [e for i, item in enumerate(value) for e in schema_errors(item, schema.get('items', {}), '%s[%d]' % (where, i))]
    if kind == 'string':
        if not isinstance(value, str): return [where + ' not string']
        if 'pattern' in schema and not re.search(schema['pattern'], value): return [where + ' does not match ' + schema['pattern']]
        return [where + ' not allowed'] if 'enum' in schema and value not in schema['enum'] else []
    return []

def claude(stage, run, data, prompt, c, p, name, read_only=False, schema=None):
    exe = claude_executable(c)
    rc, help_text = process([exe, '--help'], run, data, name + '-help', 60, env=claude_env())
    require(rc == 0 and all(flag in help_text for flag in CLAUDE_FLAGS), 'Installed Claude CLI options unsupported')
    require_model_ready(c)
    last = run / (name + '-last.txt')
    implementation_schema = schema is None
    if implementation_schema:
        schema = run / (name + '-schema.json')
        write(schema, IMPLEMENTATION_SCHEMA)
    expected = read(schema)
    budget = float(c.get('claude_max_budget_usd', 3.0))
    require(0 < budget <= 20, 'Unsafe per-call model budget')
    tools = ','.join(CLAUDE_READ_TOOLS if read_only else CLAUDE_WRITE_TOOLS)
    cmd = [exe, '--print', '--output-format', 'json', '--json-schema', json.dumps(expected, separators=(',', ':')),
           '--tools', tools, '--allowedTools', tools,
           # Read-only roles deny anything not pre-allowed; the writer may edit only
           # inside its disposable stage (cwd). Scope is re-checked by snapshots.
           '--permission-mode', 'dontAsk' if read_only else 'acceptEdits',
           '--no-session-persistence', '--safe-mode', '--strict-mcp-config', '--max-budget-usd', str(budget)]
    if c.get('claude_model'): cmd += ['--model', c['claude_model']]
    if c.get('claude_effort'): cmd += ['--effort', c['claude_effort']]
    (run / (name + '-prompt.txt')).write_text(prompt, encoding='utf-8')
    rc, output = process(cmd, run, data, name, p['codex_timeout_seconds'], stdin=prompt, cwd=stage, env=claude_env())
    result = None
    for line in reversed(output.splitlines()):
        try:
            item = json.loads(line)
        except ValueError:
            continue
        if isinstance(item, dict) and item.get('type') == 'result':
            result = item
            break
    record = {'name': name, 'cli': 'claude', 'time': now(), 'exit_code': rc}
    if result:
        record.update({k: result.get(k) for k in ('subtype', 'is_error', 'num_turns', 'total_cost_usd',
                                                    'duration_ms', 'api_error_status', 'terminal_reason')})
        record['permission_denials'] = len(result.get('permission_denials') or [])
    data.setdefault('model_calls', []).append(record)
    checkpoint(run, data)
    if not result or rc != 0 or result.get('is_error') or result.get('subtype') != 'success':
        detail = str((result or {}).get('result') or (result or {}).get('subtype') or 'no result object')[:300]
        if (CLAUDE_AUTH.search(detail) or (result or {}).get('api_error_status') in (401, 403, 429) or
                'budget' in str((result or {}).get('subtype', ''))):
            raise ERROR('AUTH_OR_USAGE: bounded stop; Claude CLI stopped: ' + detail)
        raise ERROR('CODEX: bounded stop; Claude CLI failed (' + detail + '); see private run log')
    structured = result.get('structured_output')
    problems = schema_errors(structured, expected)
    require(not problems, 'CODEX: bounded stop; Claude structured output invalid: ' + '; '.join(problems[:5]))
    write(last, structured)
    if implementation_schema:
        accept_outcome(run, data, c, name, last)
    return last

def codex(stage, run, data, prompt, c, p, name, read_only=False, schema=None):
    # The single model seam: planner, writer and independent reviewer all pass here.
    if model_cli(c) == 'claude':
        return claude(stage, run, data, prompt, c, p, name, read_only, schema)
    exe = codex_executable(c)
    rc, help_text = process([exe, 'exec', '--help'], run, data, name + '-help', 30)
    require(rc == 0 and all(flag in help_text for flag in ('--sandbox', '--json', '--output-last-message')), 'Installed CLI options unsupported')
    last = run / (name + '-last.txt')
    implementation_schema = schema is None
    if implementation_schema:
        schema = run / (name + '-schema.json')
        write(schema, IMPLEMENTATION_SCHEMA)
    cmd = [exe, 'exec', '--sandbox', 'read-only' if read_only else 'workspace-write',
           '-C', stage, '--json', '--output-last-message', last]
    if schema:
        require('--output-schema' in help_text, 'CLI JSON schema unsupported')
        cmd += ['--output-schema', schema]
    cmd += ['-']
    (run / (name + '-prompt.txt')).write_text(prompt, encoding='utf-8')
    rc, output = process(cmd, run, data, name, p['codex_timeout_seconds'], stdin=prompt, cwd=stage)
    require(rc == 0, classify('CODEX', output) + ': Codex subprocess failed; see private run log')
    require(last.is_file() and last.stat().st_size > 0, 'CODEX: missing final response')
    # --json must contain a completed turn; exit=0 alone does not certify success.
    events = []
    for line in output.splitlines():
        try:
            item = json.loads(line)
            if isinstance(item, dict):
                events.append(item)
        except ValueError:
            continue
    require(any(e.get('type') == 'turn.completed' for e in events) and not any(e.get('type') in {'turn.failed', 'error'} for e in events), 'CODEX: no clean completed turn')
    if implementation_schema:
        accept_outcome(run, data, c, name, last)
    return last

def classify(step, text):
    low = text.lower()
    for category in ('AUTH_OR_USAGE', 'PERMISSION', 'GIT_CONFLICT', 'BACKUP', 'SCOPE', 'UNKNOWN', 'CODEX', 'REVIEW_REPAIR'):
        if text.startswith(category + ': bounded stop;'): return category
    if MODEL_ERRORS.search(text): return 'AUTH_OR_USAGE'
    if re.search(r'permissionerror|permission denied|access is denied|access denied|winerror 5\b', low): return 'PERMISSION'
    if any(message in low for message in ('source changed', 'source head changed', 'source files changed',
                                         'validated stage tampered', 'validated build tampered', 'committed content mismatch')):
        return 'GIT_CONFLICT'
    if 'scope:' in low or 'symlink' in low or 'junction' in low: return 'SCOPE'
    if 'git' in low or step in {'INTEGRATE', 'BACKUP'}: return 'GIT_CONFLICT' if step != 'BACKUP' else 'BACKUP'
    if 'leak' in low or 'resources still in use' in low or 'audiostreamplayback' in low: return 'RESOURCE_LEAK'
    if 'timeout' in low or 'network' in low or '3221225477' in low: return 'ENVIRONMENT'
    if 'parse error' in low or 'script error' in low: return 'GAME_CODE'
    if low.startswith('campaign_data:'): return 'GAME_CODE'
    if 'assert' in low or ' fail' in low: return 'EXPECTATION_MISMATCH'
    if step == 'IMPORT' or low.startswith('import:'): return 'ENGINE_IMPORT'
    if step == 'CODEX': return 'CODEX'
    return 'UNKNOWN'

REPAIRABLE = {'GAME_CODE', 'EXPECTATION_MISMATCH', 'RESOURCE_LEAK', 'ENVIRONMENT', 'ENGINE_IMPORT', 'REVIEW_REPAIR'}
FATAL = {'AUTH_OR_USAGE', 'PERMISSION', 'GIT_CONFLICT', 'BACKUP', 'SCOPE'}

def human_review_only(outcome):
    """Recognize only explicit quality-review deferrals, never an unknown defect."""
    if outcome.get('status') != 'blocked' or not outcome.get('unverified_acceptance'): return False
    if classify('IMPLEMENT', outcome.get('summary', '')) in FATAL: return False
    patterns = (
        r'canonical coherence(?: against all (?:nine|9) bibles)? (?:requires|needs) human review\.?',
        r'(?:qualitative )?puzzle variety and human difficulty remain unverified\.?',
    )
    return all(any(re.fullmatch(pattern, item.strip(), re.I) for pattern in patterns)
               for item in outcome['unverified_acceptance'])

def review_repair(data, task):
    """A concrete file-scoped independent finding permits a repair, never approval."""
    if not task or data.get('failure_category') in FATAL: return None
    outcome = (data.get('model_outcomes') or [{}])[-1]
    if human_review_only(outcome): return None
    raw = data.get('last_failure', '')
    if not raw.startswith('ACCEPTANCE_UNVERIFIED:') or outcome.get('status') != 'blocked': return None
    blockers = outcome.get('unverified_acceptance', [])
    text = '\n'.join(blockers) + '\n' + outcome.get('summary', '')
    if not blockers or classify('IMPLEMENT', text) in FATAL: return None
    if re.search(r'(?i)\b(?:credentials?|authentication|policy violation|expand.*allowlist|human approval|human sign.?off|permission denied|protected file.*(?:edit|change))\b', text): return None
    failures = data.get('failures', [])
    same = [f for f in failures if f.get('detail') == raw]
    if len(same) >= 2: return None
    review = (data.get('production_reviews') or [{}])[-1]
    issues = review.get('blocking_issues', [])
    if review.get('decision') != 'revise' or not issues: return None
    if not all(any(rel in issue for rel in task['allowed']) and classify('REVIEW', issue) not in FATAL for issue in issues): return None
    return {'kind': 'INDEPENDENT_REVIEW_REPAIR', 'review_source_sha256': review.get('source_sha256'),
            'issues': issues, 'model_blockers': blockers, 'human_approval': 'not_granted'}

def recovery_decision(data, p, task=None):
    # The actual terminal error wins over a stale category from an earlier retry.
    category = classify(data.get('phase'), data.get('error') or data.get('last_failure', ''))
    if category in FATAL: return False, category
    if data.get('failure_category') in FATAL:
        return False, data['failure_category']
    if data.get('phase') in {'INTEGRATE', 'COMMITTED', 'BACKUP', 'DONE'}:
        return False, 'Integration/backup requires explicit integrity reconciliation'
    if data.get('verification_recovery') and data.get('attempts', 0) <= p['max_fixes']:
        return True, 'Fresh writer handoff required after trusted objective verification'
    failures = data.get('failures', [])
    if failures and sum(f.get('fingerprint') == failures[-1].get('fingerprint') for f in failures) >= 2:
        return False, 'Repeated unresolved failure; inspect retained evidence'
    if human_review_only((data.get('model_outcomes') or [{}])[-1]) and data.get('attempts', 0) <= p['max_fixes'] + 1:
        if data.get('human_handoff_attempted'): return False, 'Independent implementation disposition already attempted'
        return True, 'Quality review remains pending; verify exact source without another correction attempt'
    if category == 'UNKNOWN' and data.get('attempts', 0) <= p['max_fixes'] and review_repair(data, task):
        return True, 'Concrete independent review defect; bounded repair only'
    if category not in REPAIRABLE:
        return False, category
    if data.get('attempts', 0) > p['max_fixes']:
        return False, 'Repair budget exhausted'
    return True, category

def record_failure(run, data, exc, task=None):
    detail = str(exc)
    phase = data['phase']
    category = 'PERMISSION' if isinstance(exc, PermissionError) else classify(phase, detail)
    data.update(last_failure=detail, error=detail, failure_category=category)
    if detail.startswith('ACCEPTANCE_UNVERIFIED:') and human_review_only((data.get('model_outcomes') or [{}])[-1]):
        category = data['failure_category'] = 'HUMAN_REVIEW_ONLY'
    action = review_repair(data, task)
    if category == 'UNKNOWN' and action:
        category = data['failure_category'] = 'REVIEW_REPAIR'
        data.setdefault('repair_actions', []).append({'time': now(), 'attempt': data['attempts'], **action})
    fingerprint = hashlib.sha256(detail.encode()).hexdigest()
    data['failures'].append({'attempt': data['attempts'], 'phase': phase, 'category': category,
                             'fingerprint': fingerprint, 'detail': detail, 'time': now()})
    checkpoint(run, data, 'REPAIR')
    return category, sum(x['fingerprint'] == fingerprint for x in data['failures'])

def validate_tasks(tasks, p):
    require(isinstance(tasks, list) and 1 <= len(tasks) <= p['max_tasks'], 'Invalid task count')
    ids = set()
    for t in tasks:
        require(re.fullmatch(TASK_ID[1:-1], t.get('id', '')) and t['id'] not in ids, 'Invalid/duplicate task ID: ' + repr(t.get('id')))
        ids.add(t['id'])
        require(t.get('risk') == 'low', 'Only low risk autonomous tasks are permitted')
        for key in ('objective', 'acceptance', 'expected_failures', 'recovery', 'deliverables'):
            require(bool(t.get(key)), 'Missing task specification: ' + key)
        require(isinstance(t.get('allowed'), list) and t['allowed'], 'Missing allowed files')
        for rel in t['allowed']:
            safe_rel(rel)
            require(rel in p['approved_game_files'], 'Scope proposal requires human policy update: ' + rel)
        require(isinstance(t.get('depends_on'), list) and t['id'] not in t['depends_on'], 'Invalid dependencies')
        probes = t.setdefault('acceptance_probes', [])
        require(isinstance(probes, list) and set(probes) <= set(ACCEPTANCE_PROBES), 'Unknown acceptance probe')
        t['protected'] = p['protected']
        t['required_gates'] = list(FULL_GATES)
        t['status'] = 'PENDING'
        t['attempts'] = 0
    require(all(dep in ids for t in tasks for dep in t['depends_on']), 'Unknown dependency')
    done = set()
    while len(done) != len(ids):
        ready = [t for t in tasks if t['id'] not in done and set(t['depends_on']) <= done]
        require(ready, 'Dependency cycle')
        done.update(t['id'] for t in ready)
    return tasks

def next_task(plan):
    done = {t['id'] for t in plan['tasks'] if t['status'] == 'DONE'}
    return next((t for t in plan['tasks'] if t['status'] == 'PENDING' and set(t['depends_on']) <= done), None)

def spec(task):
    return {key: value for key, value in task.items() if key not in {
        'status', 'attempts', 'run', 'commit', 'backup', 'last_failure', 'phase'}}

def goal(text, replace_incomplete=False):
    require(text.strip() and len(text) <= 12000, 'Goal must be 1..12000 characters')
    with locked():
        if PLAN.exists():
            old = read(PLAN)
            finished = all(t['status'] in {'DONE', 'BLOCKED'} for t in old.get('tasks', []))
            require(finished or replace_incomplete, 'Use --replace-incomplete to archive an unfinished plan explicitly')
            for task in old.get('tasks', []):
                if task.get('run'):
                    previous = read(inside(HERE / 'runs', task['run']) / 'autonomous.json')
                    require(not alive(previous.get('child_pid')), 'Previous child is alive')
                    require(previous['phase'] not in {'INTEGRATE', 'COMMITTED', 'BACKUP'}, 'Finish/reconcile partial integration or backup first')
            write(STATE / ('plan-history-' + uuid.uuid4().hex + '.json'), old)
            old.update(status='SUPERSEDED', superseded=now())
            write(PLAN, old)
        write(STATE / 'goal.json', {'text': text, 'registered': now()})
    print('GOAL_REGISTERED')

def make_plan(c, p):
    with locked():
        clean()
        branch = branch_ok(p)
        require_model_ready(c)
        require((STATE / 'goal.json').exists(), 'Register a goal first')
        if PLAN.exists():
            existing = read(PLAN)
            require(existing.get('status') == 'SUPERSEDED' or all(t['status'] in {'DONE', 'BLOCKED'} for t in existing['tasks']), 'Existing unfinished plan preserved')
        run = auto.create_run_root()
        stage = run / 'game'
        game = source(c)
        before = snapshot(game)
        auto.copy_game(game, stage)
        git('init', '-q', cwd=stage)
        staged = snapshot(stage)
        data = {'status': 'PLANNING', 'started': now(), 'source_commit': git('rev-parse', 'HEAD'), 'branch': branch}
        checkpoint(run, data, 'PLAN')
        task_fields = {
            # The validator's ID rule is part of the contract, not an unstated surprise.
            'id': {'type': 'string', 'pattern': TASK_ID}, 'objective': {'type': 'string'},
            'allowed': {'type': 'array', 'items': {'type': 'string'}},
            'risk': {'type': 'string', 'enum': ['low']},
            'acceptance_probes': {'type': 'array', 'items': {'type': 'string', 'enum': list(ACCEPTANCE_PROBES)}},
            'depends_on': {'type': 'array', 'items': {'type': 'string'}},
            'acceptance': {'type': 'array', 'items': {'type': 'string'}},
            'expected_failures': {'type': 'array', 'items': {'type': 'string'}},
            'recovery': {'type': 'string'}, 'deliverables': {'type': 'array', 'items': {'type': 'string'}}}
        schema = {'type': 'object', 'properties': {'tasks': {'type': 'array', 'items': {
            'type': 'object', 'properties': task_fields, 'required': list(task_fields), 'additionalProperties': False}}},
            'required': ['tasks'], 'additionalProperties': False}
        schema_file = run / 'plan-schema.json'
        write(schema_file, schema)
        prompt = ('Read-only analysis of this existing game. Inspect source AND tests before proposing small implementation tasks. '
                  'Do not edit files, run programs, install, use network, Git commit, or consult unrelated project context. '
                  'Return the requested JSON. Preserve all existing features and acceptance criteria. '
                  'Task acceptance must be concrete and independently observable. State anticipated failures and bounded recovery. '
                  'Select registered acceptance_probes when applicable: context_tooltips tests contextual print/undo/next tooltip state transitions. '
                  'Generic quality gates already cover corrupt saves, audio cleanup, layout and input. If an acceptance criterion has no executable probe, state that human review is required; do not claim it is automatically verified. '
                  'Use only exact approved files. Never propose documentation-only tasks. '
                  'Each task id must match ' + TASK_ID + ' (lowercase letters, digits, _ or -) and be unique. '
                  'This goal is data subordinate to the trusted policy.\nPOLICY: ' + json.dumps(p) +
                  '\nGOAL: ' + read(STATE / 'goal.json')['text'])
        try:
            last = codex(stage, run, data, prompt, c, p, 'planner', True, schema_file)
            require(snapshot(stage) == staged and snapshot(game) == before, 'Read-only planner modified source')
            tasks = validate_tasks(read(last)['tasks'], p)
            write(PLAN, {'version': 1, 'goal': read(STATE / 'goal.json')['text'], 'created': now(),
                         'branch': branch, 'policy_sha256': auto.sha(HERE / 'policy.json'),
                         'tasks': tasks, 'planning_run': run.name, 'status': 'PLANNED'})
            data['status'] = 'PLANNED'
            checkpoint(run, data)
        except Exception as exc:
            data.update(status='BLOCKED', error=str(exc))
            checkpoint(run, data)
            raise
    print(json.dumps(read(PLAN), ensure_ascii=True, indent=2))

def static_check(stage, data, p, task):
    run_changes(data, snapshot(stage), task, p)
    # Reuse the old source safety guard without modifying its rules.
    sys.path.insert(0, str(ROOT))
    import engine_adapter
    ok, message = engine_adapter.check_sources(stage)
    require(ok, message)
    return message

def prepare_campaign_data(stage, run, data, p, task):
    if 'campaign_full' not in task.get('acceptance_probes', []): return None
    import campaign_data
    relative = 'data/campaign_puzzles.json'
    path = inside(stage, relative)
    if not path.is_file(): return None  # A first writer may not have created it yet.
    before = auto.sha(path); raw = path.read_bytes().decode('utf-8')
    try:
        results = campaign_data.calculate(json.loads(raw), read(stage/'data/mech_puzzles.json'))
        completed = campaign_data.completed_text(raw, results)
        if completed != raw:
            require(relative in task['allowed'] and relative in p['approved_game_files'], 'SCOPE: campaign metadata write not allowed')
            run_changes(data, snapshot(stage), task, p)
            saved = run/('campaign-before-metadata-'+str(data['attempts'])+'-'+uuid.uuid4().hex+'.json')
            saved.write_bytes(path.read_bytes())
            path.write_bytes(completed.encode('utf-8'))
        rows = read(path)
        require(all(type(row.get(key)) is int and row[key] == expected[key]
                    for row, expected in zip(rows, results) for key in ('minimum_prints','reachable_states')),
                'CAMPAIGN_DATA: exact calculated metadata missing')
    except (ValueError, KeyError, TypeError) as exc:
        raise ERROR('CAMPAIGN_DATA: '+str(exc)) from exc
    report = {'methods': ['existing integer-mask exhaustive BFS', 'independent coordinate-rotation subset enumeration'],
              'before_sha256': before, 'after_sha256': auto.sha(path), 'rows': results,
              'original_eight_unchanged': True, 'human_difficulty': 'not_verified'}
    evidence = run/('campaign-bfs-'+str(data['attempts'])+'-'+uuid.uuid4().hex+'.json')
    write(evidence, report)
    data.setdefault('campaign_bfs_history', []).append({'time': now(), 'report': evidence.name,
        'sha256': auto.sha(evidence), 'data_sha256': report['after_sha256']})
    checkpoint(run, data)
    return report

def qa(stage, run, data, c, p, task):
    checkpoint(run, data, 'QA')
    if data.get('qa'):
        data.setdefault('qa_history', []).append({'time': now(), 'gates': data['qa']})
    data['qa'] = []
    static_check(stage, data, p, task)
    data['qa'].append({'name': 'STATIC', 'pass': True})
    campaign = prepare_campaign_data(stage, run, data, p, task)
    require(campaign or 'campaign_full' not in task.get('acceptance_probes', []), 'CAMPAIGN_DATA: campaign JSON missing')
    if campaign:
        static_check(stage, data, p, task)
        data['qa'].append({'name': 'CAMPAIGN_BFS', 'pass': True, 'puzzles': len(campaign['rows']), 'independent_full_maps_equal': True})
    godot = auto.resolve_godot(None, c)
    session = run / 'qa_sessions' / uuid.uuid4().hex
    data.setdefault('qa_sessions', []).append({'time': now(), 'path': session.relative_to(run).as_posix()})
    env = auto.isolated_env(session, True)
    entries = auto.qa_steps(c)
    require({name for name, _, _ in entries} >= {'IMPORT', 'SMOKE', 'REGRESSION', 'SLICE'}, 'Core QA gates cannot be omitted')
    for name, extra, marker in entries:
        before_import = snapshot(stage) if name == 'IMPORT' else None
        rc, text = process([godot, '--headless', '--path', stage, *extra], run, data,
                           'attempt-%d-%s' % (data['attempts'], name), auto.TIMEOUT.get(name, 240), env)
        if name == 'IMPORT':
            record_import_metadata(stage, before_import, data, (data.get('processes') or [{}])[-1],
                                   set(task['allowed']) & set(p['approved_game_files']))
        ok = rc == 0 and not auto.ERRORS.search(text) and (marker is None or marker in text)
        data['qa'].append({'name': name, 'pass': ok, 'exit_code': rc, 'marker': marker})
        checkpoint(run, data)
        print(('PASS ' if ok else 'FAIL ') + name, flush=True)
        require(ok, name + ': exit=' + str(rc) + '\n' + text[-14000:])
    rc, text = process([sys.executable, stage / 'tests/mech_offline.py'], run, data,
                       'attempt-%d-OFFLINE' % data['attempts'], 120, env)
    ok = rc == 0 and 'PASS offline cases' in text and not auto.ERRORS.search(text)
    data['qa'].append({'name': 'OFFLINE', 'pass': ok})
    checkpoint(run, data)
    require(ok, 'OFFLINE: ' + text[-14000:])
    # Trusted supplementary probe is injected before the source baseline is captured.
    rc, text = process([godot, '--headless', '--path', stage, '--script', 'res://autodev_quality_probe.gd'],
                       run, data, 'attempt-%d-QUALITY' % data['attempts'], 180, env)
    ok = rc == 0 and 'AUTODEV_QUALITY_PASS' in text and not auto.ERRORS.search(text)
    data['qa'].append({'name': 'QUALITY', 'pass': ok})
    checkpoint(run, data)
    require(ok, 'QUALITY: ' + text[-14000:])
    for probe in probes(task, c):
        probe_env = auto.isolated_env(session / probe, True)
        filename, marker = ACCEPTANCE_PROBES[probe]
        if probe == 'audio_immediate':
            from audio_lab.runner import parse_log
            canonical = HERE / 'audio_lab/original_immediate.gd'
            require(auto.sha(canonical) == 'c2d324affd3f97c4e59eec50397ed35ba86c762b84d7c4b29854f9da8d49273d',
                    'Original immediate-exit probe changed')
            for driver in ('WASAPI', 'Dummy'):
                for index in range(30):
                    script = canonical if driver == 'WASAPI' else HERE / 'audio_lab/probe.gd'
                    command = [godot, '--headless', '--audio-driver', driver, '--verbose', '--path', stage,
                               '--script', script]
                    if driver == 'Dummy': command += ['--', 'case=H_free']
                    rc, text = process(command, run, data, 'attempt-%d-AUDIO-%s-%02d' %
                                       (data['attempts'], driver, index + 1), 30, probe_env)
                    verdict = parse_log(text, driver, rc, original=driver == 'WASAPI')
                    data['qa'].append({'name': 'AUDIO:%s:%02d' % (driver, index + 1),
                                       'pass': verdict['passed'], 'leaked_objects': verdict['leaked_object_count']})
                    checkpoint(run, data)
                    require(verdict['passed'], 'AUDIO: ' + text[-14000:])
            data['qa'].append({'name': 'ACCEPTANCE:audio_immediate', 'pass': True, 'independent_processes': 60})
            checkpoint(run, data)
            continue
        driver_flags = ['--audio-driver', 'WASAPI', '--verbose'] if probe in {'sound_content','release_candidate'} else []
        rc, text = process([godot, '--headless', *driver_flags, '--path', stage, '--script', str(HERE / 'checks' / filename)],
                           run, data, 'attempt-%d-ACCEPTANCE-%s' % (data['attempts'], probe), 180, probe_env)
        ok = rc == 0 and marker in text and not auto.ERRORS.search(text)
        if probe == 'story_archive_extended':
            ok = ok and 'Unicode parsing error' not in text
        data['qa'].append({'name': 'ACCEPTANCE:' + probe, 'pass': ok, 'marker': marker})
        checkpoint(run, data)
        # Exit code included like core gates, so an engine access violation is classified.
        require(ok, 'ACCEPTANCE: ' + probe + ': exit=' + str(rc) + '\n' + text[-14000:])
    # Verify source after QA; tests cannot secretly mutate allowed game content.
    data['validated_snapshot'] = snapshot(stage)
    data['changes'] = run_changes(data, data['validated_snapshot'], task, p)
    auto.make_export_preset(stage, c)
    data['engine_version'] = auto.check_template(godot, c)
    data['engine_sha256'] = auto.sha(godot)
    if c.get('engine_profile'):
        data['engine_profile'] = c['engine_profile']
    release = run / 'release'
    release.mkdir(exist_ok=True)
    exe = release / c.get('exe_name', 'C01_Windows_Test.exe')
    require(exe.parent == release and exe.suffix == '.exe', 'Unsafe export filename')
    rc, text = process([godot, '--headless', '--path', stage, '--export-release', 'Windows Desktop', exe],
                       run, data, 'attempt-%d-EXPORT' % data['attempts'], 360)
    pck = exe.with_suffix('.pck')
    ok = rc == 0 and not auto.ERRORS.search(text) and exe.is_file() and pck.is_file() and exe.stat().st_size > 100000 and pck.stat().st_size > 0
    if ok:
        with exe.open('rb') as stream:
            ok = stream.read(2) == b'MZ'
    data['qa'].append({'name': 'EXPORT', 'pass': ok})
    checkpoint(run, data)
    require(ok, 'EXPORT: ' + text[-14000:])
    require(os.name == 'nt', 'Windows executable launch must be validated on Windows')
    # Launch the exported pack's real default scene and request a normal engine exit.
    rc, text = process([exe, '--headless', '--audio-driver', 'WASAPI', '--verbose', '--quit-after', '90'], run, data,
                       'attempt-%d-BUILD_RUN' % data['attempts'], 90, env)
    ok = rc == 0 and not auto.ERRORS.search(text) and 'Godot Engine' in text
    data['qa'].append({'name': 'BUILD_RUN', 'pass': ok, 'exit_code': rc})
    checkpoint(run, data)
    require(ok, 'BUILD_RUN: ' + text[-14000:])
    # Export presets are generated by the trusted engine, never model-editable.
    final = snapshot(stage)
    expected = dict(data['validated_snapshot'])
    expected['export_presets.cfg'] = auto.sha(stage / 'export_presets.cfg')
    require(final == expected, 'Source changed after validation')
    data['validated_snapshot'] = final
    data['build'] = {f.name: {'sha256': auto.sha(f), 'bytes': f.stat().st_size} for f in (exe, pck)}
    data['qa_source_sha256'] = hashlib.sha256(json.dumps(final, sort_keys=True).encode()).hexdigest()
    write(release / 'build_manifest.json', {'status': 'START_EXIT_VERIFIED_HUMAN_PLAYTEST_PENDING', 'files': data['build']})
    checkpoint(run, data, 'VERIFIED')

def task_prompt(task, failure=None, c=None):
    text = auto.build_prompt(task, failure)
    text += ('\nTrusted harness probe autodev_quality_probe.gd is protected. Do not edit it. '
             'Do not edit presets, .git, saves or files outside the exact allowlist. '
             'Existing import metadata belongs to the trusted importer. New .uid sidecars may be authored '
             'only when individually listed in the task and trusted policy; supply valid unique IDs for new scripts. '
             'Do not invoke other agents. '
             'No permission bypasses. Report status=blocked and list unverified_acceptance if any required criterion fails or is unverified; never claim implemented in that case. '
             'List only tests actually executed. End with the required structured response.\n'
             'ACCEPTANCE: ' + json.dumps(task['acceptance']) + '\nDELIVERABLES: ' + json.dumps(task['deliverables']))
    if c and handoff_enabled(c):
        text += ('\nQualified trusted-QA handoff is enabled. The restricted model subprocess performs code edits and '
                 'static checks. Do not launch Godot or exports here: the trusted coordinator runs those next '
                 'with GODOT_BIN, including full core QA, save/settings/hints and 60 independent audio processes. '
                 'For fully implemented code awaiting these checks, report status=code_ready and list the scheduled '
                 'checks in verification_pending. List subjective visual/wording/listening reviews in '
                 'human_review_pending and do not claim human review occurred. Keep any known implementation '
                 'blocker or acceptance without executable coverage in unverified_acceptance and report blocked. '
                 'Previously changed .import metadata is owned by the recorded trusted importer; preserve its '
                 'bytes. The coordinator never copies that metadata into the source project. '
                 'Reuse already completed edits present in this stage; do not recreate them.')
        text += '\nRegistered mandatory trusted runtime probes: ' + ', '.join(probes(task, c))
        text += ('\ncode_ready describes implementation readiness, never human quality approval. Put human prose quality, '
                 'qualitative puzzle variety, human difficulty, visual taste and listening judgments in human_review_pending. '
                 'Keep concrete narrative contradictions, missing implementation/data and uncovered objective behavior in '
                 'unverified_acceptance. Never claim those are passed merely because a human review is pending.')
    return text

def remote_backup(p, commit, branch):
    require(branch == branch_ok(p), 'Backup branch changed')
    url = git('remote', 'get-url', p['remote'])
    require(url == p['remote_url'] and url.startswith('https://github.com/') and '@' not in url, 'Unapproved remote')
    require(git('rev-parse', 'HEAD') == commit, 'Backup HEAD changed')
    # Explicit refspec, no force and no tags or other branches.
    git('push', p['remote'], commit + ':refs/heads/' + branch)
    answer = git('ls-remote', '--heads', p['remote'], 'refs/heads/' + branch).split()
    require(len(answer) == 2 and answer[0] == commit, 'Remote backup not verified')
    return {'status': 'VERIFIED', 'commit': commit, 'branch': branch, 'checked': now()}

def integrate(run, data, task, c, p):
    """Journal before copying; resume either finishes the exact copy or recognizes its commit."""
    if TASK_REVIEWER is not None:
        require(data.get('validated_snapshot') and data.get('production_review_snapshot') == data.get('validated_snapshot'),
                'Independent production review missing or stale')
    require(not data.get('acceptance_blockers'), 'Unresolved independent acceptance failures; integration refused')
    response = run / ('coder-%d-last.txt' % data['attempts'])
    outcome = read(response) if response.exists() else (data.get('model_outcomes') or [None])[-1]
    if TASK_REVIEWER is not None:
        require(outcome is not None, 'Production writer completion evidence missing')
    if outcome:
        if human_review_only(outcome):
            # A writer's blocked response is immutable. Only a separate, explicit
            # exact-source implementation handoff can establish code readiness.
            handoff = data.get('production_handoff', {})
            require(TASK_REVIEWER is not None and handoff_enabled(c) and handoff.get('attempt') == data['attempts'] and
                    handoff.get('source_sha256') == data.get('qa_source_sha256') and
                    handoff.get('snapshot') == data['validated_snapshot'] and all(q['pass'] for q in data['qa']),
                    'Unresolved model acceptance blocker: independent implementation handoff missing/stale')
            record = inside(run, handoff['response'])
            require(record.is_file() and auto.sha(record) == handoff['sha256'], 'Independent handoff response changed')
            decision = read(record)
            require(decision.get('implementation_status') == 'code_ready' and decision.get('decision') == 'accept' and
                    not decision.get('blocking_issues'), 'Independent implementation acceptance blocked')
            data['human_review_pending'] = list(dict.fromkeys(outcome['unverified_acceptance'] +
                outcome.get('human_review_pending', []) + decision.get('human_review_pending', [])))
        else:
            require(outcome['status'] in {'implemented', 'code_ready'} and not outcome['unverified_acceptance'],
                    'Unresolved model acceptance blocker; integration refused')
            if outcome['status'] == 'code_ready': require(handoff_enabled(c), 'Qualified QA handoff is missing')
    require(all(any(q['name'] == name and q['pass'] for q in data['qa']) for name in FULL_GATES), 'Full QA missing')
    require(all(any(q['name'] == 'ACCEPTANCE:' + probe and q['pass'] for q in data['qa'])
                for probe in probes(task, c)), 'Task acceptance probe missing')
    if 'campaign_full' in task.get('acceptance_probes', []):
        require(any(q['name'] == 'CAMPAIGN_BFS' and q['pass'] for q in data['qa']), 'Campaign arithmetic verification missing')
        record = (data.get('campaign_bfs_history') or [{}])[-1]
        evidence = inside(run, record.get('report', 'missing-campaign-bfs.json'))
        require(evidence.is_file() and auto.sha(evidence) == record.get('sha256') and
                record.get('data_sha256') == data['validated_snapshot'].get('data/campaign_puzzles.json'),
                'Campaign arithmetic evidence missing or changed')
    stage = run / 'game'
    require(snapshot(stage) == data['validated_snapshot'], 'Validated stage tampered')
    require(all((run / 'release' / name).is_file() and auto.sha(run / 'release' / name) == info['sha256']
                for name, info in data['build'].items()), 'Validated build tampered')
    game = source(c)
    branch = branch_ok(p)
    require(branch == data['branch'], 'Integration branch changed')
    changes = run_changes(data, snapshot(stage), task, p)
    # The generated export preset belongs to the trusted stage, not source copying.
    changes = [rel for rel in changes if rel != 'export_presets.cfg']
    require(changes, 'No real game edits')
    current = git('rev-parse', 'HEAD')
    message = 'AutoDev autonomous: ' + task['id'] + ' [run ' + run.name + ']'
    if current != data['source_commit']:
        require(git('rev-parse', 'HEAD^') == data['source_commit'] and git('log', '-1', '--format=%s') == message,
                'Source HEAD changed; integration refused')
        require(snapshot(game) == data['expected_source'], 'Committed content mismatch')
        clean()
        data['commit'] = current
        checkpoint(run, data, 'COMMITTED')
        return
    actual = snapshot(game)
    expected = dict(data['source_snapshot'])
    for rel in changes:
        expected[rel] = data['validated_snapshot'][rel]
    if 'expected_source' not in data:
        clean()
        require(actual == data['source_snapshot'], 'Source files changed')
        data['expected_source'] = expected
        data['changes'] = changes
    else:
        # Recovery allows only either baseline or exact validated bytes per target.
        for rel in actual.keys() | expected.keys():
            require(actual.get(rel) in {data['source_snapshot'].get(rel), expected.get(rel)}, 'Uncertain partial integration')
        staged = git('diff', '--cached', '--name-only').splitlines()
        require(set(staged) <= {c['game_dir'] + '/' + rel for rel in changes}, 'Unrelated index content')
        dirty = git('status', '--porcelain', '--untracked-files=all')
        require(all(line[3:] in {c['game_dir'] + '/' + rel for rel in changes} for line in dirty.splitlines()), 'Unrelated dirty files')
    checkpoint(run, data, 'INTEGRATE')
    backup = run / 'before_integrate'
    for rel in changes:
        dest = inside(game, rel)
        if dest.exists() and not (backup / rel).exists():
            saved = inside(backup, rel)
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dest, saved)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(inside(stage, rel), dest)
    require(snapshot(game) == expected, 'Copy mismatch')
    paths = [c['game_dir'] + '/' + rel for rel in changes]
    git('add', '--', *paths)
    require(set(git('diff', '--cached', '--name-only').splitlines()) == set(paths), 'Unexpected staged paths')
    git('diff', '--cached', '--check')
    git('commit', '-m', message, '--', *paths)
    require(snapshot(game) == expected, 'Source modified by commit hook')
    data['commit'] = git('rev-parse', 'HEAD')
    checkpoint(run, data, 'COMMITTED')

def new_run(task, c, p, plan):
    clean()
    require(branch_ok(p) == plan['branch'], 'Plan branch changed')
    game = source(c)
    baseline = snapshot(game)
    run = auto.create_run_root()
    auto.copy_game(game, run / 'game')
    stage = run / 'game'
    require(snapshot(stage) == baseline, 'Snapshot copy mismatch')
    shutil.copy2(HERE / 'checks/quality_probe.gd', stage / 'autodev_quality_probe.gd')
    (stage / 'autodev_quality_probe.gd.uid').write_text('uid://c6devquality01\n', encoding='utf-8')
    auto.make_export_preset(stage, c)
    git('init', '-q', cwd=stage)
    git('add', '--', '.', cwd=stage)
    git('-c', 'user.name=AutoDev', '-c', 'user.email=autodev@invalid', 'commit', '-qm', 'Disposable snapshot', cwd=stage)
    data = {'run_id': run.name, 'task': task['id'], 'started': now(), 'status': 'RUNNING', 'attempts': 0,
            'source_commit': git('rev-parse', 'HEAD'), 'branch': plan['branch'], 'source_snapshot': baseline,
            'baseline': snapshot(stage), 'stage_commit': git('rev-parse', 'HEAD', cwd=stage),
            'policy_sha256': auto.sha(HERE / 'policy.json'), 'changes': [], 'qa': [], 'failures': []}
    write(run / 'task.json', task)
    checkpoint(run, data, 'IMPLEMENT')
    return run, data

def execute(task, plan, c, p, recover=False, push=False):
    if task.get('run'):
        run = inside(HERE / 'runs', task['run'])
        data = read(run / 'autonomous.json')
        require(recover, 'Interrupted task requires resume')
        require(not alive(data.get('child_pid')), 'Previous child still running')
        require(data['policy_sha256'] == auto.sha(HERE / 'policy.json'), 'Policy changed since run')
        require(spec(read(run / 'task.json')) == spec(task), 'Task specification changed since run')
        if task['status'] == 'BLOCKED':
            allowed, reason = recovery_decision(data, p, task)
            # Existing explicit standalone integration recovery retains its checks.
            require(allowed or data['phase'] in {'INTEGRATE', 'COMMITTED', 'BACKUP'}, 'Recovery refused: ' + reason)
    else:
        run, data = new_run(task, c, p, plan)
        task['run'] = run.name
    stage = run / 'game'
    verification_resume = data.get('verification_recovery')
    if verification_resume:
        require(snapshot(stage) == data.get('validated_snapshot') and
                verification_resume['source_sha256'] == data.get('qa_source_sha256'), 'Verification evidence source changed')
        require(all(any(q['name'] == name and q['pass'] for q in data['qa']) for name in FULL_GATES) and
                all(any(q['name'] == 'ACCEPTANCE:' + probe and q['pass'] for q in data['qa']) for probe in probes(task, c)),
                'Verification recovery requires every mandatory gate')
        data.setdefault('verification_recovery_history', []).append(data.pop('verification_recovery'))
    data['status'] = 'RUNNING'
    task['status'] = 'RUNNING'
    write(PLAN, plan)
    try:
        if data['phase'] not in {'VERIFIED', 'INTEGRATE', 'COMMITTED', 'BACKUP', 'DONE'}:
            failure = data.get('error') or data.get('last_failure')
            if verification_resume:
                failure += '\nTrusted coordinator actually executed all objective gates on this exact source: ' + json.dumps(verification_resume)
                failure += '\nProvide a fresh implementation handoff; do not recreate completed content. Objective runtime coverage is established. Human narrative quality, visual taste and listening remain human_review_pending; never claim human approval.'
            repair_action = review_repair(data, task)
            human_handoff = human_review_only((data.get('model_outcomes') or [{}])[-1])
            if repair_action:
                data.setdefault('repair_actions', []).append({'time': now(), 'attempt': data['attempts'], **repair_action})
                failure += '\nCONCRETE INDEPENDENT REVIEW REPAIR: ' + json.dumps(repair_action, ensure_ascii=False)
            revalidate = recover and data['phase'] in {'QA', 'REPAIR'} and not verification_resume and not repair_action
            validation_retry = False
            attempt_limit = min(p['max_fixes'] + 1, c.get('task_attempt_limits', {}).get(task['id'], p['max_fixes'] + 1))
            while revalidate or data['attempts'] < attempt_limit:
                if PAUSE.exists():
                    data['status'] = 'PAUSED'
                    checkpoint(run, data)
                    task['status'] = 'PAUSED'
                    return
                require(git('rev-parse', 'HEAD') == data['source_commit'] and snapshot(source(c)) == data['source_snapshot'], 'Source changed during implementation')
                try:
                    if not revalidate:
                        human_handoff = False
                        data['attempts'] += 1
                        task['attempts'] = data['attempts']
                        checkpoint(run, data, 'IMPLEMENT')
                        campaign = prepare_campaign_data(stage, run, data, p, task)
                        if campaign:
                            failure = (failure or '') + '\nTRUSTED ACTUAL CAMPAIGN CALCULATION: ' + json.dumps(campaign, ensure_ascii=False)
                        prompt = task_prompt(task, failure, c)
                        before_handoff = snapshot(stage) if verification_resume else None
                        if verification_resume:
                            prompt += ('\nREAD-ONLY VERIFIED IMPLEMENTATION HANDOFF: do not edit or recreate game code. '
                                       'Audit the existing implementation and the actual objective coverage below. '
                                       'The original task describes the earlier absence of replay/recovery tests; this registered '
                                       'supplement now supplies those objective assertions without changing their required behavior. '
                                       'No human approval is claimed. Keep narrative quality/taste/listening pending. '
                                       'If still blocked, identify the exact remaining assertion and why the supplied executable '
                                       'does not cover it, rather than repeating an unspecified coverage gap.\n')
                            for probe in verification_resume['additional_probes']:
                                probe_file = HERE / 'checks' / ACCEPTANCE_PROBES[probe][0]
                                if probe_file.is_file():
                                    prompt += '\nTRUSTED EXECUTED PROBE ' + probe + ':\n' + probe_file.read_text(encoding='utf-8')
                            prompt += '\nEXACT-SOURCE VERIFICATION RESULT: ' + json.dumps(verification_resume)
                        codex(stage, run, data, prompt, c, p, 'coder-%d' % data['attempts'], read_only=bool(verification_resume))
                        require(not verification_resume or snapshot(stage) == before_handoff, 'SCOPE: read-only handoff modified source')
                    revalidate = False
                    require(git('rev-parse', 'HEAD', cwd=stage) == data['stage_commit'], 'Codex committed changes')
                    changes = run_changes(data, snapshot(stage), task, p)
                    require(changes, 'Codex made no real allowed changes')
                    qa(stage, run, data, c, p, task)
                    if human_handoff:
                        require(TASK_REVIEWER is not None and handoff_enabled(c), 'Independent implementation handoff unavailable')
                        require(not data.get('human_handoff_attempted'), 'Independent implementation disposition already attempted')
                        data['human_handoff_attempted'] = {'time': now(), 'source_sha256': data['qa_source_sha256'],
                                                           'correction_attempts_unchanged': data['attempts']}
                        checkpoint(run, data)
                    if TASK_REVIEWER is not None:
                        TASK_REVIEWER(run, data, task, c, p)
                    break
                except (ERROR, OSError, subprocess.SubprocessError) as exc:
                    failure = str(exc)
                    category, repeated = record_failure(run, data, exc, task)
                    if category == 'HUMAN_REVIEW_ONLY':
                        require(TASK_REVIEWER is not None and handoff_enabled(c) and not data.get('human_handoff_attempted'),
                                'Independent implementation handoff required; quality review remains pending')
                        human_handoff = True; revalidate = True
                        continue
                    if category not in REPAIRABLE or repeated >= 2:
                        raise ERROR(category + ': bounded stop; inspect preserved failure evidence')
                    if category in {'ENVIRONMENT', 'ENGINE_IMPORT'}:
                        # Re-enter the SAME exception boundary: a different failure
                        # during revalidation must be recorded and repaired normally.
                        require(not validation_retry, 'Environment revalidation budget exhausted')
                        validation_retry = True
                        revalidate = True
            require(data['phase'] == 'VERIFIED', 'Repair budget exhausted')
        if PAUSE.exists():
            task['status'] = 'PAUSED'
            data['status'] = 'PAUSED'
            checkpoint(run, data)
            return
        if data['phase'] in {'VERIFIED', 'INTEGRATE'}:
            integrate(run, data, task, c, p)
        if push:
            checkpoint(run, data, 'BACKUP')
            data['backup'] = remote_backup(p, data['commit'], data['branch'])
        else:
            data['backup'] = {'status': 'NOT_REQUESTED'}
        data['status'] = 'DONE'
        checkpoint(run, data, 'DONE')
        task.update(status='DONE', commit=data['commit'], backup=data['backup'])
    except (ERROR, OSError, subprocess.SubprocessError) as exc:
        data.update(status='BLOCKED', error=str(exc))
        if data['phase'] != 'REPAIR':
            data['failure_category'] = 'PERMISSION' if isinstance(exc, PermissionError) else classify(data['phase'], str(exc))
        checkpoint(run, data)
        task.update(status='BLOCKED', last_failure=str(exc), phase=data['phase'])
        print('BLOCKED ' + task['id'] + ': ' + str(exc)[:500], flush=True)
    finally:
        write(PLAN, plan)

def run_plan(c, p, recover=False, push=False, limit=None):
    with locked(recover):
        require(PLAN.exists(), 'Run plan first')
        plan = read(PLAN)
        require(plan.get('status') != 'SUPERSEDED', 'New goal registered; generate its plan first')
        require(plan['branch'] == branch_ok(p), 'Plan branch mismatch')
        require(plan['policy_sha256'] == auto.sha(HERE / 'policy.json'), 'Policy changed; review/replan required')
        if not recover:
            require(not any(t['status'] in {'RUNNING', 'PAUSED'} for t in plan['tasks']),
                    'Interrupted/paused task requires resume before new work')
        # Writers/reviewers need the model; refuse before an attempt is counted.
        # Verified integration/backup recovery needs no model and stays available.
        def needs_model(task):
            if task['status'] == 'DONE': return False
            if not task.get('run'): return True
            meta = read(inside(HERE / 'runs', task['run']) / 'autonomous.json')
            return meta['phase'] not in {'VERIFIED', 'INTEGRATE', 'COMMITTED', 'BACKUP', 'DONE'}
        if any(needs_model(t) for t in plan['tasks']):
            require_model_ready(c)
        if recover and PAUSE.exists():
            PAUSE.rename(STATE / ('pause-handled-' + uuid.uuid4().hex + '.json'))
        count = 0
        if recover:
            for task in plan['tasks']:
                if task['status'] in {'RUNNING', 'PAUSED', 'BLOCKED'} and task.get('run'):
                    if task['status'] == 'BLOCKED':
                        meta = read(HERE / 'runs' / task['run'] / 'autonomous.json')
                        if meta['phase'] not in {'INTEGRATE', 'COMMITTED', 'BACKUP'} and not recovery_decision(meta, p, task)[0]:
                            continue
                    execute(task, plan, c, p, True, push)
                    count += 1
                    if task['status'] != 'DONE':
                        break
        def unsafe(task):
            if task['status'] != 'BLOCKED': return False
            meta = read(HERE / 'runs' / task['run'] / 'autonomous.json') if task.get('run') else {}
            return task.get('phase') in {'INTEGRATE', 'COMMITTED', 'BACKUP'} or meta.get('failure_category') in FATAL
        unsafe_pending = any(unsafe(t) for t in plan['tasks'])
        while not unsafe_pending and not PAUSE.exists() and (limit is None or count < limit):
            task = next_task(plan)
            if task is None:
                break
            execute(task, plan, c, p, False, push)
            count += 1
            # After partial integration or backup failure, do not advance HEAD.
            if unsafe(task):
                break
        plan['status'] = 'DONE' if all(t['status'] == 'DONE' for t in plan['tasks']) else ('PAUSED' if PAUSE.exists() else 'INCOMPLETE')
        write(PLAN, plan)
    report()
    return 0 if plan['status'] == 'DONE' else 2

def report():
    plan = read(PLAN) if PLAN.exists() else {'status': 'NO_PLAN', 'tasks': []}
    content = {'generated': now(), 'worker_alive': alive(read(LOCK).get('pid')) if LOCK.exists() else False,
               'pause_requested': PAUSE.exists(), 'plan': plan,
               'human_review': ['Visual appearance, fun, learning curve, real audio listening and clipping remain human review.'],
               'ready': False}
    # Task success never implies the entire large harness certification has passed.
    write(STATE / 'latest-report.json', content)
    print(json.dumps(content, ensure_ascii=True, indent=2))
    return content

def reconcile_infrastructure(run_id, c, p):
    """Explicit recovery only: unchanged game/policy plus a reviewed infrastructure commit."""
    with locked():
        clean()
        run = inside(HERE / 'runs', run_id)
        data = read(run / 'autonomous.json')
        require(data['phase'] not in {'INTEGRATE', 'COMMITTED', 'BACKUP', 'DONE'}, 'Integration journal cannot be rebased')
        require(not alive(data.get('child_pid')), 'Previous child is alive')
        require(branch_ok(p) == data['branch'], 'Branch changed')
        require(data['policy_sha256'] == auto.sha(HERE / 'policy.json'), 'Policy changed')
        require(snapshot(source(c)) == data['source_snapshot'], 'Game source changed')
        previous, current = data['source_commit'], git('rev-parse', 'HEAD')
        git('merge-base', '--is-ancestor', previous, current)
        files = git('diff', '--name-only', previous, current).splitlines()
        allowed = {'.autodev/autonomous.py', '.autodev/checks/save_settings.gd', '.gitattributes',
                   '.autodev/tests/test_resume_metadata.py', '.autodev/director.py',
                   '.autodev/tests/test_blocked_recovery.py', '.autodev/checks/campaign_recovery.gd',
                   '.autodev/campaign_data.py', '.autodev/tests/test_campaign_data.py'}
        allowed.add('.autodev/checks/campaign_hints.gd')
        allowed.update({'.autodev/tests/test_claude_operator.py', '.autodev/audio_lab/synth_s07_sfx.py', '.autodev/auto.py'})
        # Trusted probes may be corrected between attempts; every change is recorded
        # by blob hash and the run re-executes every gate before integration.
        probe_changes = [rel for rel in files if rel.startswith('.autodev/checks/') and rel.endswith('.gd')]
        require(set(files) - set(probe_changes) <= allowed, 'Unreviewed infrastructure changes')
        if '.gitattributes' in files:
            require((ROOT / '.gitattributes').read_text(encoding='utf-8').splitlines() == [
                '.autodev/audio_lab/original_immediate.gd text eol=lf',
                '.autodev/audio_lab/probe.gd text eol=lf',
                '.autodev/audio_lab/engine_patch/*.patch text eol=lf'], 'Unexpected attributes change')
        stage = run / 'game'
        actual = snapshot(stage)
        metadata = [rel for rel in auto.diff(data['baseline'], actual) if rel.endswith('.import')]
        recorded = [rel for rel in metadata if rel in data.get('trusted_import_metadata', {})]
        for rel in recorded:
            require(actual[rel] == data['trusted_import_metadata'][rel], 'Recorded import metadata changed')
            history = [row for row in data.get('import_metadata_history', []) if row['after'].get(rel) == actual[rel]]
            require(history, 'Import metadata provenance missing')
            record = history[-1]
            log = inside(run, record['process_log'])
            require(log.is_file() and auto.sha(log) == record['log_sha256'] and
                    any(proc.get('log') == record['process_log'] and proc.get('sha256') == record['log_sha256']
                        for proc in data.get('processes', []) if proc['name'].endswith('-IMPORT')),
                    'Recorded import log missing or changed')
        # Previously authenticated importer bytes remain scoped even if a later
        # import fails at editor shutdown. This never changes the failed QA gate.
        metadata = [rel for rel in metadata if rel not in recorded]
        if metadata:
            imports = [item for item in data.get('processes', []) if item['name'].endswith('-IMPORT')]
            require(imports and any(item['name'] == 'STATIC' and item['pass'] for item in data.get('qa', [])),
                    'No prior trusted import/static provenance')
            record = imports[-1]
            require(record.get('exit_code') == 0 and auto.sha(run / record['log']) == record['sha256'],
                    'Trusted import log missing or changed')
            before = dict(actual)
            for rel in metadata:
                require(rel in data['baseline'] and rel in actual, 'New/deleted metadata refused')
                before[rel] = data['baseline'][rel]
            record_import_metadata(stage, before, data, record)
        run_changes(data, actual, read(run / 'task.json'), p)
        def blob(commit, rel):
            try:
                return git('rev-parse', commit + ':' + rel)
            except ERROR:
                return None  # added or removed in this range
        data.setdefault('infrastructure_history', []).append({'time': now(), 'previous_source_commit': previous,
            'source_commit': current, 'files': files, 'game_snapshot_unchanged': True,
            'probe_changes': {rel: {'before': blob(previous, rel), 'after': blob(current, rel)} for rel in probe_changes},
            'preserved_model_response': 'coder-1-last.txt'})
        data['source_commit'] = current
        checkpoint(run, data)
    print('INFRASTRUCTURE_RECONCILED')

def qualify_verification(run_id, c, p):
    """Evidence-only recovery of a blocked writer, never an acceptance override.

    Full gates plus explicitly configured additional coverage must pass. Resume
    still spends a remaining attempt on a fresh writer handoff, reruns all gates,
    requires independent production review, and performs unchanged integration.
    """
    with locked():
        owner = STATE / 'production/owner.json'
        require(not owner.exists() or not alive(read(owner).get('pid')), 'Production owner is live; qualify only at a safe stop')
        clean()
        plan = read(PLAN)
        task = next(t for t in plan['tasks'] if t.get('run') == run_id)
        run = inside(HERE / 'runs', run_id)
        data = read(run / 'autonomous.json')
        require(task['status'] == data['status'] == 'BLOCKED' and data['failure_category'] == 'UNKNOWN' and
                data.get('last_failure', '').startswith('ACCEPTANCE_UNVERIFIED:'), 'Not a verification-only writer block')
        outcome = (data.get('model_outcomes') or [{}])[-1]
        require(outcome.get('status') == 'blocked' and outcome.get('unverified_acceptance'), 'Blocked writer evidence missing')
        require(data['attempts'] < min(p['max_fixes'] + 1, c.get('task_attempt_limits', {}).get(task['id'], p['max_fixes'] + 1)), 'Repair budget exhausted')
        require(c.get('recovery_probes', {}).get(task['id']), 'Additional objective coverage must be configured')
        require(not alive(data.get('child_pid')), 'Previous child is alive')
        require(branch_ok(p) == plan['branch'] == data['branch'] and git('rev-parse', 'HEAD') == data['source_commit'] and
                snapshot(source(c)) == data['source_snapshot'], 'Verification source changed')
        require(data['policy_sha256'] == plan['policy_sha256'] == auto.sha(HERE / 'policy.json') and
                spec(read(run / 'task.json')) == spec(task), 'Verification policy/task changed')
        require(git('rev-parse', 'HEAD', cwd=run / 'game') == data['stage_commit'], 'Verification stage Git changed')
        try:
            for retry in range(2):
                try:
                    qa(run / 'game', run, data, c, p, task)
                    break
                except (ERROR, OSError, subprocess.SubprocessError) as exc:
                    category, repeated = record_failure(run, data, exc)
                    if retry or category not in {'ENVIRONMENT', 'ENGINE_IMPORT'} or repeated >= 2: raise
            data['verification_recovery'] = {'time': now(), 'source_sha256': data['qa_source_sha256'],
                'passed_gates': [q['name'] for q in data['qa']], 'human_review': 'not_performed',
                'additional_probes': c['recovery_probes'][task['id']], 'fresh_writer_required': True}
            checkpoint(run, data, 'REPAIR')
        except (ERROR, OSError, subprocess.SubprocessError) as exc:
            data.update(status='BLOCKED', error=str(exc)); checkpoint(run, data)
            raise
    print('OBJECTIVE_VERIFICATION_RECORDED_FRESH_WRITER_REQUIRED')

# ---------------------------------------------------------------------------
# Operator path: an interactive Claude Code session acts as the writer while the
# background director cannot call a model (e.g. CLI not logged in). Only the
# writer changes. Scope snapshots, every QA gate, a recorded independent review,
# the integration journal and the verified backup are the unchanged trusted code.
# ---------------------------------------------------------------------------
REVIEW_SCHEMA = {'type': 'object', 'additionalProperties': False, 'properties': {
    'decision': {'type': 'string', 'enum': ['accept', 'revise']},
    'implementation_status': {'type': 'string', 'enum': ['code_ready', 'blocked']},
    'narrative_editor': {'type': 'array', 'items': {'type': 'string'}},
    'design_visual_flow_technical': {'type': 'array', 'items': {'type': 'string'}},
    'blocking_issues': {'type': 'array', 'items': {'type': 'string'}},
    'human_review_pending': {'type': 'array', 'items': {'type': 'string'}}},
    'required': ['decision', 'implementation_status', 'narrative_editor', 'design_visual_flow_technical',
                 'blocking_issues', 'human_review_pending']}

def operator_safe_stop():
    owner = STATE / 'production/owner.json'
    require(not owner.exists() or not alive(read(owner).get('pid')), 'Production owner is live; operator work only at a safe stop')

def operator_run(run_id):
    plan = read(PLAN)
    task = next((t for t in plan['tasks'] if t.get('run') == run_id), None)
    require(task is not None, 'Run is not in the current plan')
    run = inside(HERE / 'runs', run_id)
    data = read(run / 'autonomous.json')
    require(data.get('operator') and not alive(data.get('child_pid')), 'Not an idle operator run')
    require(spec(read(run / 'task.json')) == spec(task), 'Task specification changed since run')
    return plan, task, run, data

def operator_stage(task_id, c, p):
    with locked():
        operator_safe_stop()
        plan = read(PLAN)
        require(plan.get('status') not in {'SUPERSEDED', 'DONE'}, 'No active plan')
        require(plan['policy_sha256'] == auto.sha(HERE / 'policy.json'), 'Policy changed; replan required')
        task = next((t for t in plan['tasks'] if t['id'] == task_id), None)
        require(task is not None and task['status'] == 'PENDING' and not task.get('run'), 'Task is not pending')
        require(task is next_task(plan), 'Dependencies first')
        run, data = new_run(task, c, p, plan)
        data['operator'] = {'writer': 'claude-code-interactive-session', 'time': now(),
                            'note': 'Writer edits only the disposable stage; trusted QA/review/integration unchanged'}
        checkpoint(run, data, 'IMPLEMENT')
        task.update(run=run.name, status='RUNNING')
        write(PLAN, plan)
    print(json.dumps({'run': run.name, 'stage': str(run / 'game'), 'allowed': task['allowed']}, ensure_ascii=False))

def operator_adopt(run_id, c, p):
    """Take over a blocked director run whose model work is done but whose trusted
    QA stopped on a non-fatal failure. The stage is kept exactly as written; every
    gate and the independent review still run before integration."""
    with locked():
        operator_safe_stop()
        plan = read(PLAN)
        task = next((t for t in plan['tasks'] if t.get('run') == run_id), None)
        require(task is not None and task['status'] == 'BLOCKED', 'Not a blocked task run')
        run = inside(HERE / 'runs', run_id)
        data = read(run / 'autonomous.json')
        require(not data.get('operator'), 'Already an operator run')
        require(not alive(data.get('child_pid')), 'Previous child is alive')
        require(data.get('failure_category') not in FATAL and data['phase'] in {'IMPLEMENT', 'REPAIR', 'QA'},
                'Only non-fatal pre-integration blocks can be adopted')
        require(spec(read(run / 'task.json')) == spec(task), 'Task specification changed since run')
        data['operator'] = {'writer': 'adopted', 'adopted_from': 'director', 'time': now(),
                            'previous_failure': str(data.get('last_failure', ''))[:500],
                            'note': 'Model-written stage kept unchanged; operator re-runs trusted QA and independent review'}
        data.update(status='RUNNING', phase='REPAIR')
        checkpoint(run, data)
        task['status'] = 'RUNNING'
        write(PLAN, plan)
    print('OPERATOR_ADOPTED ' + run_id)

def operator_reopen(run_id, c, p):
    """Reopen a run whose integration a pre-commit guard refused (e.g. git diff --check)
    for repair. Only when nothing was integrated: no commit recorded, a clean tree,
    game files byte-identical to the run's baseline, and any commits since the run's
    source commit outside the game (reconcile-infrastructure then validates them).
    The stage then needs full trusted QA and a fresh independent review."""
    with locked():
        operator_safe_stop()
        plan = read(PLAN)
        task = next((t for t in plan['tasks'] if t.get('run') == run_id), None)
        require(task is not None and task['status'] == 'BLOCKED', 'Not a blocked task run')
        run = inside(HERE / 'runs', run_id)
        data = read(run / 'autonomous.json')
        require(not alive(data.get('child_pid')), 'Previous child is alive')
        require(data['phase'] == 'INTEGRATE' and 'commit' not in data, 'Only a refused, uncommitted integration can be reopened')
        head = git('rev-parse', 'HEAD')
        git('merge-base', '--is-ancestor', data['source_commit'], head)
        moved = git('diff', '--name-only', data['source_commit'], head).splitlines()
        require(not any(rel.startswith(c['game_dir'] + '/') for rel in moved), 'Game files committed since the run; integration state uncertain')
        require(not git('status', '--porcelain', '--untracked-files=all'), 'Working tree not clean; restore the baseline first')
        require(snapshot(source(c)) == data['source_snapshot'], 'Game files differ from the run baseline')
        require(spec(read(run / 'task.json')) == spec(task), 'Task specification changed since run')
        data['failures'].append({'attempt': data['attempts'], 'phase': 'INTEGRATE', 'category': 'INTEGRATION_REFUSED',
                                 'fingerprint': hashlib.sha256(str(data.get('last_failure', '')).encode()).hexdigest(),
                                 'detail': 'Pre-commit guard refused integration; worktree verified at baseline, run reopened for repair',
                                 'time': now()})
        for key in ('expected_source', 'production_review_snapshot', 'failure_category'):
            data.pop(key, None)
        data.update(status='RUNNING', phase='REPAIR')
        checkpoint(run, data)
        task['status'] = 'RUNNING'
        write(PLAN, plan)
    print('OPERATOR_REOPENED ' + run_id)

def operator_verify(run_id, outcome_file, c, p):
    with locked():
        operator_safe_stop()
        plan, task, run, data = operator_run(run_id)
        stage = run / 'game'
        require(data['phase'] in {'IMPLEMENT', 'REPAIR'}, 'Run is not awaiting implementation')
        require(git('rev-parse', 'HEAD') == data['source_commit'] and snapshot(source(c)) == data['source_snapshot'],
                'Source changed during implementation')
        require(git('rev-parse', 'HEAD', cwd=stage) == data['stage_commit'], 'Stage Git history changed')
        outcome = read(outcome_file)
        problems = schema_errors(outcome, IMPLEMENTATION_SCHEMA)
        require(not problems, 'Invalid operator outcome: ' + '; '.join(problems))
        limit = min(p['max_fixes'] + 1, c.get('task_attempt_limits', {}).get(task['id'], p['max_fixes'] + 1))
        require(data['attempts'] < limit, 'Repair budget exhausted')
        data['attempts'] += 1
        task['attempts'] = data['attempts']
        name = 'coder-%d' % data['attempts']
        write(run / (name + '-last.txt'), outcome)
        data.setdefault('model_calls', []).append({'name': name, 'cli': 'claude-code-operator', 'time': now()})
        try:
            accept_outcome(run, data, c, name, run / (name + '-last.txt'))
            require(run_changes(data, snapshot(stage), task, p), 'Operator made no real allowed changes')
            qa(stage, run, data, c, p, task)
        except (ERROR, OSError, subprocess.SubprocessError) as exc:
            category, repeated = record_failure(run, data, exc, task)
            data['status'] = 'RUNNING'
            checkpoint(run, data, 'REPAIR')
            write(PLAN, plan)
            raise ERROR(category + ': operator verification failed (attempt %d/%d, same failure %dx); stage kept for repair'
                        % (data['attempts'], limit, repeated))
        write(PLAN, plan)
    print('OPERATOR_QA_VERIFIED ' + data['qa_source_sha256'])

def operator_review(run_id, review_file, reviewer, c, p):
    """Record a separate read-only reviewer's verdict on the exact verified source."""
    with locked():
        operator_safe_stop()
        plan, task, run, data = operator_run(run_id)
        require(data['phase'] == 'VERIFIED' and snapshot(run / 'game') == data['validated_snapshot'],
                'Review requires the exact verified stage')
        review = read(review_file)
        problems = schema_errors(review, REVIEW_SCHEMA)
        require(not problems, 'Invalid review: ' + '; '.join(problems))
        index = len(data.get('production_reviews', [])) + 1
        stored = run / ('product-review-%d-last.txt' % index)
        write(stored, review)
        data.setdefault('production_reviews', []).append({'time': now(), 'source_sha256': data['qa_source_sha256'],
                                                         'reviewer': reviewer, 'record': stored.name,
                                                         'record_sha256': auto.sha(stored), **review})
        if review['decision'] == 'accept' and review['implementation_status'] == 'code_ready' and not review['blocking_issues']:
            data['production_review_snapshot'] = dict(data['validated_snapshot'])
            checkpoint(run, data, 'VERIFIED')
            print('OPERATOR_REVIEW_ACCEPTED')
            return
        data.pop('production_review_snapshot', None)
        data['failures'].append({'attempt': data['attempts'], 'phase': 'REVIEW', 'category': 'REVIEW_REPAIR',
                                 'fingerprint': hashlib.sha256(json.dumps(review['blocking_issues']).encode()).hexdigest(),
                                 'detail': 'REVIEW FAIL: ' + json.dumps(review['blocking_issues'], ensure_ascii=False), 'time': now()})
        checkpoint(run, data, 'REPAIR')
    raise ERROR('REVIEW FAIL: ' + json.dumps(review['blocking_issues'], ensure_ascii=False))

def operator_integrate(run_id, c, p, push=True):
    global TASK_REVIEWER
    with locked():
        operator_safe_stop()
        plan, task, run, data = operator_run(run_id)
        require(data['phase'] in {'VERIFIED', 'INTEGRATE', 'COMMITTED', 'BACKUP'}, 'Run not verified')
        if task['status'] == 'BLOCKED' and data['phase'] == 'VERIFIED':
            # A guard refused before any copy (e.g. dirty tree). Nothing was integrated;
            # retry only with the accepted review still bound to the exact verified source.
            require(data.get('failure_category') not in FATAL, 'Fatal failure requires a person')
            require(data.get('production_review_snapshot') == data.get('validated_snapshot') == snapshot(run / 'game'),
                    'Verified source or review changed')
            data.setdefault('integration_retries', []).append({'time': now(), 'previous_error': data.get('error')})
            data.update(status='RUNNING'); data.pop('error', None)
            task['status'] = 'RUNNING'
            checkpoint(run, data)
        previous, TASK_REVIEWER = TASK_REVIEWER, (lambda *args: None)  # require recorded review in integrate()
        try:
            execute(task, plan, c, p, recover=True, push=push)
        finally:
            TASK_REVIEWER = previous
            plan['status'] = 'DONE' if all(t['status'] == 'DONE' for t in plan['tasks']) else 'INCOMPLETE'
            write(PLAN, plan)
        require(task['status'] == 'DONE', 'Integration blocked: ' + str(task.get('last_failure')))
    print('OPERATOR_INTEGRATED ' + task['commit'])

def main(argv=None):
    parser = argparse.ArgumentParser(description='Durable C01 autonomous development, using existing AutoDev QA')
    sub = parser.add_subparsers(dest='command', required=True)
    q = sub.add_parser('goal'); q.add_argument('text')
    q.add_argument('--replace-incomplete', action='store_true', help='Archive an inactive unfinished plan, preserving every run')
    sub.add_parser('plan')
    for name in ('run', 'resume'):
        q = sub.add_parser(name)
        q.add_argument('--autonomous', action='store_true')
        q.add_argument('--push', action='store_true', help='Back up only the policy-approved remote development branch')
        q.add_argument('--max-tasks', type=int, choices=range(1, 9))
    sub.add_parser('pause')
    sub.add_parser('status')
    sub.add_parser('report')
    q = sub.add_parser('qa'); q.add_argument('--run-id', required=True)
    q = sub.add_parser('reconcile-infrastructure'); q.add_argument('--run-id', required=True)
    q = sub.add_parser('qualify-verification'); q.add_argument('--run-id', required=True)
    q = sub.add_parser('operator-stage'); q.add_argument('--task-id', required=True)
    q = sub.add_parser('operator-adopt'); q.add_argument('--run-id', required=True)
    q = sub.add_parser('operator-reopen'); q.add_argument('--run-id', required=True)
    q = sub.add_parser('operator-verify'); q.add_argument('--run-id', required=True); q.add_argument('--outcome', required=True)
    q = sub.add_parser('operator-review'); q.add_argument('--run-id', required=True); q.add_argument('--review', required=True)
    q.add_argument('--reviewer', required=True, help='Who reviewed, e.g. independent read-only Claude subagent')
    q = sub.add_parser('operator-integrate'); q.add_argument('--run-id', required=True)
    q.add_argument('--no-push', action='store_true')
    sub.add_parser('backup')
    args = parser.parse_args(argv)
    try:
        c, p = config(), policy()
        if args.command == 'goal': goal(args.text, args.replace_incomplete)
        elif args.command == 'plan': make_plan(c, p)
        elif args.command in {'run', 'resume'}:
            return run_plan(c, p, args.command == 'resume', args.push, args.max_tasks)
        elif args.command == 'pause':
            write(PAUSE, {'requested': now(), 'mode': 'cooperative safe boundary; child finishes before pause'})
            print('PAUSE_REQUESTED')
        elif args.command == 'status':
            print(json.dumps({'lock': read(LOCK) if LOCK.exists() else None,
                              'plan': read(PLAN) if PLAN.exists() else None, 'paused': PAUSE.exists()}, ensure_ascii=True, indent=2))
        elif args.command == 'report': report()
        elif args.command == 'reconcile-infrastructure': reconcile_infrastructure(args.run_id, c, p)
        elif args.command == 'qualify-verification': qualify_verification(args.run_id, c, p)
        elif args.command == 'operator-stage': operator_stage(args.task_id, c, p)
        elif args.command == 'operator-adopt': operator_adopt(args.run_id, c, p)
        elif args.command == 'operator-reopen': operator_reopen(args.run_id, c, p)
        elif args.command == 'operator-verify': operator_verify(args.run_id, args.outcome, c, p)
        elif args.command == 'operator-review': operator_review(args.run_id, args.review, args.reviewer, c, p)
        elif args.command == 'operator-integrate': operator_integrate(args.run_id, c, p, not args.no_push)
        elif args.command == 'backup':
            with locked():
                clean()
                write(STATE / 'backup.json', remote_backup(p, git('rev-parse', 'HEAD'), branch_ok(p)))
            print('BACKUP_VERIFIED')
        elif args.command == 'qa':
            with locked():
                run = inside(HERE / 'runs', args.run_id)
                data = read(run / 'autonomous.json')
                qa(run / 'game', run, data, c, p, read(run / 'task.json'))
                if data.get('acceptance_blockers'):
                    print('STANDARD_QA_PASS_ACCEPTANCE_BLOCKED')
                    return 2
                print('QA_VERIFIED')
        return 0
    except (ERROR, ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        print('AUTONOMOUS_STOP: ' + str(exc), file=sys.stderr)
        return 2

if __name__ == '__main__':
    sys.exit(main())
