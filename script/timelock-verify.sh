#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
set -euo pipefail

CONTRACT=dependencies/@openzeppelin-contracts-5.7.0/governance/TimelockController.sol:TimelockController
SNAPSHOT=dependencies/rain-deploy-0.1.27/src/generated/0_1_18/TimelockController.sol
# rain-deploy's timelock build settings; without `--compilation-profile` forge uses the cached build's instead.
COMPILE_ARGS=(--compilation-profile default --compiler-version 0.8.25 --num-of-optimizations 2000 --evm-version cancun)

case "${1:-}" in
  check)
    while read -r var; do
      export "${var}=${!var:-}"
    done < <(grep -oE '[A-Z_]+_(RPC_URL|API_KEY)' foundry.toml | sort -u)
    forge build "${CONTRACT%:*}" >/dev/null
    solc-select install 0.8.25 >/dev/null
    output=$(forge verify-contract --show-standard-json-input "${COMPILE_ARGS[@]}" --chain base \
      0x0000000000000000000000000000000000000001 "${CONTRACT}" |
      jq '.settings.outputSelection = {"*": {"*": ["evm.bytecode.object", "evm.deployedBytecode.object"]}}' |
      SOLC_VERSION=0.8.25 solc --standard-json --allow-paths "${PWD}")
    built() {
      jq -r --arg f "${CONTRACT%:*}" --arg c "${CONTRACT#*:}" ".contracts[\$f][\$c].evm.$1.object" <<<"${output}"
    }
    pinned() {
      grep -A1 "^bytes constant $1 =" "${SNAPSHOT}" | tail -1 | sed -E 's/^ *hex"([0-9a-f]*)";$/\1/'
    }
    status=0
    for pair in bytecode:CREATION_CODE deployedBytecode:RUNTIME_CODE; do
      got=$(built "${pair%:*}")
      want=$(pinned "${pair#*:}")
      if [[ ! "${want}" =~ ^[0-9a-f]+$ || "${got}" != "${want}" ]]; then
        echo "${pair#*:}: verification build (${#got} hex chars) differs from ${SNAPSHOT} (${#want} hex chars)" >&2
        status=1
      else
        echo "${pair#*:}: verification build matches ${SNAPSHOT} ($((${#got} / 2)) bytes)"
      fi
    done
    if [[ "${status}" != 0 ]]; then
      jq -c '.errors // empty' <<<"${output}" >&2
      exit 1
    fi
    ;;
  sourcify)
    forge verify-contract --verifier sourcify "${COMPILE_ARGS[@]}" --chain "$2" --watch "$3" "${CONTRACT}"
    ;;
  etherscan)
    forge verify-contract "${COMPILE_ARGS[@]}" --chain "$2" --rpc-url "$2" --watch --guess-constructor-args "$3" "${CONTRACT}"
    ;;
  *)
    echo "usage: $0 check | sourcify <chain-id> <address> | etherscan <network> <address>" >&2
    exit 2
    ;;
esac
