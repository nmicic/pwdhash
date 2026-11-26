#!/usr/bin/env python3
"""Checks that a provisioning profile suits a Mac App Store upload of one bundle identifier.

Usage: security cms -D -i PROFILE | python3 scripts/check-macos-profile.py BUNDLE_ID

Prints `application-identifier=` and `team-identifier=` lines for the calling script. For a
profile that does not fit, prints each reason to standard error and exits with status 1. The
printed values match fixed patterns, because the caller writes them into an entitlements file.
"""
import datetime
import plistlib
import re
import sys

PREFIX = r"[A-Z0-9]{10}"


def main() -> int:
    if len(sys.argv) != 2 or not re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", sys.argv[1]):
        print("usage: check-macos-profile.py BUNDLE_ID < decoded-profile", file=sys.stderr)
        return 2
    bundle_id = sys.argv[1]
    try:
        profile = plistlib.loads(sys.stdin.buffer.read())
        entitlements = profile["Entitlements"]
        if not isinstance(entitlements, dict):
            raise TypeError
    except Exception:
        print("  the file is not a readable provisioning profile", file=sys.stderr)
        return 1

    problems = []
    if "ProvisionedDevices" in profile:
        problems.append("it lists devices, so it is a development or ad hoc profile, not a Mac App Store one")
    if profile.get("ProvisionsAllDevices"):
        problems.append("it is a Developer ID profile, not a Mac App Store one")
    if entitlements.get("com.apple.security.get-task-allow") or entitlements.get("get-task-allow"):
        problems.append("it allows debugging (get-task-allow), which the App Store rejects")
    platforms = profile.get("Platform")
    if isinstance(platforms, list) and platforms and not {"OSX", "macOS"} & {str(item) for item in platforms}:
        problems.append("it is not a macOS profile")
    expires = profile.get("ExpirationDate")
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    if not isinstance(expires, datetime.datetime):
        problems.append("it has no expiration date")
    elif expires <= now:
        problems.append("it expired on " + expires.strftime("%Y-%m-%d"))
    team = entitlements.get("com.apple.developer.team-identifier")
    if not isinstance(team, str) or not re.fullmatch(PREFIX, team):
        problems.append("it has no usable team identifier")
    application = entitlements.get("com.apple.application-identifier")
    if not isinstance(application, str) or not re.fullmatch(PREFIX + r"\." + re.escape(bundle_id), application):
        readable = isinstance(application, str) and re.fullmatch(r"[A-Za-z0-9.*-]{1,200}", application)
        shown = application if readable else "missing or unreadable"
        problems.append(f"its application identifier is {shown}, not PREFIX.{bundle_id}")

    if problems:
        for problem in problems:
            print("  " + problem, file=sys.stderr)
        return 1
    print("application-identifier=" + application)
    print("team-identifier=" + team)
    return 0


if __name__ == "__main__":
    sys.exit(main())
