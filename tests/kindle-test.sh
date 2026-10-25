#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/kindle.sh"

TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
FAKE_DEVICE="$TMP/device"
MOCK_MOUNT="$TMP/mount"
MOCK_SOURCE="$FAKE_DEVICE"
MOCK_FINDMNT_COUNT=1
MOCK_EJECT_LOG="$TMP/eject.log"
mkdir -p "$MOCK_MOUNT"
: > "$FAKE_DEVICE"

is_block_device() { [[ "$1" == "$FAKE_DEVICE" ]]; }
mountpoint() { [[ "${*: -1}" == "$MOCK_MOUNT" ]]; }
findmnt() {
  local index
  for ((index = 0; index < MOCK_FINDMNT_COUNT; index++)); do
    printf '%s\n' "$MOCK_SOURCE"
  done
}
sync() { :; }
udisksctl() { printf '%s\n' "$*" >> "$MOCK_EJECT_LOG"; }

assert_ok() {
  local label="$1"; shift
  if "$@"; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s\n' "$label" >&2; exit 1; fi
}

assert_fails() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'FAIL %s (unexpected success)\n' "$label" >&2; exit 1; else printf 'PASS %s\n' "$label"; fi
}

assert_equal() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then printf 'PASS %s\n' "$label"; else printf 'FAIL %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2; exit 1; fi
}

assert_fails 'requires explicit device arguments at the command line' main check
assert_fails 'rejects unknown command-line options' main check --automatic-device
assert_ok 'checks the exact explicitly selected mount from the CLI' main check --device "$FAKE_DEVICE" --mountpoint "$MOCK_MOUNT"

assert_ok 'accepts only the explicitly mounted device' validate_target "$FAKE_DEVICE" "$MOCK_MOUNT"

MOCK_SOURCE="$TMP/other-device"
: > "$MOCK_SOURCE"
assert_fails 'rejects a different mounted device' validate_target "$FAKE_DEVICE" "$MOCK_MOUNT"
MOCK_SOURCE="$FAKE_DEVICE"
MOCK_FINDMNT_COUNT=2
assert_fails 'rejects ambiguous mount-source output' validate_target "$FAKE_DEVICE" "$MOCK_MOUNT"
MOCK_FINDMNT_COUNT=1

SOURCE="$TMP/source"
DEST="$TMP/destination"
mkdir -p "$SOURCE/.demo" "$DEST"
printf 'payload\n' > "$SOURCE/.demo/boot.flag"
printf 'visible payload\n' > "$SOURCE/file.bin"
assert_ok 'copies hidden and regular files with verification' copy_payload "$SOURCE" "$DEST"
assert_equal 'copies the hidden file exactly' "$(cat "$SOURCE/.demo/boot.flag")" "$(cat "$DEST/.demo/boot.flag")"
assert_ok 'verifies copied bytes' verify_payload "$SOURCE" "$DEST"

CONFLICT_SOURCE="$TMP/conflict-source"
CONFLICT_DEST="$TMP/conflict-destination"
mkdir -p "$CONFLICT_SOURCE" "$CONFLICT_DEST"
printf 'new\n' > "$CONFLICT_SOURCE/new.txt"
printf 'replacement\n' > "$CONFLICT_SOURCE/existing.txt"
printf 'keep me\n' > "$CONFLICT_DEST/existing.txt"
assert_fails 'refuses a payload with an existing destination' copy_payload "$CONFLICT_SOURCE" "$CONFLICT_DEST"
[[ ! -e "$CONFLICT_DEST/new.txt" ]] || { printf 'FAIL conflict preflight copied another file\n' >&2; exit 1; }
assert_equal 'preserves the pre-existing destination' 'keep me' "$(cat "$CONFLICT_DEST/existing.txt")"

LINK_SOURCE="$TMP/link-source"
LINK_DEST="$TMP/link-destination"
mkdir -p "$LINK_SOURCE" "$LINK_DEST"
ln -s "$SOURCE/file.bin" "$LINK_SOURCE/payload-link"
assert_fails 'rejects symbolic links in source payloads' copy_payload "$LINK_SOURCE" "$LINK_DEST"

SYMLINK_SOURCE="$TMP/symlink-destination-source"
SYMLINK_DEST="$TMP/symlink-destination"
mkdir -p "$SYMLINK_SOURCE/child" "$SYMLINK_DEST"
printf 'outside\n' > "$TMP/outside.txt"
printf 'payload\n' > "$SYMLINK_SOURCE/child/file.txt"
ln -s "$TMP" "$SYMLINK_DEST/child"
assert_fails 'rejects symlinked destination directories' copy_payload "$SYMLINK_SOURCE" "$SYMLINK_DEST"
assert_fails 'refuses to verify through symlinked destination directories' verify_payload "$SYMLINK_SOURCE" "$SYMLINK_DEST"
[[ ! -e "$TMP/child/file.txt" ]] || { printf 'FAIL followed a destination symlink\n' >&2; exit 1; }

NEWLINE_SOURCE="$TMP/newline-source"
NEWLINE_DEST="$TMP/newline-destination"
mkdir -p "$NEWLINE_SOURCE" "$NEWLINE_DEST"
printf 'payload\n' > "$NEWLINE_SOURCE/"$'bad\nname'
assert_fails 'rejects paths that break destination path validation' copy_payload "$NEWLINE_SOURCE" "$NEWLINE_DEST"

NESTED_ROOT="$TMP/nested-root"
mkdir -p "$NESTED_ROOT/source" "$NESTED_ROOT/destination"
printf 'payload\n' > "$NESTED_ROOT/source/file.txt"
assert_fails 'rejects overlapping source and destination trees' copy_payload "$NESTED_ROOT/source" "$NESTED_ROOT"

printf 'tampered\n' > "$DEST/file.bin"
assert_fails 'detects changed destination bytes' verify_payload "$SOURCE" "$DEST"

: > "$MOCK_EJECT_LOG"
assert_ok 'ejects only the validated device' eject_device "$FAKE_DEVICE" "$MOCK_MOUNT"
printf -v EXPECTED_EJECT 'unmount --block-device %s\npower-off --block-device %s' "$FAKE_DEVICE" "$FAKE_DEVICE"
assert_equal 'uses the explicit volume for unmount and power-off' "$EXPECTED_EJECT" "$(cat "$MOCK_EJECT_LOG")"

MOCK_SOURCE="$TMP/other-device"
: > "$MOCK_EJECT_LOG"
assert_fails 'does not eject when the mount source is mismatched' eject_device "$FAKE_DEVICE" "$MOCK_MOUNT"
assert_equal 'leaves devices untouched after target mismatch' '' "$(cat "$MOCK_EJECT_LOG")"

printf 'All offline Kindle helper tests passed. No block devices or mounts were used.\n'
