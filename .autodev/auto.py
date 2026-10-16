#!/usr/bin/env python3
"""Portable Godot 4 + Codex + Git single-stage development runner (Python stdlib).

No modifications to the user's main working tree until explicit `accept`.
One staged game per run: Codex edits -> import -> QA -> export, on the SAME game folder.
"""
from __future__ import annotations
import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PureWindowsPath
import re
import shutil
import subprocess
import sys
import time
import uuid
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CONFIG = HERE / 'config.json'
ERRORS = re.compile(r'(?im)^\s*(?:SCRIPT ERROR:|ERROR:|WARNING:.*ObjectDB instances were leaked|WARNING:.*resources? still in use)')
PRESET = '''[preset.0]\n\nname="Windows Desktop"\nplatform="Windows Desktop"\nrunnable=true\ndedicated_server=false\ncustom_features=""\nexport_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\nexport_path=""\nencryption_include_filters=""\nencryption_exclude_filters=""\nscript_export_mode=2\n\n[preset.0.options]\n\ncustom_template/debug=""\ncustom_template/release=""\nbinary_format/architecture="x86_64"\nbinary_format/embed_pck=false\ntexture_format/s3tc_bptc=true\ntexture_format/etc2_astc=false\ncodesign/enable=false\napplication/modify_resources=false\n'''
IGNORE_DIR = {'.godot', '.git', '__pycache__', '.autodev'}
TIMEOUT = {'IMPORT': 240, 'SMOKE': 180, 'REGRESSION': 240, 'SLICE': 240, 'EXPORT': 300}

class StopRun(Exception):
    pass

def require(condition, msg):
    if not condition:
        raise StopRun(msg)

def load_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for part in iter(lambda: f.read(1024*1024), b''):
            h.update(part)
    return h.hexdigest()

def git(*args, check=True):
    p = subprocess.run(['git', '-C', str(ROOT), *args], capture_output=True,
                       text=True, encoding='utf-8', errors='replace', timeout=45)
    if check and p.returncode:
        raise StopRun(f'Git {args[0]} failed: {p.stderr[-1400:]}')
    return p.stdout.strip()

def source_files(game):
    """Snapshot only substantive content; Godot owns sidecars and import caches."""
    out = {}
    for path in game.rglob('*'):
        if path.is_symlink() or (hasattr(path, 'is_junction') and path.is_junction()):
            raise StopRun('Linked path in project (refusing): ' + str(path))
        if any(p in IGNORE_DIR for p in path.relative_to(game).parts):
            continue
        if path.is_symlink():
            raise StopRun('Symlink in staged project (refusing): ' + str(path))
        if path.is_file():
            relative = path.relative_to(game).as_posix()
            if relative.endswith('.import') or relative.endswith('.bak') or relative == 'export_presets.cfg':
                continue
            out[relative] = sha(path)
    return out

def diff(before, after):
    return sorted(k for k in before.keys() | after.keys() if before.get(k) != after.get(k))

def path_permitted(rel, allowed):
    return any(fnmatch.fnmatchcase(rel, pat) for pat in allowed)

def check_changes(before, after, allowed):
    changes = diff(before, after)
    bad = [p for p in changes if not path_permitted(p, allowed)]
    deleted = [p for p in changes if p not in after]
    require(not bad, 'Codex changed protected or out-of-scope files: ' + ', '.join(bad))
    require(not deleted, 'Codex deleted files: ' + ', '.join(deleted))
    return changes

def copy_game(source, target):
    require((source / 'project.godot').exists(), 'Missing game/project.godot')
    require(not target.exists(), 'Staging folder already exists: ' + str(target))
    require(not source.is_symlink() and not (hasattr(source, 'is_junction') and source.is_junction()), 'Linked source root refused')
    source_files(source)  # Reject linked paths before copytree can dereference them.
    def ignore(_, names):
        return {n for n in names if n in IGNORE_DIR or n.endswith('.bak')}
    shutil.copytree(source, target, ignore=ignore, symlinks=False)

