"""Offline source contracts only: these are NOT Flutter behavior tests."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LocalOnlyContractTest(unittest.TestCase):
    def test_removed_account_and_placeholder_surface(self):
        sources = '\n'.join(p.read_text() for p in (ROOT / 'lib').rglob('*.dart'))
        for token in ('Supabase', 'supabase_flutter', 'AuthService', 'SyncService',
                      'ExamVIPScreen', 'MustCorrectScreen', 'MustWrongScreen',
                      'DifficultScreen', 'ProfileScreen', 'LoginRegisterScreen',
                      'CodeRedeemScreen', 'VipUpgradeScreen'):
            with self.subTest(token=token):
                self.assertNotIn(token, sources)
        self.assertNotIn('supabase_flutter:', (ROOT / 'pubspec.yaml').read_text())

    def test_orphan_account_provider_is_removed(self):
        self.assertFalse((ROOT / 'lib/Screen/General/user_provider.dart').exists())
        sources = '\n'.join(p.read_text() for p in (ROOT / 'lib').rglob('*.dart'))
        for token in ('UserProvider', 'user_provider.dart', 'isLoggedIn', 'logout('):
            with self.subTest(token=token):
                self.assertNotIn(token, sources)

    def test_orphan_supabase_clients_are_removed(self):
        for name in ('sanitizing_client_io.dart', 'sanitizing_client_stub.dart'):
            with self.subTest(file=name):
                self.assertFalse((ROOT / 'lib/utils' / name).exists())
        sources = '\n'.join(p.read_text() for p in (ROOT / 'lib').rglob('*.dart'))
        self.assertNotIn('createSanitizedClient', sources)
        self.assertNotIn('sanitizing_client', sources)

    def test_local_study_routes_remain(self):
        home = (ROOT / 'lib/Screen/Homepage.dart').read_text()
        for screen in ('ExamScreen', 'QuestionBankScreen', 'PracticeScreen',
                       'FavoritesScreen', 'WrongReviewScreen', 'StudyRecordScreen',
                       'DictionaryScreen', 'SettingsScreen'):
            self.assertIn(screen, home)
        self.assertIn('UpdateService.checkUpdate(context)', home)
        self.assertIn('TopBanner()', home)
        self.assertIn('新闻内容正在开发中', home)
        self.assertTrue((ROOT / 'lib/Screen/General/exam_general.dart').exists())

    def test_every_owner_entry_uses_same_local_service(self):
        for name in ('exam_general', 'favorites_screen', 'wrong_review_screen',
                     'study_record_screen'):
            with self.subTest(screen=name):
                source = (ROOT / f'lib/Screen/General/{name}.dart').read_text()
                self.assertIn('LocalStudyData.instance.ensureOwner()', source)

    def test_initializers_handle_storage_errors_and_offer_retry(self):
        for name, method in (('exam_general', '_loadUser'),
                             ('favorites_screen', '_loadData'),
                             ('wrong_review_screen', '_loadData'),
                             ('study_record_screen', '_load')):
            with self.subTest(screen=name):
                source = (ROOT / f'lib/Screen/General/{name}.dart').read_text()
                body = source.split(f'Future<void> {method}() async {{', 1)[1]
                body = body.split('\n  }', 1)[0]
                self.assertIn('try {', body)
                self.assertLess(body.index('try {'), body.index('ensureOwner()'))
                self.assertIn('catch (e)', body)
                self.assertIn('if (!mounted) return;', body.split('catch (e)', 1)[1])
                self.assertIn(f'onPressed: {method}', source)
                self.assertIn("'重试'", source)
                if name != 'exam_general':
                    self.assertIn('finally {', body)
                    self.assertIn('_isLoading = false', body.split('finally {', 1)[1])
                    self.assertIn('_loadError != null', source)
                    self.assertIn('Text(_loadError!)', source)
                else:
                    self.assertIn('await _updateFavoriteStatus();', body)

    def test_unsaved_exam_requires_warning_before_results(self):
        source = (ROOT / 'lib/Screen/General/exam_general.dart').read_text()
        body = source.split('Future<void> _finishExam() async {', 1)[1]
        body = body.split('\n  }', 1)[0]
        self.assertIn('bool saved = false;', body)
        self.assertLess(body.index('await DatabaseHelper.instance.saveQuizAttempt('),
                        body.index('saved = true;'))
        self.assertIn('if (!saved)', body)
        self.assertIn('await showDialog<void>(', body)
        self.assertIn('本次成绩未保存', body)
        self.assertIn('仅查看本次成绩', body)
        self.assertLess(body.index('await showDialog<void>('),
                        body.index('Navigator.pushReplacement('))
        self.assertIn('if (_isFinishing) return;', body)

    def test_no_destructive_history_retention_or_upgrade(self):
        source = (ROOT / 'lib/database/database_helper.dart').read_text()
        self.assertNotIn('DROP TABLE', source)
        self.assertNotIn('trimQuizHistory', source)
        self.assertNotIn('trimQuizHistory',
                         (ROOT / 'lib/Screen/General/exam_general.dart').read_text())

    def test_relative_dart_imports_exist(self):
        for path in (ROOT / 'lib').rglob('*.dart'):
            for target in re.findall(r"(?:import|export)\s+'([^']+)'", path.read_text()):
                if ':' not in target:
                    self.assertTrue((path.parent / target).exists(), (path, target))
                elif target.startswith('package:italian_driving_app/'):
                    self.assertTrue((ROOT / 'lib' / target.split('/', 1)[1]).exists(),
                                    (path, target))


if __name__ == '__main__':
    unittest.main()
