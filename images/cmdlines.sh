#!/usr/bin/env bash
# cmdlines.sh — sourced helper that loads KERNEL_CMDLINE from a profile env file.
#
# Usage (from another script):
#   source images/cmdlines.sh
#   load_profile_cmdline "$PROFILE"   # PROFILE is "nfs" or "emmc" or a path to *.env

set -euo pipefail

load_profile_cmdline() {
  local profile="$1"
  local repo_root path
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if [[ -f "$profile" ]]; then
    path="$profile"
  else
    path="$repo_root/profiles/${profile}.env"
  fi

  [[ -f "$path" ]] || { echo "ERROR: profile not found: $path" >&2; return 1; }
  # shellcheck disable=SC1090
  source "$path"
  [[ -n "${KERNEL_CMDLINE:-}" ]] || { echo "ERROR: $path did not define KERNEL_CMDLINE" >&2; return 1; }
  export KERNEL_CMDLINE
}
