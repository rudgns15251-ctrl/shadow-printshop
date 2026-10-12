#!/usr/bin/env python3
"""Game harness v0.7-A: non-mutating Windows/WSL preflight checks.

Run from the Windows harness repository using its venv Python:
    .\\.venv\\Scripts\\python.exe .\\.data\\doctor_v07a.py --check

This script does not edit the repository, launch Codex tasks, call the network,
change worktree metadata, or update SQLite. Git status is checked with Windows
Git only. It intentionally does NOT call Linux Git on Windows-built worktrees.
"""

import argparse
from contextlib import closing
import ast
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class Check:
    name: str
    status: str
    detail: str


def shorten(value, limit=260):
    value = " ".join(str(value).split())
    if len(value) > limit:
        value = value[: limit - 3] + "..."
    return value


def execute(args, cwd=None, timeout=35):
    env = dict(os.environ)
    env["GIT_OPTIONAL_LOCKS"] = "0"
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    try:
        result = subprocess.run(
            [str(x) for x in args], cwd=str(cwd) if cwd else None,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", timeout=timeout, env=env,
            check=False,
        )
        return result.returncode, (result.stdout or "")
    except FileNotFoundError as exc:
        return 127, str(exc)
    except subprocess.TimeoutExpired:
        return 124, f"Timed out after {timeout} seconds"
    except (OSError, ValueError) as exc:
        return 126, str(exc)


def check_core(root):
    essential = ["harness.py", "autopilot.py", "engine_adapter.py", "tasks/backlog.json"]
    missing = [s for s in essential if not (root / s).is_file()]
    if missing:
        return Check("프로젝트 기본 파일", "FAIL", "누락: " + ", ".join(missing))
    for name in ("harness.py", "autopilot.py", "engine_adapter.py"):
        try:
            ast.parse((root / name).read_text(encoding="utf-8-sig"), filename=name)
        except (SyntaxError, UnicodeError, OSError) as exc:
            return Check("프로젝트 기본 파일", "FAIL", f"{name}: {shorten(exc)}")
    try:
        json.loads((root / "tasks/backlog.json").read_text(encoding="utf-8-sig"))
    except (ValueError, OSError, UnicodeError) as exc:
        return Check("프로젝트 기본 파일", "FAIL", f"backlog.json: {shorten(exc)}")
    return Check("프로젝트 기본 파일", "PASS", "핵심 Python 문법 및 작업 명세 JSON 읽기 성공")


