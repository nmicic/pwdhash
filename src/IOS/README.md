# PwdHash for iPhone

The iPhone source lives here. Build and test commands below run from the repository root.

A single-screen, offline native iPhone app for the original
[Stanford PwdHash website](https://pwdhash.github.io/website/) algorithm.
Requires iOS 17 or later. Bundle ID: `app.nmic.pwdhash`.

Enter **Site Address** and **Site Password**, then press **Generate** and
**Copy**. Both password fields start hidden. Hold an eye button to reveal
its field; releasing, dragging away, or leaving the active app hides it.
The site password remains editable while hidden and while revealed.

Editing the address keeps the site password. Editing the site password keeps
the address. Either edit clears the previous result and disables Copy until
Generate is pressed again. There is no history or saved list of sites.
All controls, including **Clear** and the background option, are on this screen.
The view scrolls for the keyboard, smaller phones, and larger accessibility text.

**About & credits** expands on the same screen with this attribution:

> iOS app developed by Nenad Micic as a personal hobby project, based on Stanford PwdHash.

It credits the original PwdHash contributors and displays the complete original
BSD license offline. **Support & app information**, **Privacy policy**, and the
original-project link open their pages in the user's browser only when tapped.
The links do not include entered site addresses or passwords. Opening them hides
the password fields and dismisses the keyboard; the ordinary background-clearing
option still applies.

## Contact

Questions, feedback, and bug reports: [pwdhash@nmic.app](mailto:pwdhash@nmic.app).

App information and support: <https://nmic.app/pwdhash/ios>.
Privacy policy: <https://nmic.app/pwdhash/ios/privacy>.

The **Contact** button in About & credits opens the user's email app with this
recipient. The user writes and sends the message. The ordinary background-clearing
option applies when leaving PwdHash for the email app.

## Install over USB from Terminal

Connect and unlock the iPhone with Developer Mode and computer trust enabled.
Use a bundle identifier on your Apple Developer team with a matching
development certificate and provisioning profile.

```sh
BUNDLE_ID=com.example.pwdhash make install
```

This builds, signs with an existing matching development certificate and
provisioning profile, selects a registered iPhone, and installs and launches the
app. Matching wildcard development profiles are supported.
The shell needs permission to use the login keychain and Apple's device service.

If more than one phone is connected, pass its identifier explicitly:

```sh
DEVICE_ID=YOUR_DEVICE_IDENTIFIER BUNDLE_ID=com.example.pwdhash make install
```

Optional environment variables are `BUNDLE_ID` and `PROVISIONING_PROFILE`.
`SKIP_BUILD=1` installs the existing `.build/iphoneos/PwdHash.app`.
Nothing is submitted or published by these commands.

## Privacy and idle behavior

- No network requests, accounts, analytics, databases, preferences, keychain
  storage, credential files, or state restoration. The app keeps only the
  current on-screen session. The background option itself is not saved.
- After five minutes without interaction, the app clears the fields,
  generated result, domain hint, and undo state. The deadline uses a continuous
  clock that includes device sleep. Expiry is checked before accepting an
  interaction and before showing a returning session.
- **Clear when leaving app** starts **on**. It clears fields as soon as the
  app enters the background. The app switcher gets an opaque privacy cover.
  Temporarily becoming inactive hides both passwords and covers the screen.
- Turn that switch **off** if you want to reuse the inputs while switching
  between PwdHash and login screens. If five idle minutes have elapsed, it
  clears before showing the session again. iOS can suspend apps and prevent
  a timer from running in the background, so this mode cannot promise erasure
  at exactly five minutes while suspended. The on-screen explanation says so.
  The default immediate-background clearing avoids retaining that session.
- Copy uses the iPhone's clipboard with `localOnly` enabled, excluding
  Universal Clipboard. iOS removes the copied item after **60 seconds**, even
  while PwdHash is suspended. Background field clearing leaves that deliberate
  copy available for pasting. **Clear** and foreground idle expiry also clear
  a clipboard item the app still owns; another app's newer copy is preserved.
- Both fields disable autocorrection, spell checking, smart substitutions,
  AutoFill hints, and built-in Copy/Cut menus. Third-party keyboard extensions
  are disabled. Only the result's Copy button writes to the clipboard.

Clearing releases the app's session values and resets its UI and undo state.
Temporary input byte buffers are overwritten where possible. Swift, CryptoKit,
UIKit, and the operating system manage other string/buffer copies; this is not
a guarantee that every physical byte has been securely overwritten. Pasting
into another app is outside PwdHash's control.

Apple documents [background suspension](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time)
and [pasteboard expiration and device-only copies](https://developer.apple.com/documentation/uikit/uipasteboard/setitems(_:options:)).

## Compatibility

The default and currently only algorithm is the original website's PwdHash.
The native implementation is isolated in `src/IOS/PwdHash/Core/LegacyPwdHash.swift`
so additional algorithms can be added later without changing existing results.

It intentionally preserves HMAC-MD5, one leading `@@` removal, the original
domain suffix list, letter case and port handling, UTF-16 low-byte encoding,
password-length rules, and final character constraints. Updating these rules
would change existing passwords. Inputs are not silently trimmed or normalized.
The website's unusual output for very long passwords is also preserved;
the app displays a note if that output includes invisible NUL characters.

The original JavaScript reference files are used by the test suite.
The original BSD license is in the app's `ThirdPartyNotices.txt`.

## Build and check

The terminal build uses Xcode's installed Swift compiler and iOS SDK, without
the Xcode UI or any downloaded packages. Development tools need Python 3,
Pillow for the locally drawn app icon, and Node for compatibility tests.

```sh
make test
make build
make simulator
```

`make test` compares the native implementation with 6,111 synthetic cases
executed by the unmodified website JavaScript. These cover historical suffixes,
subdomains, schemes, ports, case, `@@`, Unicode/combining marks, MD5 block/key
boundaries, long-password behavior, and malformed input. It also tests idle
expiry at 299/300 seconds, extension by interaction, long sleep, and reset.
No real credentials are used or logged.
It also runs nine device-selection regression checks, including paired USB
phones whose developer tunnel has not opened yet, current and older CoreDevice
JSON formats, ambiguous devices, and unregistered phones.

For Xcode development, open `src/IOS/PwdHash.xcodeproj` and set your development
team and bundle identifier in Signing & Capabilities. The app has no external
runtime dependencies.

After installing, use synthetic credentials first and check:

1. The same site/password produces the website's result.
2. Hold and release each eye; edit at the start/middle/end both hidden and
   while holding the eye. The next keystroke should preserve existing text.
3. Edit each input in turn; the other input survives and Copy waits for Generate.
4. Copy, switch to another app, and paste within a minute. Confirm expiry.
5. Confirm background clearing with the switch on, and retained inputs with it off.
6. Leave it untouched for five minutes, including across a background interval
   with the switch off; the next active screen must be empty.
7. Check the app switcher, dark mode, keyboard layout, larger text, and relaunch.