def verify_repo(config, require_clean=True):
    root_game = (ROOT / config['game_dir']).resolve()
    require(root_game.is_relative_to(ROOT), 'game_dir must be within the current repository')
    require(root_game.is_dir(), 'Godot game folder missing: ' + str(root_game))
    require((ROOT/'.git').exists(), 'Run inside a Git repository root')
    if require_clean:
        status = git('status', '--porcelain', '--untracked-files=normal')
        # Sidecars from Godot may be modified after editing and are regenerated in staging.
        material=[]
        for s in status.splitlines():
            rel = s[3:].strip().replace('\\','/')
            if rel.endswith('.import'):
                continue
            # These new, locally installed automation files are intentionally
            # untracked until the user chooses to version the reusable template.
            if s.startswith('?? ') and (rel.startswith('.autodev/') or rel in {'Taskfile.autodev.yml','README_시작하기.md'}):
                continue
            material.append(s)
        require(not material, 'Working tree has uncommitted changes:\n' + '\n'.join(material))
    return root_game

def resolve_godot(cli_path, config):
    val = cli_path or os.environ.get('GODOT_BIN') or config.get('godot') or 'godot'
    exe = Path(val)
    if not exe.is_file():
        detected = shutil.which(val)
        require(bool(detected), 'Godot not found. Pass --godot <Godot.exe>, or set GODOT_BIN')
        exe = Path(detected)
    return exe.resolve()

def run_process(cmd, log, timeout, cwd=None, stdin=None, env=None):
    try:
        p = subprocess.run(cmd, cwd=cwd, input=stdin, capture_output=True, timeout=timeout,
                           env=env, text=stdin is not None, encoding='utf-8' if stdin is not None else None,
                           errors='replace' if stdin is not None else None)
        raw = ((p.stdout or '') + '\n' + (p.stderr or '')).encode('utf-8') if stdin is not None else (p.stdout or b'') + b'\n--- STDERR ---\n' + (p.stderr or b'')
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_bytes(raw)
        return p.returncode, raw.decode('utf-8', 'replace')
    except subprocess.TimeoutExpired as e:
        log.write_text(f'TIMEOUT after {timeout}s: {e}', encoding='utf-8')
        return -1, f'TIMEOUT after {timeout}s: {e}'

def qa_steps(config):
    return [('IMPORT', ['--import'], None)] + [
        (entry['name'], ['--script', 'res://'+entry['script'].lstrip('/')], entry['marker'])
        for entry in config['tests']
    ]

def isolated_env(run_root, test):
    env = os.environ.copy()
    if test:
        # Prevent acceptance tests using user:// from touching real player saves.
        appdata = run_root / 'qa_appdata'
        appdata.mkdir(parents=True, exist_ok=True)
        env['APPDATA'] = str(appdata)
        env['XDG_DATA_HOME'] = str(appdata)
    return env

def run_qa(godot, stage, run_root, config, round_id):
    logs = run_root / 'logs' / f'round-{round_id}'
    logs.mkdir(parents=True, exist_ok=True)
    for name, extra, marker in qa_steps(config):
        rc, contents = run_process([str(godot), '--headless', '--path', str(stage), *extra],
                                   logs/(name.lower()+'.log'), TIMEOUT.get(name,240),
                                   env=isolated_env(run_root, test=(name != 'IMPORT')))
        ok = rc == 0 and (marker is None or marker in contents) and not ERRORS.search(contents)
        print(f'{"PASS" if ok else "FAIL"} {name} exit={rc}', flush=True)
        if not ok:
            return False, name, contents[-15000:]
    return True, None, ''

def wsl_path(winpath):
    p = PureWindowsPath(str(winpath))
    require(p.drive.endswith(':') and p.is_absolute(), 'WSL requires a Windows drive path')
    return f'/mnt/{p.drive[0].lower()}/' + '/'.join(p.parts[1:])

def invoke_codex(stage, run_root, task, prompt, round_id, config, codex_mode):
    (run_root/'logs').mkdir(parents=True, exist_ok=True)
    log = run_root / 'logs' / f'codex-{round_id}.log'
    prompt_path = run_root / 'logs' / f'prompt-{round_id}.txt'
    prompt_path.write_text(prompt, encoding='utf-8')
    permitted = run_root / 'logs' / f'allow-{round_id}.json'
    permitted.write_text(json.dumps(task['allowed'], ensure_ascii=False), encoding='utf-8')
    if codex_mode == 'wsl':
        require(os.name == 'nt', 'WSL mode requires Windows')
        require(shutil.which('wsl.exe') is not None, 'wsl.exe not found')
        args = ['wsl.exe', '-d', config.get('wsl_distro','Ubuntu'), '--', 'python3',
                wsl_path(HERE/'wsl_worker.py'), '--source', wsl_path(stage),
                '--prompt', wsl_path(prompt_path), '--allowed', wsl_path(permitted),
                '--codex', config.get('wsl_codex','codex')]
        rc, output = run_process(args, log, 1000)
    else:
        executable = shutil.which('codex') or config.get('native_codex')
        require(bool(executable), 'Windows Codex not found. Install native CLI or use --codex-mode wsl')
        # CLI operates in our disposable game copy; git init improves context.
        if not (stage/'.git').exists():
            p = subprocess.run(['git','init','-q'],cwd=stage, capture_output=True)
            require(p.returncode == 0,'Cannot init disposable git repository')
        args = [executable, 'exec', '--sandbox', 'workspace-write', '-C', str(stage), '-']
        rc, output = run_process(args, log, 1000, cwd=stage, stdin=prompt)
    require(rc == 0, f'Codex call failed (exit {rc}). Log: {log}; {output[-600:]}')

