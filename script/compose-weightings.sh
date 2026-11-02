#!/bin/bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH

set -euo pipefail

compose() {
  local input="$1" output="$2"
  shift 2
  local binds=()
  for b in "$@"; do binds+=(-b "$b"); done
  nix shell .#rain-cli -c rain dotrain compose -i "$input" -e weighting "${binds[@]}" > "$output"
}


for bind in test/composed/*.bind; do
  set_name="$(basename "$bind" .bind)"
  binds=()
  while IFS= read -r b; do binds+=("$b"); done < "$bind"
  case "$set_name" in
    mint-weighting-*) rain=mint-weighting ;;
    *) rain="$set_name" ;;
  esac
  compose "src/rain/${rain}.rain" "test/composed/${set_name}.rl" "${binds[@]}"
done
