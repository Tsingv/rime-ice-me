import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "sync_upstream", Path(__file__).resolve().parents[1] / "sync_upstream.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class SyncRulesTest(unittest.TestCase):
    def test_enable_and_preserve_upstream_changes(self):
        source = 'version: "new"\nimport_tables:\n  - cn_dicts/8105\n  # - cn_dicts/41448  # 大字表\n  - cn_dicts/base\n'
        result = sync.enable_large_table(source)
        self.assertIn('version: "new"', result)
        self.assertIn('  - cn_dicts/41448  # 大字表', result)
        self.assertEqual(sync.enable_large_table(result), result)

    def test_changed_structure_fails_closed(self):
        for text in ('  - cn_dicts/8105\n', '  - cn_dicts/41448\n  - cn_dicts/8105\n',
                     '  - cn_dicts/8105\n  - cn_dicts/base\n  - cn_dicts/41448\n',
                     '  - cn_dicts/8105\n  - cn_dicts/41448\n  - cn_dicts/41448\n'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                sync.enable_large_table(text)

    def test_personal_and_repository_protection(self):
        for path in sync.PROTECTED | {'rime_ice.custom.yaml', 'double_pinyin_flypy.custom.yaml',
                                      '.github/workflows/sync-upstream.yml', 'radical_pinyin.dict.yaml'}:
            self.assertTrue(sync.protected(path), path)
        for path in ('cn_dicts/base.dict.yaml', 'rime_ice.dict.yaml', 'rime_ice.schema.yaml'):
            self.assertFalse(sync.protected(path), path)
