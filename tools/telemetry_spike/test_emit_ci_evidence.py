import io
import tempfile
import unittest
import zipfile
from pathlib import Path

from emit_ci_evidence import collect


class EvidenceEmitterTests(unittest.TestCase):
    def test_duplicate_key_cannot_hide_a_secret_in_archived_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            public = root / 'lab-public'
            public.mkdir()
            (public / 'result.json').write_text(
                '{"status":"https://example.invalid/private-auth","status":"PASSED"}')
            with self.assertRaises(ValueError):
                collect(root)

    def test_repeated_event_rows_remain_in_archive(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            normal = root / 'lab-public/normal'
            normal.mkdir(parents=True)
            row = '{"event_id":"synthetic-emitter-000001","sequence":1}\n'
            (normal / 'received.jsonl').write_text(row + row)
            data, names = collect(root)
            self.assertIn('SHA256SUMS.txt', names)
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                rows = archive.read('lab-public/normal/received.jsonl').splitlines()
                self.assertEqual(len(rows), 2)
                self.assertEqual(rows[0], rows[1])


if __name__ == '__main__':
    unittest.main()
