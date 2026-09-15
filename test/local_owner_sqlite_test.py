"""Source contracts + actual SQLite SQL tests, NOT execution of Dart behavior."""
from pathlib import Path
import re
import sqlite3
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'lib/Services/local_study_data.dart'


class LocalOwnerSqliteTest(unittest.TestCase):
    def sql(self, name):
        match = re.search(r"static const " + name + r" = '''(.*?)''';", SOURCE.read_text(), re.S)
        self.assertIsNotNone(match, f'missing production SQL: {name}')
        assert match is not None  # Narrow for static checkers after unittest assertion.
        return match.group(1)

    def schema(self, db):
        db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE, password_hash TEXT, created_at TEXT)')
        for table in ('favorites', 'wrong_answers', 'quiz_history'):
            db.execute(f'CREATE TABLE {table} (user_id INTEGER, note TEXT)')
        db.commit()

    def test_durable_transaction_and_best_effort_preferences_contract(self):
        source = SOURCE.read_text()
        self.assertIn('local_study_state', source)
        self.assertIn('db.transaction<int>', source)
        self.assertIn('persistOwner', source)
        self.assertNotIn('return null;', source)
        self.assertNotIn('Could not persist local study ownership', source)
        self.assertIn('legacyVisibilityMessage', source)
        for token in ('txn.delete(', 'txn.update(tableUsers', 'DELETE FROM', 'UPDATE favorites', 'UPDATE wrong_answers', 'UPDATE quiz_history'):
            self.assertNotIn(token, source)

    def test_production_max_sql_reserves_every_orphan_id(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        self.schema(db)
        for maximum_table in ('users', 'favorites', 'wrong_answers', 'quiz_history'):
            with self.subTest(maximum_table=maximum_table), db:
                for table in ('users', 'favorites', 'wrong_answers', 'quiz_history'):
                    db.execute(f'DELETE FROM {table}')
                    col = 'id' if table == 'users' else 'user_id'
                    db.execute(f'INSERT INTO {table} ({col}) VALUES (?)', (900 if table == maximum_table else 17,))
                db.execute('INSERT INTO favorites (user_id) VALUES (NULL)')
                maximum = db.execute(self.sql('ownerHighWaterSql')).fetchone()[0]
                self.assertEqual(maximum, 900)
                before = {t: db.execute(f'SELECT * FROM {t}').fetchall() for t in ('favorites', 'wrong_answers', 'quiz_history')}
                # Python drives production SELECT; Dart insertion/control flow is not run.
                db.execute('INSERT INTO users (id, username) VALUES (?, ?)', (maximum + 1, 'local-901'))
                for t, rows in before.items():
                    self.assertEqual(db.execute(f'SELECT * FROM {t}').fetchall(), rows)

    def test_marker_and_owner_commit_restart_and_rollback_real_sqlite(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / 'synthetic.db')
            db = sqlite3.connect(path)
            self.schema(db)
            with db:
                db.execute(self.sql('ownerStateSql'))
                db.execute('INSERT INTO users (id, username) VALUES (43, "local")')
                db.execute('INSERT INTO local_study_state (id, user_id) VALUES (1, 43)')
            db.close()
            db = sqlite3.connect(path)
            try:
                self.assertEqual(db.execute('SELECT user_id FROM local_study_state WHERE id=1').fetchone(), (43,))
                with self.assertRaises(sqlite3.IntegrityError), db:
                    db.execute('INSERT INTO users (id, username) VALUES (44, "local-44")')
                    db.execute('INSERT INTO local_study_state (id, user_id) VALUES (1, 44)')
                self.assertEqual(db.execute('SELECT id FROM users').fetchall(), [(43,)])
            finally:
                db.close()

    def test_empty_high_water_is_zero(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        self.schema(db)
        self.assertEqual(db.execute(self.sql('ownerHighWaterSql')).fetchone()[0], 0)


if __name__ == '__main__':
    unittest.main()
