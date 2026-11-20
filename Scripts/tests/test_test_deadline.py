"""Exercise the runner's real deadline loop with a simulated clock and process."""
import pathlib
import subprocess
import unittest

HELPER = pathlib.Path(__file__).resolve().parents[1] / 'lib' / 'test-deadline.sh'


class TestDeadline(unittest.TestCase):
    def run_clock(self, increment, exit_after, expected):
        script = '''
source "$1"
simulated_epoch=100
sleeps=0
date() { printf '%s\\n' "$simulated_epoch"; }
sleep() { sleeps=$((sleeps+1)); simulated_epoch=$((simulated_epoch+INCREMENT)); }
limit="$3"
kill() { [ "$sleeps" -lt "$limit" ]; }
INCREMENT="$2"
if keypath_wait_for_test_deadline 999 240 100; then result=0; else result=$?; fi
printf '%s %s' "$result" "$sleeps"
'''
        result = subprocess.run(
            ['bash', '-c', script, 'deadline-test', str(HELPER), str(increment), str(exit_after)],
            text=True, capture_output=True, check=True, timeout=5)
        self.assertEqual(result.stdout, expected)

    def test_sleep_jump_expires_on_first_wake(self):
        self.run_clock(1000, 100, '0 1')

    def test_normal_deadline(self):
        self.run_clock(1, 300, '0 240')

    def test_process_exit_does_not_timeout(self):
        self.run_clock(1, 2, '1 2')

    def test_already_exited(self):
        self.run_clock(1, 0, '1 0')
