"""Real Windows child-tree termination, log release, and unrelated-process safety."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


@unittest.skipUnless(os.name == 'nt', 'Windows process handles')
class ProcessTree(unittest.TestCase):
    def test_descendant_log_is_released_and_neighbor_survives(self):
        from windows_process import terminate_tree, wait_log_released
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            signal = root / 'ready'
            log = root / 'child.log'
            neighbor = subprocess.Popen([sys.executable, '-c', 'import time;time.sleep(30)'],
                                        creationflags=subprocess.CREATE_NO_WINDOW)
            target = None
            try:
                program = ('import pathlib,subprocess,sys,time; '
                           'child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(30)"]); '
                           'pathlib.Path(' + repr(str(signal)) + ').write_text(str(child.pid)); time.sleep(30)')
                with log.open('wb') as output:
                    target = subprocess.Popen([sys.executable, '-c', program], stdout=output, stderr=output,
                                              creationflags=subprocess.CREATE_NO_WINDOW)
                    deadline = time.monotonic() + 15
                    while not signal.exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                    self.assertTrue(signal.exists(), 'Target tree did not become ready')
                    result = terminate_tree(target)
                    self.assertTrue(result['waited_descendant_pids'])
                    self.assertIsNotNone(target.poll())
                    self.assertIsNone(neighbor.poll(), 'Unrelated process was terminated')
                wait_log_released(log)
                renamed = root / 'released.log'
                log.rename(renamed)  # Windows rejects this if a descendant still holds the log.
                self.assertTrue(renamed.is_file())
            finally:
                if target is not None and target.poll() is None:
                    terminate_tree(target)
                if neighbor.poll() is None:
                    terminate_tree(neighbor)


if __name__ == '__main__':
    unittest.main()
