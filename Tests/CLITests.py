"""Synthetic original-JavaScript comparison and real terminal input checks."""
import ctypes
import fcntl
import json
import os
from pathlib import Path
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build/cli'
BINARY = BUILD / 'pwdhash-test'
PASSWORD = b'SyntheticPassword9!'

# Results of the unmodified website JavaScript for PASSWORD. A notice must never change a result,
# and a plain name, in any letter case, must never get a notice.
PLAIN = {
    'example.com': 'HREoUO+dWf2L91PiQrbuC',
    'bank.example': 'Dxc6tyYqnOvqKOYidzE+m',
    'example.ABCD': '6D9f3UnzPT6ma8G+xPdc5',
    'Mail.Example-Site_1.QwErTy9': 'nsng+A4Bm6e0dAZzVypJd',
}
SILENT = [*PLAIN, 'https://login.example.com/path', 'http://www.example.co.uk/a/b', 'localhost']
CAUTIONED = [
    ('https://evil.example#.bank.example', 'Dxc6tyYqnOvqKOYidzE+m', ['contains "#"', 'may not be the site a link opens']),
    ('https://evil.example?next=www.bank.example', 'Dxc6tyYqnOvqKOYidzE+m', ['contains "?"']),
    ('https://evil.example\\.bank.example/login', 'Dxc6tyYqnOvqKOYidzE+m', ['contains "\\"']),
    ('https://user@example.com/', 'aCx935fA2NLK3Ix+fRXMH', ['contains "@"', 'user name']),
    ('example.com:8443', 'bl3nJ3oPJ7+V42W5X8fDC', ['contains ":"', 'port']),
    ('www.example.com:8443', 'bl3nJ3oPJ7+V42W5X8fDC', ['contains ":"', 'port']),
    ('HTTPS://www.example.com/', '/o2+nNZeVM2o0jTcjObC/', ['only lowercase', '"HTTPS:"']),
    ('example%2ecom', 'o4RoS4kxbyFDwdMyq5gn+', ['contains "%"']),
    (' example.com', 'aGnY1Ts7lGn6He+WtRfFd', ['contains a space', 'Nothing is trimmed']),
    ('example.com\t', 'TSPV4D+PZkHjs7K01BNcI', ['contains a tab']),
    ('b\u0161nk.example', 'Dxc6tyYqnOvqKOYidzE+m', ['a non-ASCII character (U+0161)', 'different names can give the same password']),
    ('exam\u200bple.com', '2PNaDJ+f410s6eWgz3VYK', ['a non-ASCII character (U+200B)']),
]


class CLITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        source = str(ROOT / 'src/cli/pwdhash.c')
        flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Wpedantic', '-Werror']
        compiler = os.environ.get('CC', 'cc')
        subprocess.run([compiler, *flags, source, '-o', str(BINARY)], check=True)
        cls.timeout_binary = BUILD / 'pwdhash-timeout-test'
        subprocess.run([compiler, *flags, '-DPWDHASH_IDLE_SECONDS=1', source, '-o', str(cls.timeout_binary)], check=True)
        library = BUILD / ('libpwdhash.dylib' if sys.platform == 'darwin' else 'libpwdhash.so')
        shared_flags = ['-dynamiclib'] if sys.platform == 'darwin' else ['-shared', '-fPIC']
        subprocess.run([compiler, *flags, *shared_flags, '-DPWDHASH_NO_MAIN', source, '-o', str(library)], check=True)
        cls.library = ctypes.CDLL(str(library))
        cls.library.pwdhash_domain.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(ctypes.c_size_t)]
        cls.library.pwdhash_derive.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.POINTER(ctypes.c_size_t)]
        cls.library.pwdhash_site_part.argtypes = cls.library.pwdhash_domain.argtypes
        cls.library.pwdhash_site_caution.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
        cls.library.pwdhash_site_caution.restype = ctypes.c_size_t
        cls.vectors = json.loads((ROOT / '.build/reference-vectors.json').read_text())

    def site_part(self, address):
        site, length = ctypes.create_string_buffer(len(address) + 1), ctypes.c_size_t()
        code = self.library.pwdhash_site_part(address, len(address), site, len(site), ctypes.byref(length))
        return code, site.raw[:length.value]

    def notice(self, address):
        code, site = self.site_part(address)
        self.assertEqual(code, 0, address)
        text = ctypes.create_string_buffer(b'\xff' * 512, 512)
        length = self.library.pwdhash_site_caution(site, len(site), text, len(text))
        self.assertEqual(text.raw[length], 0, address)
        return text.raw[:length].decode('ascii')

    def run_stdin(self, address, data, *options):
        return subprocess.run([str(BINARY), '--stdin', *options, '--', address], input=data, capture_output=True, timeout=20)

    def test_original_javascript_vectors(self):
        for index, vector in enumerate(self.vectors):
            address = vector['address'].encode('utf-8')
            domain = ctypes.create_string_buffer(len(address) + 1)
            domain_length = ctypes.c_size_t()
            code = self.library.pwdhash_domain(address, len(address), domain, len(domain), ctypes.byref(domain_length))
            if vector['domain'] is None:
                self.assertEqual(code, 1, index)
                continue
            self.assertEqual(code, 0, index)
            self.assertEqual(domain.raw[:domain_length.value], vector['domain'].encode('utf-8'), index)
            password = vector['password'].encode('utf-8')
            result = ctypes.create_string_buffer(26)
            length = ctypes.c_size_t()
            code = self.library.pwdhash_derive(domain, domain_length.value, password, len(password), result, ctypes.byref(length))
            self.assertEqual(code, 0, index)
            self.assertEqual(result.raw[:length.value], vector['result'].encode('utf-8'), index)

    def test_rfc_md5_vectors(self):
        self.assertEqual(self.library.pwdhash_self_test(), 0)
        subprocess.run([str(BINARY), '--self-test'], check=True, capture_output=True)

    def test_rejects_invalid_utf8(self):
        for invalid in [b'\xc0\x80', b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\x80', b'\xe2\x82']:
            result, length = ctypes.create_string_buffer(26), ctypes.c_size_t()
            code = self.library.pwdhash_derive(b'example.com', 11, invalid, len(invalid), result, ctypes.byref(length))
            self.assertEqual(code, 3)
            self.assertEqual(length.value, 0)
            self.assertEqual(result.raw, bytes(26))

    def test_stdin_and_hex(self):
        for vector in self.vectors[:29 * 6:5]:
            if not vector['password'] or '\n' in vector['password'] or vector['result'] is None:
                continue
            for hexadecimal in [False, True]:
                args = [str(BINARY), '--stdin', '--no-newline']
                if hexadecimal:
                    args.append('--hex')
                args.extend(['--', vector['address']])
                result = subprocess.run(args, input=vector['password'].encode('utf-8') + b'\n', capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                expected = vector['result'].encode('utf-8')
                self.assertEqual(result.stdout, expected.hex().encode() if hexadecimal else expected)

    def test_rejects_password_argument(self):
        result = subprocess.run([str(BINARY), 'example.com', 'SyntheticSecret'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(b'SyntheticSecret', result.stdout + result.stderr)

    def terminal(self, data, binary=None, interrupt=None, arguments=('example.com',), prompt=b'Site Password: '):
        import pty
        master, slave = pty.openpty()
        original = termios.tcgetattr(slave)
        status_read, status_write = os.pipe()
        release_read, release_write = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.close(status_read)
            os.close(release_write)
            os.login_tty(slave)
            executable = str(binary or BINARY)
            target = os.fork()
            if target == 0:
                os.close(status_write)
                os.close(release_read)
                os.execv(executable, [executable, *arguments])
            os.write(status_write, struct.pack('!II', 0, target))
            _, target_status, usage = os.wait4(target, 0)
            os.write(status_write, struct.pack('!II', 2, int((usage.ru_utime + usage.ru_stime) * 1000)))
            os.write(status_write, struct.pack('!II', 1, target_status))
            os.read(release_read, 1)
            os._exit(0)
        os.close(status_write)
        os.close(release_read)
        output = bytearray()
        deadline = time.monotonic() + 8
        sent = False
        status = None
        target_pid = None
        messages = bytearray()
        try:
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master, status_read], [], [], 0.05)
                if master in readable:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        pass
                if status_read in readable:
                    messages.extend(os.read(status_read, 16))
                    while len(messages) >= 8:
                        kind, value = struct.unpack('!II', messages[:8])
                        del messages[:8]
                        if kind == 0:
                            target_pid = value
                        elif kind == 2:
                            self.processor_milliseconds = value
                        else:
                            status = value
                if not sent and prompt in output and target_pid is not None:
                    os.write(master, data)
                    if interrupt is not None:
                        time.sleep(0.05)
                        os.kill(target_pid, interrupt)
                    sent = True
                if status is not None:
                    while select.select([master], [], [], 0)[0]:
                        try:
                            chunk = os.read(master, 65536)
                        except OSError:
                            break
                        if not chunk:
                            break
                        output.extend(chunk)
                    break
            self.assertIsNotNone(status, f'Terminal child did not finish: {output!r}')
            restored = termios.tcgetattr(slave)
            self.assertEqual(restored[3] & (termios.ECHO | termios.ICANON), original[3] & (termios.ECHO | termios.ICANON))
            return bytes(output), os.waitstatus_to_exitcode(status)
        finally:
            if status is None:
                if target_pid is not None:
                    os.kill(target_pid, signal.SIGKILL)
            os.write(release_write, b'x')
            os.waitpid(pid, 0)
            os.close(status_read)
            os.close(release_write)
            os.close(master)
            os.close(slave)

    def test_hidden_prompt_and_unicode_backspace(self):
        password = 'SyntheticPassword9!'
        output, code = self.terminal(password.encode() + 'é'.encode() + b'\x7f\n')
        self.assertEqual(code, 0)
        self.assertNotIn(password.encode(), output)
        expected = subprocess.run([str(BINARY), '--stdin', 'example.com'], input=password.encode() + b'\n', capture_output=True, check=True).stdout.strip()
        self.assertIn(expected, output)

    def test_timeout_restores_terminal(self):
        output, code = self.terminal(b'IncompleteSecret', binary=self.timeout_binary)
        self.assertNotEqual(code, 0)
        self.assertIn(b'Input cleared', output)
        self.assertNotIn(b'IncompleteSecret', output)

    def test_interrupt_restores_terminal(self):
        output, code = self.terminal(b'IncompleteSecret', interrupt=signal.SIGINT)
        self.assertEqual(code, 130)
        self.assertNotIn(b'IncompleteSecret', output)


    def test_interrupt_at_the_address_prompt(self):
        output, code = self.terminal(b'exam', arguments=(), prompt=b'Site Address: ', interrupt=signal.SIGINT)
        self.assertEqual(code, 130)
        self.assertNotIn(b'Site Password', output)

    def test_waiting_at_a_prompt_uses_no_processor_time(self):
        # poll() rejects terminal devices on macOS, which made the wait a busy loop on a full core.
        output, code = self.terminal(b'IncompleteSecret', binary=self.timeout_binary)
        self.assertIn(b'Input cleared', output)
        self.assertLess(self.processor_milliseconds, 250, 'The prompt used processor time while waiting')

    def test_plain_names_get_no_notice(self):
        for address in SILENT:
            self.assertEqual(self.notice(address.encode()), '', address)
        for address, expected in PLAIN.items():
            result = self.run_stdin(address, PASSWORD + b'\n', '--no-newline')
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected.encode(), b''), address)

    def test_unusual_addresses_get_a_notice_and_the_original_result(self):
        for address, expected, phrases in CAUTIONED:
            notice = self.notice(address.encode('utf-8'))
            self.assertTrue(notice.startswith('Caution: '), address)
            self.assertTrue(notice.isprintable(), address)
            for phrase in phrases:
                self.assertIn(phrase, notice, address)
            result = self.run_stdin(address, PASSWORD + b'\n', '--no-newline')
            self.assertEqual((result.returncode, result.stdout), (0, expected.encode()), address)
            self.assertEqual(result.stderr.decode('ascii'), notice + '\n', address)

    def test_notice_reads_the_site_part_the_algorithm_reads(self):
        for vector in self.vectors:
            address = vector['address'].encode('utf-8')
            code, site = self.site_part(address)
            if vector['domain'] is None:
                self.assertEqual(code, 1, address)
            else:
                self.assertEqual(code, 0, address)
                self.assertTrue(site.endswith(vector['domain'].encode('utf-8')), address)
                self.assertNotIn(b'/', site, address)

    def test_notice_survives_any_bytes_and_any_room(self):
        for site in [b'\xff.example', b'a\xc0\x80.example', b'\x00.example', b'\x1b[2Jexample.com', b'x' * 300 + b':', b'\xe2\x80\xa8.example', b'\x7f.example']:
            for room in [1, 2, 20, 80, 512]:
                text = ctypes.create_string_buffer(b'\xff' * 600, 600)
                length = self.library.pwdhash_site_caution(site, len(site), text, room)
                self.assertLess(length, room)
                self.assertEqual(text.raw[length], 0)
                self.assertEqual(text.raw[room:], b'\xff' * (600 - room))
                self.assertTrue(all(0x20 <= byte < 0x7f for byte in text.raw[:length]), site)
                self.assertTrue(room < 2 or length > 0, site)

    def test_invalid_address_stops_before_the_password_is_read(self):
        result = subprocess.run([str(BINARY), '--stdin', '--', b'\xffexample.com'], input=b'', capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, b'')
        self.assertIn(b'not valid UTF-8 (0xFF)', result.stderr)
        self.assertIn(b'Input must be valid UTF-8.', result.stderr)
        self.assertNotIn(b'Password input', result.stderr)
        output, code = self.terminal(b'', arguments=(b'\xffexample.com',))
        self.assertEqual(code, 1)
        self.assertNotIn(b'Site Password', output)

    def test_carriage_return_is_hashed_and_announced(self):
        unix = self.run_stdin('example.com', PASSWORD + b'\n', '--no-newline')
        self.assertEqual((unix.returncode, unix.stdout, unix.stderr), (0, PLAIN['example.com'].encode(), b''))
        windows = self.run_stdin('example.com', PASSWORD + b'\r\n', '--no-newline')
        self.assertEqual(windows.returncode, 0)
        self.assertIn(b'ends with a carriage return', windows.stderr)
        domain, result, length = b'example.com', ctypes.create_string_buffer(26), ctypes.c_size_t()
        self.assertEqual(self.library.pwdhash_derive(domain, len(domain), PASSWORD + b'\r', len(PASSWORD) + 1, result, ctypes.byref(length)), 0)
        self.assertEqual(windows.stdout, result.raw[:length.value])
        self.assertNotEqual(windows.stdout, unix.stdout)

    def test_nul_bytes_are_announced_when_the_result_is_piped(self):
        vector = next(v for v in self.vectors if v['result'] and '\x00' in v['result'] and v['password'] and '\n' not in v['password'])
        raw = self.run_stdin(vector['address'], vector['password'].encode('utf-8') + b'\n', '--no-newline')
        self.assertEqual((raw.returncode, raw.stdout), (0, vector['result'].encode('utf-8')))
        self.assertIn(b'invisible NUL bytes', raw.stderr)
        exact = self.run_stdin(vector['address'], vector['password'].encode('utf-8') + b'\n', '--hex')
        self.assertEqual((exact.returncode, exact.stdout), (0, vector['result'].encode('utf-8').hex().encode() + b'\n'))
        self.assertNotIn(b'NUL', exact.stderr)

    def test_password_arriving_in_pieces(self):
        process = subprocess.Popen([str(BINARY), '--stdin', '--no-newline', 'example.com'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            for piece in [PASSWORD[:5], PASSWORD[5:], b'\n']:
                process.stdin.write(piece)
                process.stdin.flush()
                time.sleep(0.15)
            output, errors = process.communicate(timeout=20)
        finally:
            process.kill()
            process.wait()
        self.assertEqual((process.returncode, output, errors), (0, PLAIN['example.com'].encode(), b''))

    def test_shared_standard_input_is_left_blocking(self):
        # The flag belongs to the open file, which the shell and other programs share. Changing it
        # would outlive this program if it were killed while waiting.
        reader, writer = os.pipe()
        process = subprocess.Popen([str(BINARY), '--stdin', 'example.com'], stdin=reader, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            os.write(writer, PASSWORD[:4])
            deadline = time.monotonic() + 0.6
            while time.monotonic() < deadline:
                self.assertEqual(fcntl.fcntl(reader, fcntl.F_GETFL) & os.O_NONBLOCK, 0)
                self.assertIsNone(process.poll())
                time.sleep(0.01)
            process.kill()
            process.communicate(timeout=20)
            self.assertEqual(fcntl.fcntl(reader, fcntl.F_GETFL) & os.O_NONBLOCK, 0)
        finally:
            process.kill()
            process.wait()
            process.stdout.close()
            process.stderr.close()
            os.close(reader)
            os.close(writer)

    def test_closed_output_reports_the_signal(self):
        reader, writer = os.pipe()
        os.close(reader)
        try:
            result = subprocess.run([str(BINARY), '--stdin', 'example.com'], input=PASSWORD + b'\n', stdout=writer, stderr=subprocess.PIPE, timeout=20)
        finally:
            os.close(writer)
        self.assertEqual(result.returncode, 128 + signal.SIGPIPE)

    def test_help_names_the_argument_exposure(self):
        text = subprocess.run([str(BINARY), '--help'], capture_output=True, check=True).stdout
        self.assertIn(b'shell history', text)
        self.assertIn(b'standard error', text)


if __name__ == '__main__':
    unittest.main()
