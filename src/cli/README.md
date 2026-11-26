# Standalone PwdHash for macOS and Linux

One C11/POSIX source file, using the C library only. No OpenSSL, libcrypto,
package manager, network, or external file is needed to run it.

```sh
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -fstack-protector-strong pwdhash.c -o pwdhash
./pwdhash
```

With no arguments, it prompts for the site address and then the hidden site
password. This keeps both inputs out of the shell command line. You can also
pass a site address: `./pwdhash example.com`. An address passed this way can be
seen by other programs and users of the computer while the command runs (for
example with `ps`), and the shell usually saves it in its history. Leave it out
to be prompted instead. The address prompt shows what you type; only the
password is hidden.

The password is read from the controlling terminal, with echo disabled.
Backspace deletes a UTF-8 character; Ctrl-U clears the entered password.
Ctrl-C cancels and restores the terminal. Five minutes without input cancels
the prompt, and the program overwrites its input, digest, and output buffers
before exiting. The clock includes sleep on macOS and Linux where supported;
deadlines are checked whenever the process runs.

Before reading input, the CLI sets its core file size limit to zero. It exits if
the limit cannot be set. Linux crash handlers that receive dumps through a pipe
can bypass this limit. The program does not lock its memory, so the operating
system can still move it to swap.

The result is written to standard output, directly from a buffer the program
then overwrites. Your terminal or a program receiving that output can retain it.
The CLI itself creates no files or history.

Everything else goes to standard error, so it never mixes with a piped or
captured result:

- A caution when the site part of the address holds something a plain site name
  does not: a space or control character, one of `# % : ? @ \`, a non-ASCII
  character, or a scheme other than lowercase `http://` and `https://`. Such an
  address usually comes from a pasted link, and the original algorithm can hash
  it for a different site than the one a browser would open. A plain name such
  as `example.com` or `Example.Site-1`, in any letter case, gets no caution.
- A caution when a `--stdin` password line ends in a carriage return, which a
  Windows line ending adds. It is hashed as part of the password.
- A note when the result contains invisible NUL bytes, which the original
  produces for long passwords. `--hex` shows the exact bytes instead.

A caution never changes or withholds the result: the output is always what the
original website produces for the same input. An address whose hashing domain
is not valid UTF-8 is refused before the password is asked for.

The exit status is 0 on success and 1 for an error, an empty input, or the idle
timeout. A signal that interrupts the program, at either prompt or before the
result is written, gives 128 plus the signal number. So does a closed output
pipe (141).

Options:

- `--stdin`: read one UTF-8 password line from standard input instead of the
  terminal. Intended for a secure pipe, not a password argument or environment
  variable. A newline ends the input; the limit is 65,536 input bytes.
- `--hex`: output the exact result bytes in hexadecimal. This is useful because
  the original website can produce embedded NULs for long passwords.
- `--no-newline`: omit the usual trailing output newline.
- `--self-test`: check the MD5 implementation against standard digest vectors.
- `--license`: show the complete original PwdHash BSD notice.
- `--help`, `--version`: show help or the version.

The algorithm deliberately matches Stanford PwdHash, including one leading
`@@` removal, historical domain rules, case and ports, UTF-16 low-byte encoding,
and long-password quirks. Passwords are UTF-8 at the terminal boundary.

Personal hobby project by Nenad Micic, based on
[Stanford PwdHash](https://pwdhash.github.io/website/).
Contact: [pwdhash@nmic.app](mailto:pwdhash@nmic.app).
