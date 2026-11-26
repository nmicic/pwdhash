# PwdHash for macOS

Native AppKit application for macOS 13 or later. Bundle ID: `app.nmic.pwdhash`.
It shares the original-compatible Swift hash engine and continuous idle deadline
with the iPhone app in `../IOS/PwdHash/Core/`.

From the repository root:

```sh
make macos
open .build/macos/PwdHash.app
make test-macos
make verify-macos
```

The build uses the installed Xcode/macOS SDK, the committed geometric icon,
Apple's asset compiler, and ad-hoc local signing with Hardened Runtime. There
are no third-party build or runtime dependencies. The app is universal (Apple
silicon and Intel) by default; `ARCHS=arm64` or `ARCHS=x86_64` builds one
architecture, and the older `ARCH=` spelling still works. The build adds the
toolchain keys that Xcode writes for its own projects (`DTXcode`, `DTSDKName`,
and the rest), read from the installed tools, and clears extended attributes
before signing.

`make verify-macos` rebuilds the app and checks the signature, Hardened Runtime,
that the sandbox is the only entitlement, the architectures and their minimum
system version, the App Store category and toolchain keys, the absence of
download quarantine marks, the privacy manifest, and core-file suppression. It
uses Python 3's standard library.

## Upload to App Store Connect

Sign in under Xcode **Settings → Accounts** with a developer team that has
access to the target app record. For your own distribution, use a bundle
identifier registered to your team in the Xcode project and app Info.plist.
Set `CFBundleShortVersionString` and `CFBundleVersion` in
[`App/Info.plist`](App/Info.plist) for the version you are delivering. Use a
new build number for each upload.

From the repository root, run:

```sh
PWDHASH_DEVELOPMENT_TEAM=YOUR_TEAM_ID sh scripts/upload-macos-appstore.sh --upload
```

The script prepares the icon catalog, archives a universal Release build,
uses Xcode's automatic signing, and verifies the exported installer and app.
It then delivers the archive to App Store Connect using the Xcode account.
The archive and signed `Export/PwdHash.pkg` are saved under
`.build/macos-upload/PwdHash-VERSION-BUILD.*/`.

To create and verify a signed installer locally, run the same script with
`--export`. After an upload finishes processing, select the build on the macOS
version page in App Store Connect. [Apple's upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

### Manual signing

Use this route if you already have local distribution identities and a profile.

```sh
PWDHASH_APP_IDENTITY="Apple Distribution: NAME (TEAMID)" \
PWDHASH_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: NAME (TEAMID)" \
PWDHASH_PROVISIONING_PROFILE=/path/to/PwdHash.provisionprofile \
make macos-appstore
```

Both certificates need their private keys in a keychain
(`security find-identity -v` lists them), and the profile must be a Mac App
Store profile for this bundle ID. The command rebuilds the app, checks the
profile (type, expiry, bundle ID), embeds it, signs the app with the
application certificate and a secure timestamp, checks the signed copy against
the profile, and writes `.build/macos/appstore/PwdHash-VERSION-BUILD.pkg`,
signed with the installer certificate. Signing contacts Apple's timestamp
service. Nothing is uploaded: the command ends by printing the `altool` lines
that ask App Store Connect to validate and then receive the package.

The Intel half cannot run on an Apple silicon Mac without Rosetta, so run the
app once on an Intel Mac or under Rosetta before uploading.

## Window and input handling

One resizable window contains editable inputs, momentary reveal, Generate,
Copy, Clear, background behavior, and inline credits/contact/full BSD license.
Return moves from address to password, then generates. Cmd-Shift-C copies the
generated password. The revealed field keeps its text and caret when hidden.

Under the address, the app shows the hashing domain as you type. It adds a
caution when the site part holds something a plain site name does not: a space
or control character, one of `# % : ? @ \`, a non-ASCII character, or a scheme
other than lowercase `http://` and `https://`. Such an address usually comes
from a pasted link, and the original algorithm can hash it for a different site
than the one a browser would open. The caution is also announced to VoiceOver.
It never blocks Generate or changes the result, and a plain name such as
`example.com`, in any letter case, gets none.

The password fields give Accessibility clients their labels and focus but not
their text, hidden or revealed. The field cell, which is the element AppKit
hands to those clients, carries the label and answers no value or text-range
request. The test suite checks this inside the app's own process; a read by a
separate Accessibility client has not been exercised. The revealed editor also
rejects copying, dragging, Services, speaking, Find, Quick Look/definition
lookup, and all selection-pasteboard export, and its menu actions are limited
to Paste, Select All, and Delete.

In the address and password editors, undo, autocorrection, text replacement,
inline predictions, Writing Tools, and smart-paste spacing are off from the
moment a field takes focus. The delete commands that normally fill the system
kill buffer (Ctrl-K, Cmd-Delete, and the like) delete without filling it, so
Ctrl-Y cannot bring cleared text back.

Secure keyboard entry, which AppKit turns on for the hidden password field,
stays on while a revealed password is being edited. It is released when focus
leaves the field, the window stops being the key window, or another app comes
to the front. A held reveal still shows the password on screen and can be
observed by someone or software able to capture the display.

## Storage, clearing, and the clipboard

No credentials are written to files, preferences, or the keychain. The process
sets its core-file size limit to zero before AppKit starts. The window
is not restorable. Five idle minutes clears its fields and undo state. The app
starts with clearing on deactivation enabled; it can be turned off on the same
screen for repeated logins. An opaque privacy cover appears while inactive.
Sleep, a locked screen, and session deactivation clear the fields and the app's
own copied item. The screen-lock notice is a system notification that Apple
does not document, so that path adds to the idle and sleep handling and does
not replace it.

Copy uses the current-host-only pasteboard option and concealed/transient markers.
The app clears its own copy after 60 seconds while it is running, and on quit,
sleep, or screen lock when the pasteboard still reports that the app owns the
copy. AppKit checks ownership and clears content in separate calls. Short
activity assertions keep session/clipboard deadlines from being deferred by App
Nap, while still allowing system sleep. Force-killing the app can prevent its
cleanup timer from running.

The pasteboard is shared with other applications on the Mac. The host-only
option prevents Universal Clipboard transfer to other devices; it does not stop
local applications or clipboard managers from reading or retaining an explicit
copy. Concealed/transient markers are advisory. Pasting into another application
is controlled by that application.

The original algorithm is retained for compatibility. It is fast and permits
offline testing of guesses for a weak original password when a generated
password is exposed. Use a long, high-entropy original password. This is a
legacy-compatibility client, not a modern password-hardening design.

## Tests

Tests use a private pasteboard and synthetic inputs, preserving the user's normal
clipboard. They exercise generation, input reuse, caret-safe reveal/edit/hide,
accessibility text protection for hidden and revealed fields, selection-export
denial, copy flags, expiry, background modes, sleep cleanup, editor protections
before the first keystroke, kill-buffer and smart-paste handling, secure
keyboard entry (through counters, so the real system setting is not touched),
address cautions, screen-lock cleanup, and desktop rendering.
The generated preview is ignored under `.build/macos-tests/`.

Personal hobby project by Nenad Micic, based on Stanford PwdHash.
Contact: [pwdhash@nmic.app](mailto:pwdhash@nmic.app).
