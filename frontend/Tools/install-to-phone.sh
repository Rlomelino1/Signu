#!/usr/bin/env bash
#
# Build Signu and install it on a physically connected iPhone, signed with a
# free Apple ID (Personal Team).
#
# WHY THIS EXISTS: a free provisioning profile is valid for SEVEN DAYS. After
# that the app refuses to launch ("Unable to Verify App") until it is rebuilt
# and reinstalled. Paying for the Developer Program would make it a year. This
# script is the weekly re-sign, so the choice not to pay costs one command.
#
# RELEASE, NOT DEBUG, AND THAT IS NOT A PREFERENCE. SignuApp.sessionProvider()
# and SignuDataProviderFactory.make() both return the Mock providers under
# `#if DEBUG` unless --live-auth / --live-data are passed as launch arguments,
# and an app you tap on the home screen gets no launch arguments. A Debug build
# on the phone would show "Alex Rivera" and fixture data with no way to reach
# the real account.
#
# Reinstalling over the top KEEPS the app's data container and its Keychain
# item, so the Supabase session survives and there is no need to sign in again.
#
# Usage:   frontend/Tools/install-to-phone.sh
#          TEAM_ID=ABCDE12345 frontend/Tools/install-to-phone.sh   # override
#          SKIP_LAUNCH=1 frontend/Tools/install-to-phone.sh        # install only

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project="$repo_root/frontend/Signu.xcodeproj"
derived="$repo_root/frontend/.build-device"
bundle_id="pro.signu"