def build_prompt(task, failure=None):
    rules = f'''You are editing a disposable Godot 4 game snapshot.\nGoal: {task['objective']}\nAllowed file patterns: {', '.join(task['allowed'])}\nYou MUST edit only allowed files. Never edit .import, tests, project.godot, export presets, Git files, or acceptance criteria unless a test is explicitly allowlisted.\nDo not remove existing features, change the game rules, weaken any assertion, run network/download/install, make Git commits, or perform destructive commands.\nCreate real working game code and assets, not just a report. Keep the change focused and small. Godot QA and Windows export will run after your edit.\n'''
    if task.get('test_edit_allowed'):
        rules += 'This task specifically permits the named acceptance test teardown change, but MUST preserve the count and substance of all _check assertions and success markers.\n'
    return rules + (('\nExact Godot QA failure to fix:\n' + failure[-14000:]) if failure else '')

def task_file(task_name):
    require(re.fullmatch(r'[A-Za-z0-9_-]+',task_name) is not None,'Unsafe task identifier')
    path = HERE / 'tasks' / (task_name + '.json')
    require(path.exists(), 'No task file: ' + str(path))
    task = load_json(path)
    require(task.get('allowed') and task.get('objective'), 'Task requires allowed + objective')
    require(all(isinstance(s,str) and not s.startswith('/') and not PureWindowsPath(s).drive and '\\' not in s and '..' not in s.split('/') for s in task['allowed']), 'Invalid allowed paths')
    return task

def make_export_preset(game):
    p = game/'export_presets.cfg'
    if not p.exists():
        p.write_text(PRESET,encoding='utf-8',newline='\n')

def check_template(godot):
    version_log = subprocess.run([str(godot), '--version'],capture_output=True,timeout=20)
    require(version_log.returncode==0, 'Cannot determine Godot version')
    version = version_log.stdout.decode('utf-8','replace').strip()
    m = re.match(r'(\d+\.\d+\.\d+\.[a-zA-Z0-9]+)',version)
    require(bool(m), 'Unrecognized Godot version: ' + version)
    appdata = os.environ.get('APPDATA')
    require(bool(appdata), 'Windows APPDATA not found for export template')
    template = Path(appdata)/'Godot'/'export_templates'/m.group(1)/'windows_release_x86_64.exe'
    require(template.is_file(), 'Windows export template missing: '+str(template))
    return version

def make_release(godot, stage, run_root, config):
    make_export_preset(stage)
    version = check_template(godot)
    release = run_root/'release'; release.mkdir(exist_ok=True)
    exe = release / config.get('exe_name','C01_Windows_Test.exe')
    rc, output = run_process([str(godot),'--headless','--path',str(stage),
                              '--export-release','Windows Desktop',str(exe)],
                             run_root/'logs'/'export.log', 360)
    require(rc == 0 and not ERRORS.search(output), f'Export failed (exit {rc}); see logs/export.log: {output[-850:]}')
    pck = exe.with_suffix('.pck')
    require(exe.is_file() and exe.stat().st_size>100000, 'Export did not create a usable EXE')
    require(pck.is_file() and pck.stat().st_size>0, 'Export did not create matching PCK')
    (release/'build_manifest.json').write_text(json.dumps({
        'godot':version,'status':'BUILD_CREATED_HUMAN_PLAYTEST_PENDING',
        'files':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in (exe,pck)}
    },indent=2),encoding='utf-8')
    archive = run_root/'Windows_Test_Build.zip'
    with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
        for file in release.iterdir():
            if file.is_file(): z.write(file,arcname=file.name)
    print('BUILD PASS:',archive,flush=True)
    return archive

def meta_file(run_root):
    return run_root / 'result.json'

