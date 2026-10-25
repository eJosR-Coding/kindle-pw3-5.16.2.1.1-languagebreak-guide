#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Error: %s\n' "$*" >&2
  return 1
}

usage() {
  cat <<'EOF'
Usage:
  kindle.sh check  --device DEVICE --mountpoint PATH
  kindle.sh copy   --device DEVICE --mountpoint PATH --source DIRECTORY
  kindle.sh verify --device DEVICE --mountpoint PATH --source DIRECTORY
  kindle.sh eject  --device DEVICE --mountpoint PATH

DEVICE must be the exact block-device path mounted at PATH. Nothing is
auto-detected, mounted, overwritten, or deleted. Copy accepts regular files
and directories only; symbolic links are rejected.
EOF
}

is_block_device() {
  [[ -b "$1" ]]
}

validate_target() {
  local device="$1" mount_path="$2" requested_source
  local -a mounted_sources=()

  [[ -n "$device" && -n "$mount_path" ]] || fail 'Both --device and --mountpoint are required.' || return
  is_block_device "$device" || fail "Not a block device: $device" || return
  [[ -d "$mount_path" && ! -L "$mount_path" ]] || fail "Mount point is not a real directory: $mount_path" || return
  mountpoint --quiet -- "$mount_path" || fail "Path is not a mount point: $mount_path" || return
  command -v findmnt >/dev/null || fail 'Required command not found: findmnt' || return

  mapfile -t mounted_sources < <(findmnt --noheadings --raw --output SOURCE --mountpoint "$mount_path")
  [[ "${#mounted_sources[@]}" -eq 1 ]] || fail "Expected one mounted source at $mount_path; found ${#mounted_sources[@]}." || return

  requested_source="$(readlink -f -- "$device")" || fail "Cannot resolve block device: $device" || return
  [[ -n "$requested_source" && "$requested_source" == "$(readlink -f -- "${mounted_sources[0]}")" ]] || fail "Mounted source does not match the explicitly selected device: $device" || return

  VALIDATED_DEVICE="$requested_source"
  VALIDATED_MOUNTPOINT="$(readlink -f -- "$mount_path")"
}

validate_payload_dir() {
  local source="$1" entry
  [[ -d "$source" && ! -L "$source" ]] || fail "Source is not a real directory: $source" || return
  entry="$(find "$source" -type l -print -quit)" || fail "Cannot inspect source directory: $source" || return
  if [[ -n "$entry" ]]; then
    fail "Symbolic links are not supported in source payloads: $entry"
    return
  fi
  entry="$(find "$source" ! -type d ! -type f -print -quit)" || fail "Cannot inspect source directory: $source" || return
  if [[ -n "$entry" ]]; then
    fail "Only regular files and directories are supported: $entry"
    return
  fi
}

validate_separate_trees() {
  local source_real="$1" target_real="$2"
  [[ "$source_real" != "$target_real" && "$source_real" != "$target_real/"* && "$target_real" != "$source_real/"* ]] || fail 'Source and destination trees must not contain one another.'
}

destination_path_has_symlink() {
  local root="$1" relative="$2" current="$1" part
  local -a parts=()
  IFS='/' read -r -a parts <<< "$relative"
  for part in "${parts[@]}"; do
    current="$current/$part"
    [[ ! -L "$current" ]] || return 0
  done
  return 1
}

load_payload_files() {
  local source="$1" list_file
  PAYLOAD_FILES=()
  list_file="$(mktemp)" || fail 'Cannot create a temporary file list.' || return
  if ! find "$source" -type f -print0 > "$list_file"; then
    rm -f -- "$list_file"
    fail "Cannot enumerate source files: $source"
    return
  fi
  mapfile -d '' -t PAYLOAD_FILES < "$list_file" || { rm -f -- "$list_file"; fail 'Cannot read the source file list.'; return; }
  rm -f -- "$list_file" || fail 'Cannot remove the temporary file list.' || return
  [[ "${#PAYLOAD_FILES[@]}" -gt 0 ]] || fail "No regular files found in source directory: $source" || return
}

valid_relative_path() {
  local relative="$1"
  [[ "$relative" != *$'\n'* ]] || fail 'Source paths containing line breaks are not supported.'
}

