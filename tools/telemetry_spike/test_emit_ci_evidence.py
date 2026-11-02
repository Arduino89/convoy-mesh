import io
import tempfile
import unittest
import zipfile
from pathlib import Path

from emit_ci_evidence import collect
from ci_native_trial import TrialBlocked


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

    def test_direct_export_preserves_duplicates_without_sdk_provenance(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            wire = root / 'direct-public/wire-retry'
            wire.mkdir(parents=True)
            row = '{"event_id":"synthetic-direct-000001","sequence":1}\n'
            (wire / 'received.jsonl').write_text(row + row)
            data, names = collect(root)
            path = 'direct-public/wire-retry/received.jsonl'
            self.assertIn(path, names)
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                self.assertEqual(len(archive.read(path).splitlines()), 2)

    def test_direct_export_rejects_unlisted_artifact_and_private_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            public = root / 'direct-public'
            public.mkdir()
            unexpected = public / 'diagnostic.log'
            unexpected.write_text('not public evidence')
            with self.assertRaises(TrialBlocked):
                collect(root)
            unexpected.unlink()
            (public / 'result.json').write_text('{"authorization":"example-secret"}')
            with self.assertRaises(TrialBlocked):
                collect(root)


if __name__ == '__main__':
    unittest.main()