def create_run_root():
    stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:5]
    directory = ROOT/'.autodev'/'runs'/stamp
    directory.mkdir(parents=True,exist_ok=False)
    return directory

def save_result(run_root, data):
    meta_file(run_root).write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

def do_doctor(args, config):
    game = verify_repo(config, require_clean=False)
    godot = resolve_godot(args.godot,config)
    code, _ = run_process([str(godot),'--version'], ROOT/'.autodev'/'doctor_godot.log', 20)
    require(code==0, 'Godot executable failed')
    print('DOCTOR PASS: game=' + str(game))
    print('DOCTOR PASS: godot=' + str(godot))
    mode = args.codex_mode or config.get('codex_mode','wsl')
    if mode == 'wsl':
        require(shutil.which('wsl.exe') is not None,'WSL missing; install Codex on Windows or enable WSL')
        print('CODEX MODE: WSL (login will be verified on first actual call)')
    else:
        require(bool(shutil.which('codex') or config.get('native_codex')),'Native codex CLI not found')
        print('CODEX MODE: native')
    print('DOCTOR OK: no source changed')

def do_run(args, config):
    source = verify_repo(config)
    godot = resolve_godot(args.godot,config)
    task = task_file(args.task) if args.task else None
    before_repo = git('rev-parse','HEAD')
    run_root = create_run_root()
    stage = run_root/'game'
    copy_game(source,stage)
    baseline = source_files(stage)
    state = {'run_id':run_root.name,'task':args.task,'source_commit':before_repo,'status':'running',
             'allowed':task['allowed'] if task else [],'changes':[], 'stage':str(stage)}
    state['source_snapshot'] = baseline
    save_result(run_root,state)
    print('STAGE:',stage,flush=True)
    # Single stage folder is used for import, testing and final export.
    failure = None
    allowed_rounds = args.max_fixes if task else 0
    success = False
    mode = args.codex_mode or config.get('codex_mode','wsl')
    try:
        for round_id in range(allowed_rounds + 1):
            if task and (round_id == 0 or failure is not None):
                invoke_codex(stage,run_root,task,build_prompt(task,failure),round_id,config,mode)
                check_changes(baseline,source_files(stage),task['allowed'])
                # Preserve all acceptance assertion count on targeted test repairs.
                if task.get('test_edit_allowed'):
                    for test in [x['script'] for x in config['tests'] if path_permitted(x['script'],task['allowed'])]:
                        old = (source/test).read_text(encoding='utf-8-sig')
                        new = (stage/test).read_text(encoding='utf-8-sig')
                        require(old.count('_check(')==new.count('_check('), 'Test assertions count changed')
                        require('SLICE_ACCEPTANCE_PASS' in new, 'Acceptance success marker removed')
            success, failed_step, failure = run_qa(godot,stage,run_root,config,round_id)
            if success: break
            if not task: break
            if round_id == allowed_rounds: break
            # Do not let Codex fix environment failures or parse common engine crashes.
            if '3221225477' in failure or failed_step == 'IMPORT' and not ('SCRIPT ERROR:' in failure or 'ERROR:' in failure):
                print('Environment/import failure; no code retry',flush=True)
                break
            print('QA failed; invoking bounded Codex repair',flush=True)
        state['changes'] = diff(baseline,source_files(stage))
        if success:
            if task:
                check_changes(baseline,source_files(stage),task['allowed'])
                require(bool(state['changes']), 'Codex made no allowed source changes')
            archive = None
            if not args.skip_export:
                archive = make_release(godot,stage,run_root,config)
            state['status']='review'
            state['validated_snapshot'] = source_files(stage)
            state['build_zip']=str(archive) if archive else None
            print('AUTODEV_PASS (HUMAN_REVIEW_REQUIRED)',flush=True)
        else:
            state['status']='failed'
            state['failed_step'] = failed_step
            print('AUTODEV_STOP: see run logs',flush=True)
        return 0 if success else 2
    except (StopRun,OSError,subprocess.SubprocessError) as exc:
        state['status']='failed'
        state['error']=str(exc)
        print('AUTODEV_STOP:',exc,file=sys.stderr,flush=True)
        return 2
    finally:
        save_result(run_root,state)
        print('RUN:',run_root.name,flush=True)
        print('REPORT:',meta_file(run_root),flush=True)

