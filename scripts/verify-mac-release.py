#!/usr/bin/env python3
"""Fail closed unless a Mac release is provisioned, notarized, and universal."""

import datetime
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

TEAM_ID = "8ZA2YW2U9D"
BUNDLE_ID = "com.stickeynote.app.preview"
APP_ID = f"{TEAM_ID}.{BUNDLE_ID}"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(*command):
    result = subprocess.run(command, capture_output=True, env={**os.environ, "LC_ALL": "C"})
    if result.returncode:
        raise ValueError(f"{' '.join(map(str, command))}\n{result.stderr.decode(errors='replace').strip()}")
    return result


def allows(pattern, value):
    return isinstance(pattern, str) and (
        pattern == value or (pattern.endswith("*") and "*" not in pattern[:-1] and value.startswith(pattern[:-1]))
    )


def validate_profile(profile):
    require(profile.get("ProvisionsAllDevices") is True, "A Developer ID profile for all Macs is required.")
    require("ProvisionedDevices" not in profile, "A device-limited development profile cannot be released.")
    require(profile.get("TeamIdentifier") == [TEAM_ID], "Provisioning profile belongs to a different team.")
    require("OSX" in profile.get("Platform", []), "Provisioning profile must support macOS.")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime.datetime), "Provisioning profile has no expiration date.")
    require(expiry.replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc),
            "Provisioning profile has expired.")
    entitlements = profile.get("Entitlements", {})
    require(allows(entitlements.get("com.apple.application-identifier"), APP_ID),
            "Provisioning profile does not authorize this application identifier.")
    require(any(allows(group, APP_ID) for group in entitlements.get("keychain-access-groups", [])),
            "Provisioning profile does not authorize the notes Keychain group.")
    require(not entitlements.get("get-task-allow") and not entitlements.get("com.apple.security.get-task-allow"),
            "Provisioning profile permits debugging.")


def validate_entitlements(entitlements):
    require(entitlements.get("com.apple.application-identifier") == APP_ID,
            "Signed application identifier must preserve the notes Keychain identity.")
    require(entitlements.get("com.apple.developer.team-identifier") == TEAM_ID,
            "Signed team entitlement is incorrect.")
    require(entitlements.get("keychain-access-groups") == [APP_ID], "Signed notes Keychain group is incorrect.")
    require(not entitlements.get("get-task-allow") and not entitlements.get("com.apple.security.get-task-allow"),
            "A release must not permit debugger attachment.")


def verify(app, version):
    require(app.is_dir(), f"Missing exported app: {app}")
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == BUNDLE_ID, "Unexpected bundle identifier.")
    require(info.get("CFBundleShortVersionString") == version, "Release version does not match.")
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and Path(executable).name == executable, "Invalid executable name.")
    binary = app / "Contents/MacOS" / executable
    architectures = set(run("lipo", "-archs", binary).stdout.decode().split())
    require(architectures == {"arm64", "x86_64"}, "Release must include both Apple silicon and Intel architectures.")
    run("codesign", "--verify", "--deep", "--strict", "--all-architectures", app)

    profile_path = app / "Contents/embedded.provisionprofile"
    require(profile_path.is_file(), "Missing Developer ID provisioning profile for Keychain access.")
    profile = plistlib.loads(run("security", "cms", "-D", "-i", profile_path).stdout)
    validate_profile(profile)
    for architecture in sorted(architectures):
        details = run("codesign", "--display", "--verbose=4", "--architecture", architecture, app).stderr.decode()
        require(re.search(r"^Authority=Developer ID Application:", details, re.MULTILINE),
                f"{architecture}: expected a Developer ID Application signature.")
        require(f"TeamIdentifier={TEAM_ID}\n" in details, f"{architecture}: unexpected signing team.")
        flags = re.search(r"flags=0x([0-9a-fA-F]+)", details)
        require(flags and int(flags.group(1), 16) & 0x10000, f"{architecture}: hardened runtime is missing.")
        require(re.search(r"^Timestamp=.+", details, re.MULTILINE), f"{architecture}: secure signing timestamp is missing.")
        entitlements = plistlib.loads(run("codesign", "--display", "--entitlements", "-", "--xml",
                                         "--architecture", architecture, app).stdout)
        validate_entitlements(entitlements)
        with tempfile.TemporaryDirectory(prefix="stickey-release-cert-") as directory:
            prefix = str(Path(directory) / "certificate-")
            run("codesign", "--display", "--architecture", architecture, "--extract-certificates", prefix, app)
            certificate = Path(prefix + "0").read_bytes()
            require(certificate in profile.get("DeveloperCertificates", []),
                    f"{architecture}: provisioning profile does not authorize the signing certificate.")

    run("xcrun", "stapler", "validate", app)
    run("spctl", "--assess", "--type", "execute", "--verbose=4", app)
    print(f"Verified notarized Developer ID release {version}: arm64 + x86_64, matching Keychain provisioning.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"Usage: {sys.argv[0]} APP VERSION")
    try:
        verify(Path(sys.argv[1]).resolve(), sys.argv[2])
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        sys.exit(f"Release verification failed: {error}")