copy_payload() {
  local source="$1" target="$2" source_real target_real file relative destination parent temp
  local -a PAYLOAD_FILES=()

  validate_payload_dir "$source" || return
  [[ -d "$target" && ! -L "$target" ]] || fail "Destination is not a real directory: $target" || return
  source_real="$(readlink -f -- "$source")" || return
  target_real="$(readlink -f -- "$target")" || return
  validate_separate_trees "$source_real" "$target_real" || return
  load_payload_files "$source_real" || return

  for file in "${PAYLOAD_FILES[@]}"; do
    relative="${file#"$source_real"/}"
    valid_relative_path "$relative" || return
    destination="$target/$relative"
    if destination_path_has_symlink "$target" "$relative"; then
      fail "Destination path contains a symbolic link: $relative"
      return 1
    fi
    [[ ! -e "$destination" && ! -L "$destination" ]] || fail "Refusing to overwrite existing path: $relative" || return
  done

  for file in "${PAYLOAD_FILES[@]}"; do
    relative="${file#"$source_real"/}"
    destination="$target/$relative"
    parent="$(dirname -- "$destination")"
    mkdir -p -- "$parent" || fail "Cannot create destination directory: $parent" || return
    if destination_path_has_symlink "$target" "$relative"; then
      fail "Destination path contains a symbolic link: $relative"
      return 1
    fi
    temp="$(mktemp --tmpdir="$parent" '.kindle-transfer.XXXXXX')" || fail "Cannot create temporary file in: $parent" || return
    if ! cp -- "$file" "$temp" || ! cmp -s -- "$file" "$temp"; then
      rm -f -- "$temp"
      fail "Copy verification failed for: $relative"
      return
    fi
    if ! mv --no-clobber -- "$temp" "$destination" || [[ -e "$temp" ]]; then
      rm -f -- "$temp"
      fail "Destination appeared during transfer; refusing to overwrite: $relative"
      return
    fi
  done

  sync || fail 'Could not flush copied files.' || return
  verify_payload "$source" "$target" || return
  printf 'Copied and verified %s file(s).\n' "${#PAYLOAD_FILES[@]}"
}

verify_payload() {
  local source="$1" target="$2" source_real target_real file relative destination
  local -a PAYLOAD_FILES=()

  validate_payload_dir "$source" || return
  [[ -d "$target" && ! -L "$target" ]] || fail "Destination is not a real directory: $target" || return
  source_real="$(readlink -f -- "$source")" || return
  target_real="$(readlink -f -- "$target")" || return
  validate_separate_trees "$source_real" "$target_real" || return
  load_payload_files "$source_real" || return

  for file in "${PAYLOAD_FILES[@]}"; do
    relative="${file#"$source_real"/}"
    valid_relative_path "$relative" || return
    destination="$target/$relative"
    if destination_path_has_symlink "$target" "$relative"; then
      fail "Destination path contains a symbolic link: $relative"
      return 1
    fi
    [[ -f "$destination" && ! -L "$destination" ]] || fail "Destination file is missing or not regular: $relative" || return
    cmp -s -- "$file" "$destination" || fail "File content differs: $relative" || return
  done
  printf 'Verified %s file(s); this checks copied bytes only.\n' "${#PAYLOAD_FILES[@]}"
}

eject_device() {
  local device="$1" mount_path="$2"
  validate_target "$device" "$mount_path" || return
  command -v udisksctl >/dev/null || fail 'Required command not found: udisksctl' || return
  sync || fail 'Could not flush pending writes.' || return
  udisksctl unmount --block-device "$VALIDATED_DEVICE" || fail 'Unmount failed; do not disconnect the cable.' || return
  if ! udisksctl power-off --block-device "$VALIDATED_DEVICE"; then
    fail 'The volume was unmounted but the device did not power off. Use the desktop safe-removal control and wait before disconnecting.'
    return
  fi
  printf 'Unmounted and requested safe removal of %s.\n' "$VALIDATED_DEVICE"
}

parse_options() {
  DEVICE=''
  MOUNTPOINT=''
  SOURCE=''
  while (($#)); do
    case "$1" in
      --device|--mountpoint|--source)
        (($# >= 2)) || fail "Missing value for $1" || return
        case "$1" in
          --device) [[ -z "$DEVICE" ]] || fail 'Duplicate --device option.' || return; DEVICE="$2" ;;
          --mountpoint) [[ -z "$MOUNTPOINT" ]] || fail 'Duplicate --mountpoint option.' || return; MOUNTPOINT="$2" ;;
          --source) [[ -z "$SOURCE" ]] || fail 'Duplicate --source option.' || return; SOURCE="$2" ;;
        esac
        shift 2
        ;;
      *) fail "Unknown option: $1"; return ;;
    esac
  done
}

require_options() {
  local action="$1"
  [[ -n "$DEVICE" && -n "$MOUNTPOINT" ]] || fail 'Provide both --device and --mountpoint.' || return
  if [[ "$action" == copy || "$action" == verify ]]; then
    [[ -n "$SOURCE" ]] || fail 'Provide --source for copy and verify.' || return
  else
    [[ -z "$SOURCE" ]] || fail "--source is not used by $action." || return
  fi
}

main() {
  local action="${1:-}"
  [[ -n "$action" ]] || { usage; return 2; }
  shift
  case "$action" in check|copy|verify|eject) ;; *) usage; return 2 ;; esac
  parse_options "$@" || return 2
  require_options "$action" || return 2
  if [[ "$action" == eject ]]; then
    eject_device "$DEVICE" "$MOUNTPOINT"
    return
  fi
  validate_target "$DEVICE" "$MOUNTPOINT" || return

  case "$action" in
    check)
      printf 'Explicit device matches mounted filesystem: %s at %s.\n' "$VALIDATED_DEVICE" "$VALIDATED_MOUNTPOINT"
      ;;
    copy)
      copy_payload "$SOURCE" "$VALIDATED_MOUNTPOINT"
      ;;
    verify)
      verify_payload "$SOURCE" "$VALIDATED_MOUNTPOINT"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