def do_accept(args, config):
    require(re.fullmatch(r'\d{8}-\d{6}-[a-f0-9]{5}',args.run_id or '') is not None,'Invalid run id')
    run_root = ROOT/'.autodev'/'runs'/args.run_id
    report_path = meta_file(run_root)
    require(report_path.exists(),'Run not found')
    report = load_json(report_path)
    require(report.get('status')=='review' and report.get('task'), 'Only a successful source-change run can be accepted')
    source = verify_repo(config)
    require(git('rev-parse','HEAD') == report['source_commit'], 'Git HEAD changed since this run; no files copied')
    stage = run_root/'game'
    allowed = report['allowed']
    baseline = source_files(source)
    new_snapshot = source_files(stage)
    changes = report['changes']
    require(report.get('source_snapshot') == baseline, 'Source snapshot differs; preserve historical run and revalidate')
    require(report.get('validated_snapshot') == new_snapshot, 'Stage was not validated or has changed since QA')
    require(check_changes(baseline,new_snapshot,allowed) == changes, 'Recorded change list differs from actual stage')
    require(all(p in new_snapshot and path_permitted(p,allowed) for p in changes), 'Unsafe changed paths')
    # Validate that only listed allowed changes exist in source before applying.
    require(all(p not in baseline or (source/p).exists() for p in changes),'Destination state invalid')
    # Same source must match original Git baseline; compare via `git status` was done above.
    backup = run_root/'before_accept'; backup.mkdir(exist_ok=True)
    copied=[]
    try:
        for rel in changes:
            dst = source/rel
            if dst.exists():
                old = backup/rel
                old.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(dst,old)
            else:
                require(not dst.exists(), 'Unexpected new file path')
            dst.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(stage/rel,dst)
            copied.append(rel)
        # Save newly generated import metadata for newly added art/audio assets only.
        metadata=[]
        for rel in changes:
            meta = stage/(rel+'.import')
            if meta.exists() and not (source/(rel+'.import')).exists():
                dest=source/(rel+'.import'); dest.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(meta,dest); metadata.append(rel+'.import'); copied.append(rel+'.import')
        root_paths = [(Path(config['game_dir'])/p).as_posix() for p in changes+metadata]
        git('add','--',*root_paths)
        staged = git('diff','--cached','--name-only').splitlines()
        expected = {(Path(config['game_dir'])/p).as_posix() for p in changes+metadata}
        require(set(staged) <= expected and staged, 'Unexpected staged Git files; refusing commit')
        git('diff','--cached','--check')
        git('commit','-m',f'AutoDev: {report["task"]} validated by Godot QA')
        report['status']='accepted'
        report['accepted_commit']=git('rev-parse','--short','HEAD')
        save_result(run_root,report)
        print('ACCEPTED:',report['accepted_commit'])
        print('RUN Godot editor once to reimport any newly added assets before launching game.')
    except Exception:
        # Don't roll back after a successful commit; Git would already own the change.
        if report.get('status') != 'accepted':
            git('reset','--quiet',check=False)
            for rel in copied:
                original = backup/rel
                dst = source/rel
                if original.exists(): shutil.copy2(original,dst)
                elif dst.exists(): dst.unlink()
        raise

def main():
    # Keep the original single-task CLI, with the autonomous CLI as an extension.
    if len(sys.argv) > 1 and (sys.argv[1] in {'goal','plan','status','pause','resume','report','qa','backup'} or '--autonomous' in sys.argv):
        import autonomous
        return autonomous.main(sys.argv[1:])
    parser = argparse.ArgumentParser(description='Godot AutoDev: single stage, bounded Codex, real QA, EXE export')
    sub = parser.add_subparsers(dest='command',required=True)
    for name in ('doctor','run','accept'):
        p=sub.add_parser(name)
        p.add_argument('--godot',help='Godot editor executable (or GODOT_BIN env)')
        p.add_argument('--codex-mode',choices=['wsl','native'],help='Override config coder mode')
        if name=='run':
            p.add_argument('--task',help='Task definition name (omit to QA+build the current committed game)')
            p.add_argument('--max-fixes',type=int,choices=[0,1,2],default=2)
            p.add_argument('--skip-export',action='store_true',help='Only code/QA, no EXE')
        if name=='accept':
            p.add_argument('--run-id',required=True)
    args=parser.parse_args()
    try:
        config=load_json(CONFIG)
        if args.command=='doctor': do_doctor(args,config); return 0
        if args.command=='run': return do_run(args,config)
        if args.command=='accept': do_accept(args,config); return 0
    except (StopRun,ValueError,OSError,subprocess.SubprocessError) as exc:
        print('STOP:',exc,file=sys.stderr)
        return 2
    return 2

if __name__=='__main__':
    sys.exit(main())
