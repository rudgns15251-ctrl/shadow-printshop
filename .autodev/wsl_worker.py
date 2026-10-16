#!/usr/bin/env python3
"""Safe WSL-native Codex worker, invoked only by auto.py from Windows.

Uses a disposable Linux-native game directory; copies back ONLY task-allowlisted files.
No changes to Windows worktree metadata, Git, task definitions or Godot acceptance gates.
"""
from __future__ import annotations
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

IGNORED = {'.git','.godot','__pycache__','.autodev'}
MAX_TOTAL_BYTES = 250_000_000

def inventory(root):
    out={}; total=0
    for path in root.rglob('*'):
        rel=path.relative_to(root)
        if any(p in IGNORED for p in rel.parts):
            continue
        if path.is_symlink():
            raise RuntimeError('Symlink is prohibited: '+str(path))
        if path.is_file():
            total += path.stat().st_size
            if total>MAX_TOTAL_BYTES:
                raise RuntimeError('Game snapshot exceeds safe size limit')
            name=rel.as_posix()
            if name.endswith('.import') or name.endswith('.bak') or name=='export_presets.cfg':
                continue
            out[name]=hashlib.sha256(path.read_bytes()).hexdigest()
    return out

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--source',required=True)
    p.add_argument('--prompt',required=True)
    p.add_argument('--allowed',required=True)
    p.add_argument('--codex',default='codex')
    args=p.parse_args()
    original=Path(args.source).resolve(strict=True)
    allowed=json.loads(Path(args.allowed).read_text(encoding='utf-8'))
    prompt=Path(args.prompt).read_text(encoding='utf-8')
    if not (original/'project.godot').is_file():
        raise RuntimeError('Not a Godot project')
    if (original/'.git').exists():
        raise RuntimeError('Refusing to operate on a Git worktree')
    before=inventory(original)
    scratch=Path.home()/'.cache'/'godot-autodev'
    scratch.mkdir(parents=True,exist_ok=True)
    staging=Path(tempfile.mkdtemp(prefix='job-',dir=scratch))
    stage=staging/'game'
    succeeded=False
    try:
        shutil.copytree(original,stage,ignore=lambda _,names: {n for n in names if n in IGNORED})
        if inventory(stage)!=before:
            raise RuntimeError('Shadow-stage copy mismatch')
        def git(*a):
            r=subprocess.run(['git',*a],cwd=stage,capture_output=True,text=True,timeout=40)
            if r.returncode: raise RuntimeError('Disposable Git failed: '+r.stderr[-500:])
            return r.stdout.strip()
        git('init','-q')
        git('config','core.autocrlf','false')
        git('add','-A')
        git('-c','user.name=AutoDev Test','-c','user.email=test@invalid','commit','-qm','Temp baseline')
        commit=git('rev-parse','HEAD')
        code=subprocess.run([args.codex,'exec','--sandbox','workspace-write','-C',str(stage),'-'],
                            input=prompt,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                            timeout=850)
        print((code.stdout or '')[-17000:],flush=True)
        if code.returncode:
            raise RuntimeError(f'Codex failed (exit {code.returncode})')
        if git('rev-parse','HEAD')!=commit:
            raise RuntimeError('Codex created a commit; refusing to sync')
        after=inventory(stage)
        changed=sorted(set(before)|set(after))
        changed=[x for x in changed if before.get(x)!=after.get(x)]
        if not changed:
            raise RuntimeError('Codex produced no usable changes')
        for rel in changed:
            if not any(fnmatch.fnmatchcase(rel,pat) for pat in allowed):
                raise RuntimeError('Unauthorized modification: '+rel)
            if rel not in after:
                raise RuntimeError('Deletion forbidden: '+rel)
        if inventory(original)!=before:
            raise RuntimeError('Windows stage changed during Codex run; refusing sync')
        # Pre-copy all changed files to temporary neighbors for safe two-phase replace.
        temps=[]; copied=[]; backups=[]
        try:
            for rel in changed:
                dest=original/rel; dest.parent.mkdir(parents=True,exist_ok=True)
                if dest.is_symlink(): raise RuntimeError('Unexpected destination symlink: '+rel)
                backup=staging/'restore'/rel
                if dest.exists():
                    backup.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(dest,backup)
                backups.append((dest,backup))
                temp=dest.with_name(dest.name+'.autodev-pending')
                if temp.exists(): raise RuntimeError('Temporary collision: '+str(temp))
                shutil.copy2(stage/rel,temp)
                temps.append((temp,dest))
            for temp,dest in temps:
                os.replace(temp,dest)
                copied.append(dest)
        except Exception:
            for dest,backup in reversed(backups):
                if dest in copied:
                    if backup.exists(): shutil.copy2(backup,dest)
                    else: dest.unlink(missing_ok=True)
            raise
        finally:
            for temp,_ in temps:
                temp.unlink(missing_ok=True)
        print('CODEX_SYNC_OK: '+', '.join(changed),flush=True)
        succeeded=True
    finally:
        if succeeded:
            shutil.rmtree(staging)
        else:
            print('FAILED_STAGE_PRESERVED='+str(staging),flush=True)

if __name__=='__main__':
    try:
        main()
    except (RuntimeError,OSError,subprocess.SubprocessError,ValueError) as exc:
        print('WSL_WORKER_STOP:',exc,file=sys.stderr,flush=True)
        sys.exit(2)