die() { printf '\n\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- preflight

step "Checking the things that are not this script's to fix"

[ -d "$project" ] || die "no Xcode project at $project"

# Config.plist is gitignored and holds the Supabase URL + publishable key. A
# build without it compiles fine and then cannot reach production at all.
config="$repo_root/frontend/Signu/Config.plist"
[ -f "$config" ] || die "frontend/Signu/Config.plist is missing — the app would build and then fail to reach Supabase. It is gitignored on purpose; restore it before building."
for key in SupabaseURL SupabaseAnonKey; do
  /usr/libexec/PlistBuddy -c "Print :$key" "$config" >/dev/null 2>&1 \
    || die "Config.plist has no '$key'"
done

team="${TEAM_ID:-}"

# The Team ID is the OU of the Apple Development certificate. Read it from the
# certificate rather than from `security find-identity`: newer Xcode can hold
# the private key somewhere the `security` CLI does not enumerate, so
# find-identity reports "0 valid identities" for a signing setup that
# xcodebuild uses without complaint. The certificate is the reliable witness;
# whether it can actually sign is settled by the build, not by this check.
if [ -z "$team" ]; then
  team="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)"
fi
[ -n "$team" ] || die "no 'Apple Development' certificate found.
  Adding the Apple ID to Xcode is NOT enough — it does not mint a certificate
  on its own. In Xcode -> Settings -> Apple Accounts, select the Personal Team,
  click 'Manage Certificates...', then '+' -> 'Apple Development'.
  Then re-run. (Or pass TEAM_ID=... if you already know the team.)"
echo "signing team: $team"
security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development" \
  || echo "note: the security CLI lists no codesigning identity, which is often a
      false negative on recent Xcode. Proceeding — if signing genuinely cannot
      find a private key, the build below fails with 'no signing certificate'."

# --------------------------------------------------------------- the device

step "Finding the phone"

devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 \
  || die "xcrun devicectl failed — is Xcode (not just the command line tools) installed?"

read -r udid name os < <(python3 - "$devices_json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
best = None
for dev in d.get("result", {}).get("devices", []):
    props = dev.get("deviceProperties", {})
    hw = dev.get("hardwareProperties", {})
    conn = dev.get("connectionProperties", {})
    if hw.get("platform") != "iOS":
        continue
    # "connected" is the paired-and-present state; "available" alone can be a
    # device Xcode merely remembers.
    if conn.get("tunnelState") == "unavailable" and conn.get("pairingState") != "paired":
        continue
    best = (dev.get("identifier", ""),
            (props.get("name") or "iPhone").replace(" ", "_"),
            props.get("osVersionNumber") or "?")
    break
print(*(best or ("", "", "")))
PY
) || true

[ -n "${udid:-}" ] || die "no connected iPhone found. Check, in order:
  1. cable is in, phone unlocked, 'Trust This Computer' accepted
  2. Developer Mode is ON: Settings -> Privacy & Security -> Developer Mode
     (iOS 16+; the phone reboots when you enable it)
  3. the phone appears in Xcode -> Window -> Devices and Simulators"

echo "device: ${name//_/ } (iOS $os)"
echo "udid:   $udid"

# ------------------------------------------------------------------- build

step "Building Release (Debug would show mock data — see the header)"

xcodebuild build \
  -project "$project" \
  -scheme Signu \
  -configuration Release \
  -destination "platform=iOS,id=$udid" \
  -derivedDataPath "$derived" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_STYLE=Automatic \
  | tail -25

app="$derived/Build/Products/Release-iphoneos/Signu.app"
[ -d "$app" ] || die "build reported success but $app is missing"

# A build that is not really signed installs and then refuses to launch.
# -dvv, not -dv: the Authority lines only appear at the second verbosity level.
sig="$(codesign -dvv "$app" 2>&1 || true)"
grep -qiE 'Signature=adhoc|not signed' <<<"$sig" \
  && die "the .app came out ad-hoc/unsigned — device install needs a real Apple Development signature"
echo "signed:  $(sed -n 's/^Authority=//p' <<<"$sig" | head -1)"
echo "team:    $(sed -n 's/^TeamIdentifier=//p' <<<"$sig" | head -1)"

# ----------------------------------------------------------------- install

step "Installing"

xcrun devicectl device install app --device "$udid" "$app" 2>&1 | tail -8

if [ "${SKIP_LAUNCH:-}" != "1" ]; then
  step "Launching"
  xcrun devicectl device process launch --device "$udid" "$bundle_id" 2>&1 | tail -4 \
    || echo "launch failed — if this is the first install, trust the certificate on the phone:
  Settings -> General -> VPN & Device Management -> Developer App -> Trust"
fi

# ------------------------------------------------------------------ expiry

step "Done"

# Read the real expiry out of the profile that was just embedded, rather than
# adding 7 days to today. It is an exact instant -- 7x24h from when the profile
# was issued, not a date boundary and not a fixed weekday -- so it slides to
# whenever this script was last run.
expires="unknown (could not read the embedded profile)"
if security cms -D -i "$app/embedded.mobileprovision" >/tmp/signu-profile.plist 2>/dev/null; then
  raw="$(plutil -extract ExpirationDate raw -o - /tmp/signu-profile.plist 2>/dev/null || true)"
  # Parse as UTC (-u) into epoch, THEN render in local time. Without -u, BSD
  # date reads the Z-suffixed string as though it were already local and the
  # printed deadline is off by the UTC offset -- three hours, here.
  if [ -n "$raw" ]; then
    epoch="$(date -jf '%Y-%m-%dT%H:%M:%SZ' -u "$raw" '+%s' 2>/dev/null || true)"
    if [ -n "$epoch" ]; then
      expires="$(date -r "$epoch" '+%a %d %b at %H:%M %Z')"
    else
      expires="$raw (UTC)"
    fi
  fi
  rm -f /tmp/signu-profile.plist
fi

cat <<EOF
Installed $bundle_id on ${name//_/ }.

This signature expires $expires — an exact instant 7x24h after the build, not
midnight and not a fixed weekday. iOS checks it when the app LAUNCHES, so an
already-running app keeps working and the next cold start is what fails, with
"Unable to Verify App". That is the free-account limit, not a bug and not data
loss. Re-run this script to reset the clock:

    frontend/Tools/install-to-phone.sh

Your session and local data survive a reinstall, so there is no re-login.
EOF
