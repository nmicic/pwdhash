# PwdHash

Native, offline clients for the original
[Stanford PwdHash website](https://pwdhash.github.io/website/), developed by
Nenad Micic. Use the same site address and original password to reproduce a
site-specific password. The [compatibility notes](#compatibility-and-tests)
explain the legacy rules and their limits.

[Project website](https://nmic.app/pwdhash/) ·
[App Store](https://apps.apple.com/us/app/pwdhash/id6827518713) ·
[Google Play](https://play.google.com/store/apps/details?id=app.nmic.pwdhash)

The native macOS release is in App Review. See the project website for availability.

Contact: [pwdhash@nmic.app](mailto:pwdhash@nmic.app).

## Source layout

```text
src/
  IOS/       Existing native iPhone app and Xcode project
  Android/   Native Android app, using standard Java/Android APIs
  MacOS/     Native AppKit macOS app
  cli/       Standalone C11/POSIX terminal program
Reference/   Unmodified original website JavaScript, used only in tests
Tests/       Compatibility, terminal, desktop, and Android device checks
scripts/     Build, install, and test commands
```

The GUI clients use the identifier `app.nmic.pwdhash`. The Apple clients share
the Swift engine and idle deadline in `src/IOS/PwdHash/Core/`. Android has a
native Java port; the C tool includes its own MD5/HMAC implementation and needs
only the C library. No client contains a browser or JavaScript runtime.

## Build and run

From the repository root:

| Client | Build | Run or install |
| --- | --- | --- |
| Terminal | `make cli` (also the default `make`) | `.build/cli/pwdhash` |
| macOS | `make macos` | `open .build/macos/PwdHash.app` |
| iPhone | `make ios` | `make install` with a connected phone |
| Android | `make android` | `make install-android` with a connected phone |

`make build` is an alias for the iPhone build. `make simulator` builds
the iPhone simulator version. Local build outputs go to the ignored `.build/`
directory. Store signing uses credentials configured outside the repository.

The terminal program is one self-contained file. To build it separately on
Linux or macOS, without the rest of this repository:

```sh
cc -std=c11 -O2 -Wall -Wextra -Wpedantic -fstack-protector-strong src/cli/pwdhash.c -o pwdhash
./pwdhash
```

It prompts for the site address and a hidden site password. Passing the site
as an argument is optional, and an argument can be seen by other programs on
the computer and is usually saved in shell history. The password is never an
argument or environment variable. `--stdin` reads a UTF-8 password line from a
pipe. `--hex` exposes the exact legacy result bytes, including any invisible
NULs. Cautions about an unusual address go to standard error and never change
the result. `--help`, `--license`, and `--self-test` are available. See the
[terminal guide](src/cli/README.md).

Apple builds require Xcode's installed SDKs. The iPhone icon-generation step
uses Python 3/Pillow. The macOS build uses Apple's asset compiler and needs no
third-party build dependency. Installation on an iPhone requires your own
development signing identity and profile. `make macos` builds a universal app (Apple
silicon and Intel) with ad-hoc local signing and Hardened Runtime, and
`make verify-macos` checks it. The [macOS README](src/MacOS/README.md)
covers distribution signing and uploading through Xcode. The Xcode projects
are `src/IOS/PwdHash.xcodeproj` and `src/MacOS/PwdHash.xcodeproj`.
No third-party runtime libraries are needed.

Android builds require JDK 17, Android SDK platform 36, build tools 35.0.0 and
platform-tools. The wrapper pins Gradle 8.13 and its checksum; AGP is 8.13.2.
Set `JAVA_HOME` and `ANDROID_HOME`. Optional machine-specific exports can be
kept in ignored `.build/android-env.sh`; `GRADLE_BIN` can select an existing
Gradle 8.13 executable. Android has no third-party runtime dependencies and
requests no Internet permission.

The Android APK is `.build/android/app/outputs/apk/debug/app-debug.apk`.
`sh scripts/build-android.sh bundleRelease` produces an AAB under
`.build/android/app/outputs/bundle/release/`. Store signing and submission are
separate release steps; configure a private upload key before Play distribution.

Platform details: [iPhone](src/IOS/README.md), [Android](src/Android/README.md),
[macOS](src/MacOS/README.md), [terminal](src/cli/README.md).

## GUI workflow

Enter **Site Address** and **Site Password**, then press **Generate** and
**Copy**. Both passwords start hidden. Hold an eye to reveal; releasing or
leaving the active app hides it again. Inputs remain editable while hidden
and while revealed.

Editing the address keeps the site password; editing the password keeps the
address. Either edit clears the old result and disables Copy until Generate
is pressed again. **Clear**, the background option, and expandable
**About & credits** are all on the same screen. The view scrolls for smaller
windows, larger text, the keyboard, and expanded credits.

About includes the author credit, platform support and privacy links, legacy
security guidance, contact email, original contributors, project link, and the
full original BSD notice. Email opens a blank message addressed to
`pwdhash@nmic.app`; the user writes and sends it. Website links open in the
user's browser. These actions use the same ordinary background-clearing behavior
as any other app switch.

## Privacy and platform behavior

The apps have no accounts, credential files, databases, preferences, saved
sessions, analytics, or history. Five idle minutes clears the current GUI
fields, generated result, domain hint, and undo state. Continuous clocks include
device sleep. Expiry is checked before accepting an action or showing a returning
session. The terminal tool clears its byte buffers on exit and cancels input
after five idle minutes. Terminal output can be retained by the user's terminal
or the program receiving it.

**Clear when leaving app** starts on. It clears the current fields immediately
when the phone app enters the background or the Mac app becomes inactive.
Turning it off lets you reuse the current inputs while switching apps. iOS and
Android can suspend background processes; with that option off, expiry is
enforced when the app next runs and before the session is displayed or used.
That mode cannot promise physical erasure at exactly five minutes while suspended.

| Client | Clipboard behavior |
| --- | --- |
| iOS | Local-only copy, with OS-managed removal after 60 seconds. |
| macOS | Current-host-only copy, concealed/transient markers, and a 60-second cleanup timer while running. Copy also clears on normal quit, sleep, or screen lock. |
| Android | Sensitive-content flag and a 60-second foreground cleanup deadline. Android restricts background clipboard access and controls OS auto-expiry; the screen explains this limit. |

Clear and idle expiry check whether the app owns the copy before removing it.
On macOS the ownership check and removal are separate calls. Immediate background
field clearing leaves an intentional copy available to paste.

The macOS pasteboard is shared with other applications. Current-host-only keeps
the copy off Universal Clipboard, but local applications and clipboard managers
can still read or retain an explicit copy. Concealed/transient markers are
advisory, and force-killing the app can prevent its timer from clearing the item.

iOS disables third-party keyboard extensions. Android marks password input as
private and disables personalized learning; the OS/user controls which keyboard
is enabled. Android also blocks screenshots/recording and excludes app data from
backup. The Apple GUIs cover their windows while inactive; macOS clears fields
and its own clipboard item before sleep, when the screen locks, and on
user-session deactivation. The macOS process also disables core files before
AppKit starts. Its password fields give Accessibility clients their labels but
not their text, hidden or revealed, and its revealed editor rejects selection
export through pasteboard, drag, Services, speech, Find, and Quick Look paths.
Secure keyboard entry stays on while a revealed password is being edited, as it
is for the hidden field.

Clearing releases the logical session and resets UI/undo state. Temporary input
byte buffers are overwritten where possible. Swift, Java, CryptoKit, UI frameworks,
keyboards, and operating systems manage other copies; this is not a guarantee
that every physical byte has been overwritten. Pasting into another app is
outside PwdHash's control.

## Compatibility and tests

The original PwdHash algorithm is the default and currently only algorithm.
It intentionally preserves HMAC-MD5, one leading `@@` removal, the historical
suffix list, letter case and ports, UTF-16 low-byte encoding, password-length
rules, character constraints, and rotation. Inputs are not silently trimmed
or normalized. Long-password quirks, including NUL output bytes, are preserved.
Changing these rules would change existing passwords.

The macOS app and the terminal tool show a caution when the site part of an
address holds something a plain site name does not, such as a space, `#`, `?`,
`@`, a port, or a non-ASCII character. A pasted link of that kind can name one
site to a browser and another to the original rules. The caution never blocks
or changes the result, and a plain name such as `example.com` gets none.

One difference from the original is known. When a `/` or `.` in the address is
directly followed by a combining mark, the Swift engine shared by the Apple
apps divides the address differently from the original JavaScript and the C
tool, and gives a different result. The macOS app shows its caution for such
an address.

The original construction is fast. If a generated password is exposed, an
attacker can test guesses of a weak original password offline. Use a long,
high-entropy original password. Legacy compatibility is intentionally separate
from any future modern password-hardening design.

The test suite requires Node.js, Python 3.11 or later, and a C toolchain with
AddressSanitizer and UndefinedBehaviorSanitizer. The Swift and AppKit tests
use the installed Xcode SDK on macOS. Android core tests use JDK 17.

```sh
make test                 # C + original JS corpus, terminal checks, sanitizers; Swift core on macOS
make test-macos           # Native AppKit screen, private test pasteboard
make test-android-core    # Actual Java engine against the original JS corpus
make test-android-device  # Connected Android phone, synthetic inputs and clipboard
```

The shared corpus has 6,111 synthetic cases covering historical suffixes,
subdomains, schemes, ports, case, `@@`, Unicode/combining marks, key/block
boundaries, long passwords, and malformed addresses. The C checks additionally
exercise hidden terminal input, Unicode backspace, timeout/cancellation with
terminal restoration, interruption at either prompt, an idle prompt's processor
use, address cautions over the whole corpus, the carriage-return and NUL
notices, a closed output pipe, malformed UTF-8, and 40,000 boundary cases under
ASan/UBSan. The macOS suite covers reveal/caret/editing, accessibility
protection of hidden and revealed fields, selection-export denial, editor
protections before the first keystroke, kill-buffer and smart-paste handling,
secure keyboard entry while a revealed password is edited, address cautions,
copy privacy markers, clipboard ownership, idle/background behavior, and sleep
and screen-lock cleanup.

The device suite uses the actual Android runtime for the entire corpus and
checks screen privacy, input reuse, hold/edit/release, Copy/Clear, foreground
clipboard expiry, real background/foreground switching, and empty saved state.
It replaces the phone's clipboard with synthetic copies.

No real credentials are used in tests. Detailed physical acceptance of keyboard
behavior, accessibility, and all device/OS variations remains manual. Builds
and tests do not publish an app or establish store acceptance.

## Licence

The original work in this repository is licensed under [Apache-2.0](LICENSE).
The original PwdHash code and other bundled components retain their upstream
terms. See [NOTICE](NOTICE) for the applicable licences and attributions.

For private security reporting, see [SECURITY.md](SECURITY.md).

## Credits

Personal hobby project by **Nenad Micic**, based on
[Stanford PwdHash](https://pwdhash.github.io/website/). Original contributors:
Blake Ross, Collin Jackson, Nicholas Miyake, Dan Boneh, and John C. Mitchell.
The original BSD notice is retained in each GUI app and in the standalone C
source/program. Unmodified upstream test sources retain their own notices.
