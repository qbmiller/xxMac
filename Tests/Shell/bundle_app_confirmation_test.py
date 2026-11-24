"""Test the real bundle confirmation block without building or installing anything."""
import os
from pathlib import Path
import select
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "bundle_app.sh").read_text()
CONFIRMATION = SCRIPT[SCRIPT.index('INSTALL_RESPONSE=""'):SCRIPT.index('\ncase "$INSTALL_RESPONSE" in')]
COMMAND = CONFIRMATION + '\nprintf "\\nRESULT=<%s>\\n" "$INSTALL_RESPONSE"\n'


class BundleConfirmationTests(unittest.TestCase):
    def run_prompt(self, text, *, automatic="0"):
        env = dict(os.environ, INSTALL_TO_APPLICATIONS=automatic,
                   APPLICATIONS_APP_PATH="/tmp/xxmac-confirmation-test.app")
        return subprocess.run(["/bin/bash", "-c", COMMAND], input=text,
                              text=True, capture_output=True, env=env, timeout=5)

    def test_build_time_returns_do_not_decline_installation(self):
        result = self.run_prompt("\n\n\ny\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RESULT=<y>", result.stdout)

    def test_explicit_no_after_blank_lines_is_respected(self):
        self.assertIn("RESULT=<n>", self.run_prompt("\n\nn\n").stdout)

    def test_invalid_answers_are_not_treated_as_no(self):
        self.assertIn("RESULT=<yes>", self.run_prompt("unexpected\nyes\n").stdout)

    def test_eof_skips_without_installing(self):
        result = self.run_prompt("")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("RESULT=<>", result.stdout)

    def test_explicit_automatic_install_still_works(self):
        self.assertIn("RESULT=<y>", self.run_prompt("", automatic="1").stdout)

    def test_terminal_waits_for_explicit_answer_after_queued_returns(self):
        master, slave = os.openpty()
        gate_read, gate_write = os.pipe()
        env = dict(os.environ, INSTALL_TO_APPLICATIONS="0",
                   APPLICATIONS_APP_PATH="/tmp/xxmac-confirmation-test.app")
        command = f'printf "BUILDING\\n"; IFS= read -r gate <&{gate_read};\n' + COMMAND
        process = subprocess.Popen(["/bin/bash", "-c", command], stdin=slave,
                                   stdout=slave, stderr=slave, env=env, pass_fds=(gate_read,))
        os.close(slave)
        os.close(gate_read)
        output = b""

        def wait_for(marker):
            nonlocal output
            deadline = time.monotonic() + 3
            while marker not in output and time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], max(0, deadline - time.monotonic()))
                if readable:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
            self.assertIn(marker, output)

        try:
            wait_for(b"BUILDING")
            os.write(master, b"\n\n\n")  # Key presses queued while building.
            os.write(gate_write, b"ready\n")  # Build completes and reaches confirmation.
            wait_for("是否覆盖原文件".encode())
            readable, _, _ = select.select([master], [], [], 0.2)
            if readable:
                try:
                    output += os.read(master, 4096)
                except OSError:
                    pass
            self.assertIsNone(process.poll(), output.decode(errors="replace"))
            self.assertNotIn(b"RESULT=", output)
            os.write(master, b"n\n")
            wait_for(b"RESULT=<n>")
            self.assertEqual(process.wait(timeout=3), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
            os.close(gate_write)


if __name__ == "__main__":
    unittest.main()
