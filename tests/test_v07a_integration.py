"""v0.7-A integration tests: all calls are mocked; no Codex, WSL, Git or Godot execution."""
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import io
from contextlib import redirect_stdout

import autopilot


def check(status="PASS"):
    return SimpleNamespace(name="mock", status=status, detail="synthetic")


class PreflightIntegrationTests(unittest.TestCase):
    def test_eight_pass_allow(self):
        with patch("doctor_v07a.preflight", return_value=[check()] * 8) as f:
            with redirect_stdout(io.StringIO()):
                result = autopilot.enforce_v07a_preflight()
        self.assertEqual(len(result), 8)
        self.assertEqual(f.call_count, 1)

    def test_fail_blocks(self):
        with patch("doctor_v07a.preflight", return_value=[check()] * 7 + [check("FAIL")]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, "preflight stopped"):
                    autopilot.enforce_v07a_preflight()

    def test_warning_blocks(self):
        with patch("doctor_v07a.preflight", return_value=[check()] * 7 + [check("WARN")]):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, "preflight stopped"):
                    autopilot.enforce_v07a_preflight()

    def test_missing_check_blocks(self):
        with patch("doctor_v07a.preflight", return_value=[check()] * 7):
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, "Expected 8 checks"):
                    autopilot.enforce_v07a_preflight()

    def test_dry_run_skips_preflight(self):
        with patch.object(autopilot, "show_plan") as show, patch.object(autopilot, "enforce_v07a_preflight") as pre:
            with redirect_stdout(io.StringIO()):
                autopilot.run_worker(False, 1, 45, 0, 900)
            show.assert_called_once_with()
            pre.assert_not_called()

    def test_preflight_cli_reuses_gate(self):
        with patch.object(autopilot, "enforce_v07a_preflight") as pre:
            rc = autopilot.main(["preflight"])
            self.assertEqual(rc, 0)
            pre.assert_called_once_with()

    def test_live_no_ready_never_calls_gate_or_codex(self):
        # Existing scheduler must not call Codex or preflight when no task is runnable.
        with (patch.object(autopilot.harness, "require_git_base"),
              patch.object(autopilot.harness, "git", return_value=SimpleNamespace(stdout="")),
              patch.object(autopilot.harness.shutil, "which", return_value="codex"),
              patch.object(autopilot, "SingleWorker") as worker,
              patch.object(autopilot, "snapshot", return_value=([], {})),
              patch.object(autopilot, "ready_tasks", return_value=[]),
              patch.object(autopilot, "enforce_v07a_preflight") as pre,
              patch.object(autopilot, "call_harness") as codex,
              redirect_stdout(io.StringIO())):
            autopilot.run_worker(True, 1, 45, 0, 900)
            worker.assert_called_once()
            pre.assert_not_called()
            codex.assert_not_called()

    def test_preflight_blocks_before_real_task(self):
        task = {"id": "TEST-001", "priority": 1, "dependencies": []}
        state = {"TEST-001": {"status": "pending", "attempts": 0, "note": ""}}
        with (patch.object(autopilot.harness, "require_git_base"),
              patch.object(autopilot.harness, "git", return_value=SimpleNamespace(stdout="")),
              patch.object(autopilot.harness.shutil, "which", return_value="codex"),
              patch.object(autopilot, "SingleWorker"),
              patch.object(autopilot, "snapshot", return_value=([task], state)),
              patch.object(autopilot, "enforce_v07a_preflight", side_effect=RuntimeError("blocked")) as pre,
              patch.object(autopilot, "call_harness") as codex,
              redirect_stdout(io.StringIO())):
            with self.assertRaisesRegex(RuntimeError, "blocked"):
                autopilot.run_worker(True, 1, 45, 0, 900)
            pre.assert_called_once()
            codex.assert_not_called()


if __name__ == "__main__":
    unittest.main()