def check_bridge(root):
    try:
        tree = ast.parse((root / "harness.py").read_text(encoding="utf-8-sig"))
    except (OSError, SyntaxError, UnicodeError) as exc:
        return Check("WSL 연결 코드", "FAIL", shorten(exc))
    funcs = {node.name: node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
    runner = funcs.get("run_command")
    if runner is None:
        return Check("WSL 연결 코드", "FAIL", "run_command() 함수를 찾지 못했습니다")
    names = {n.id for n in ast.walk(runner) if isinstance(n, ast.Name)}
    if "_harness_wsl_dispatch_command" not in names:
        return Check("WSL 연결 코드", "WARN", "v4 디스패치 함수 호출이 보이지 않습니다. 실제 연결 여부 확인 필요")
    if "_harness_wsl_dispatch_command" not in funcs:
        return Check("WSL 연결 코드", "WARN", "연결 함수 정의가 없습니다. 설치 코드 검토 필요")
    return Check("WSL 연결 코드", "PASS", "하네스의 WSL 디스패치 경로 확인(정적 검사)")


def check_windows_git(root):
    if not shutil.which("git"):
        return Check("Windows Git", "FAIL", "git 실행 파일을 찾지 못했습니다")
    rc, out = execute(["git", "-C", root, "rev-parse", "--show-toplevel"], timeout=12)
    if rc:
        return Check("Windows Git", "FAIL", "Git 저장소 확인 실패: " + shorten(out))
    rc, out = execute(["git", "-C", root, "status", "--porcelain=v1", "--untracked-files=normal"], timeout=25)
    if rc:
        return Check("Windows Git", "FAIL", "상태 조회 실패: " + shorten(out))
    changes = [line for line in out.splitlines() if line.strip()]
    if changes:
        examples = "; ".join(shorten(x, 90) for x in changes[:4])
        return Check("Windows Git", "FAIL", f"미커밋/미추적 항목 {len(changes)}개: {examples}")
    return Check("Windows Git", "PASS", "메인 체크아웃 깨끗함 (Windows Git 기준)")


def check_worktrees(root):
    rc, out = execute(["git", "-C", root, "worktree", "list", "--porcelain"], timeout=20)
    if rc:
        return Check("Git worktree", "FAIL", shorten(out))
    names = [line[9:] for line in out.splitlines() if line.startswith("worktree ")]
    return Check("Git worktree", "PASS", f"등록된 worktree {len(names)}개 확인 (Linux Git 상태 검사는 생략)")


def check_sqlite(root):
    db = root / ".data" / "state.sqlite3"
    if not db.is_file():
        return Check("SQLite 작업 상태", "WARN", "state.sqlite3 없음. 초기화 여부를 별도 확인하세요")
    try:
        # Read-only SQLite URI; no task status/attempt changes.
        db_uri = db.resolve().as_uri() + "?mode=ro"
        with closing(sqlite3.connect(db_uri, uri=True, timeout=3)) as conn:
            verdict = conn.execute("PRAGMA quick_check").fetchone()
            if not verdict or verdict[0] != "ok":
                return Check("SQLite 작업 상태", "FAIL", "quick_check 통과하지 못함: " + shorten(verdict))
            rows = conn.execute("SELECT id, status FROM tasks ORDER BY id").fetchall()
        reviewing = [str(task_id) for task_id, status in rows if status in ("review", "blocked", "running")]
        msg = f"읽기 전용 확인 성공; 작업 {len(rows)}개"
        if reviewing:
            msg += "; 검토 대상: " + ", ".join(reviewing[:8])
        return Check("SQLite 작업 상태", "PASS", msg)
    except (sqlite3.Error, OSError, ValueError) as exc:
        return Check("SQLite 작업 상태", "FAIL", shorten(exc))


def check_wsl_codex(distro, codex_path):
    rc, out = execute(["wsl.exe", "-d", distro, "--", codex_path, "--version"], timeout=45)
    if rc:
        return Check("WSL2 Codex", "FAIL", "호출 실패: " + shorten(out))
    return Check("WSL2 Codex", "PASS", shorten(out, 110))


def check_codex_login(distro, codex_path):
    rc, out = execute(["wsl.exe", "-d", distro, "--", codex_path, "login", "status"], timeout=45)
    if rc:
        return Check("Codex 로그인", "FAIL", "로그인 상태 확인 실패(세부 인증 정보는 출력하지 않음)")
    return Check("Codex 로그인", "PASS", "인증 상태 확인 명령 성공(인증 정보는 표시하지 않음)")


def check_godot(root):
    if not (root / "engine_adapter.py").is_file():
        return Check("Windows Godot", "FAIL", "engine_adapter.py 없음")
    rc, out = execute([sys.executable, str(root / "engine_adapter.py"), "doctor"], cwd=root, timeout=40)
    if rc == 0 and "GODOT_OK" in out:
        return Check("Windows Godot", "PASS", "엔진 어댑터 진단 성공: " + shorten(out, 140))
    if rc != 0:
        return Check("Windows Godot", "FAIL", "엔진 진단 실패: " + shorten(out))
    return Check("Windows Godot", "WARN", "엔진 진단 출력 확인 필요: " + shorten(out))


def preflight(root, distro="Ubuntu", codex_path=None):
    if codex_path is None:
        codex_path = "/home/newsjw/.local/bin/codex"
    checks = [check_core(root), check_bridge(root), check_windows_git(root)]
    if shutil.which("git"):
        checks.append(check_worktrees(root))
    else:
        checks.append(Check("Git worktree", "FAIL", "Windows Git이 없음"))
    checks.extend([check_sqlite(root), check_wsl_codex(distro, codex_path),
                   check_codex_login(distro, codex_path), check_godot(root)])
    return checks


def main():
    parser = argparse.ArgumentParser(description="v0.7-A 안전 실행 환경 진단 (기본적으로 읽기 전용)")
    parser.add_argument("--check", action="store_true", help="상태 확인만 수행 (기본값)")
    parser.add_argument("--root", default=None, help="하네스 프로젝트 루트 (기본값: 현재 디렉터리)")
    parser.add_argument("--distro", default=os.environ.get("GAME_HARNESS_WSL_DISTRO", "Ubuntu"))
    parser.add_argument("--codex", default=os.environ.get("GAME_HARNESS_WSL_CODEX", "/home/newsjw/.local/bin/codex"))
    parser.add_argument("--json", action="store_true", help="진단 결과를 화면에 JSON으로 출력")
    args = parser.parse_args()
    root = Path(args.root or Path.cwd()).resolve()
    checks = preflight(root, args.distro, args.codex)
    if args.json:
        print(json.dumps([vars(c) for c in checks], ensure_ascii=False, indent=2))
    else:
        print("Game Harness v0.7-A / READ-ONLY PREFLIGHT")
        print("원본 파일, Git 기록, SQLite 상태를 변경하지 않습니다.\n")
        for c in checks:
            print(f"[{c.status}] {c.name}: {c.detail}")
        total = {state: sum(c.status == state for c in checks) for state in ("PASS", "WARN", "FAIL")}
        print(f"\nRESULT: {total['PASS']} PASS / {total['WARN']} WARN / {total['FAIL']} FAIL")
        if total["FAIL"]:
            print("Autonomous run: NOT READY. 실패 원인을 확인하세요.")
        elif total["WARN"]:
            print("Autonomous run: REVIEW WARNINGS. 경고를 확인하세요.")
        else:
            print("Preflight passed. 실제 Codex 코드 작성과 Godot QA 성공을 보장하지는 않습니다.")
    return 1 if any(c.status == "FAIL" for c in checks) else 0


if __name__ == "__main__":
    sys.exit(main())
