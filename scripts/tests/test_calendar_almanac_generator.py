import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[2]

class AlmanacGeneratorTests(unittest.TestCase):
    def test_output_is_identical_across_python_hash_seeds(self):
        with tempfile.TemporaryDirectory() as directory:
            outputs = []
            for seed in ('1', '2'):
                target = Path(directory) / seed
                subprocess.run([sys.executable, str(ROOT / 'scripts/generate_calendar_almanac.py'),
                                '--start-year', '2026', '--end-year', '2026',
                                '--output-directory', str(target)],
                               env={**os.environ, 'PYTHONHASHSEED': seed}, check=True, capture_output=True)
                payload = (target / '2026.json.deflate').read_bytes()
                manifest = json.loads((target / 'manifest.json').read_text())
                self.assertEqual(manifest['years']['2026']['sha256'], hashlib.sha256(payload).hexdigest())
                records = json.loads(zlib.decompress(payload, -15))
                self.assertEqual(len(records), 365)
                self.assertEqual(records['2026-02-17']['lunarDay'], 1)
                outputs.append(payload)
            self.assertEqual(outputs[0], outputs[1])

if __name__ == '__main__':
    unittest.main()
