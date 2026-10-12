"""SQLite connections must close even when a statement or transaction fails."""
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import harness


class DatabaseLifecycleTests(unittest.TestCase):
    def test_connection_closed_on_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(harness, 'DATA', Path(tmp) / 'db.sqlite3'):
                with harness.db() as conn:
                    conn.execute('SELECT 1').fetchone()
                with self.assertRaises(sqlite3.ProgrammingError):
                    conn.execute('SELECT 1')

    def test_connection_closed_on_exception(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(harness, 'DATA', Path(tmp) / 'db.sqlite3'):
                try:
                    with harness.db() as conn:
                        conn.execute('INSERT INTO tasks (id,status) VALUES (?,?)', ('test', 'pending'))
                        raise ValueError('intentional test error')
                except ValueError:
                    pass
                with self.assertRaises(sqlite3.ProgrammingError):
                    conn.execute('SELECT 1')
                with harness.db() as check:
                    self.assertIsNone(check.execute('SELECT id FROM tasks WHERE id=?', ('test',)).fetchone())


if __name__ == '__main__':
    unittest.main()
