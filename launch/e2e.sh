#!/usr/bin/env bash
# The staged launch, run through the real forge CLI as the deploy workflow runs
# it, against an anvil fork of Base taken at the block before tDIS's deploy.
#
#   tDIS   launches in full: its ledger row is sft-ops's row.
#   tWMT   wiring stops after its landing authoriser is set, before the
#          handoff lands: it is recorded with the signer as owner, and check()
#          reports it.
#   tSPY   wiring stops after its first transaction: no ledger row, and the
#          summary lists it.
#   tSNES  wiring refuses before sending anything (its payloads are gone): no
#          ledger row, and no other token's stage file is read as its own.
#
# A wiring is stopped by turning anvil's automine off, mining a set number of
# its transactions and making the next one revert on chain.
#
# Needs BASE_RPC_URL (an archive node), Node with launch/ffi installed, and the
# nix shell's forge, cast, anvil and jq.
set -euo pipefail

: "${BASE_RPC_URL:?BASE_RPC_URL must be set}"

SIGNER=0x21Cc8a5fe957a167cB92F12F4E658d755b00Be53
SAFE=0xe70d821f3462a074e63b42d0AaC6523faAe1d611
DIS_FORK_BLOCK=52645050
DIS_VAULT=0x40584fBad768FF46f299Cf50cAe5b3D437E213Fa
SCRIPT=script/20261020-launch-base-tokens.s.sol
PORT="${E2E_PORT:-8547}"
RPC="http://127.0.0.1:${PORT}"
WORK=out/launch-e2e

rm -rf "${WORK}"
mkdir -p "${WORK}"
echo '[]' > "${WORK}/launches.json"

export LAUNCH_PLAN="${WORK}/plan.json"
export LAUNCH_STAGE_DIR="${WORK}/stages"
export LAUNCH_LEDGER="${WORK}/launches.json"
# tDIS was planned at its launch, so its certification date is the real one.
export LAUNCH_NOW=1792079467
export LAUNCH_FILES="launch/metadata/dis.json launch/metadata/wmt.json launch/metadata/spy.json launch/metadata/snes.json"
# The real CIDs of tDIS's documents; the other tokens reuse them, as nothing
# is uploaded.
export LAUNCH_FIXED_SCHEMA_CID=bafkreihewy5a4ynph5cbwee6xzfoujfk7jh4h47hpso3rntlp45itiyzgi
export LAUNCH_FIXED_METADATA_CID=bafkreiggpf2siafql7ikqwwo5esxtmajtmybxhohid4tm22tuvbz5auogq
export LAUNCH_ALLOW_FIXED_CIDS=true

anvil --fork-url "${BASE_RPC_URL}" --fork-block-number "${DIS_FORK_BLOCK}" \
  --auto-impersonate --port "${PORT}" --silent &
ANVIL_PID=$!
trap 'kill "${ANVIL_PID}"' EXIT
for _ in $(seq 1 60); do
  cast chain-id --rpc-url "${RPC}" >/dev/null 2>&1 && break
  sleep 1
done

fail() {
  echo "e2e: $*" >&2
  exit 1
}

forge_script() {
  forge script "${SCRIPT}" "$@"
}

stage() {
  # Anvil's forked Base node rejects forge's EIP-1559 fee-history queries.
  launch/stage.sh "$1" "$2" --legacy --rpc-url "${RPC}" --unlocked --sender "${SIGNER}" "${@:3}"
}

# Mine the first $1 transactions sent to the pool, then make the next one
# revert: the code at its target is swapped for a bare REVERT while it is
# mined, then put back.
mine_then_revert() {
  local mined=0
  while true; do
    local pending
    pending=$(cast rpc txpool_content --rpc-url "${RPC}" | jq -r '.pending | .[] | .[] | .hash' | head -1)
    if [[ -n "${pending}" ]]; then
      if (( mined < $1 )); then
        cast rpc evm_mine --rpc-url "${RPC}" >/dev/null
        mined=$((mined + 1))
      else
        local target code
        target=$(cast tx "${pending}" to --rpc-url "${RPC}")
        code=$(cast code "${target}" --rpc-url "${RPC}")
        cast rpc anvil_setCode "${target}" 0x60006000fd --rpc-url "${RPC}" >/dev/null
        cast rpc evm_mine --rpc-url "${RPC}" >/dev/null
        cast rpc anvil_setCode "${target}" "${code}" --rpc-url "${RPC}" >/dev/null
        return
      fi
    fi
    sleep 0.2
  done
}

# Run the wire stage of $1 with its transaction number $2 + 1 reverting.
cut_wire() {
  cast rpc evm_setAutomine false --rpc-url "${RPC}" >/dev/null
  mine_then_revert "$2" &
  local driver=$!
  local status=0
  stage "$1" wire || status=$?
  wait "${driver}"
  cast rpc evm_setAutomine true --rpc-url "${RPC}" >/dev/null
  [[ "${status}" != 0 ]] || fail "$1 wiring should have stopped"
}

forge_script --sig 'plan()'
for symbol in tDIS tWMT tSPY tSNES; do
  forge_script --ffi --sig 'prepare(string)' "${symbol}"
done

forge_script --sig 'simulate(string)' tDIS --rpc-url "${RPC}"
simulate_nonce=$(cast nonce "${SIGNER}" --rpc-url "${RPC}")
simulate_status=0
forge_script --sig 'simulate(string)' tDIS --rpc-url "${RPC}" --broadcast --unlocked --sender "${SIGNER}" \
  >"${WORK}/simulate-broadcast.log" 2>&1 || simulate_status=$?
[[ "$(cast nonce "${SIGNER}" --rpc-url "${RPC}")" == "${simulate_nonce}" ]] || fail "simulate sent a transaction"
[[ "${simulate_status}" != 0 ]] || fail "simulate must refuse --broadcast"
grep -q SimulateCannotBroadcast "${WORK}/simulate-broadcast.log" || fail "simulate refused for another reason"
for symbol in tDIS tWMT tSPY tSNES; do
  stage "${symbol}" deploy
  stage "${symbol}" clone
done

stage tDIS wire
# Steps 3 to 8 are seven transactions; the eighth is the handoff.
cut_wire tWMT 7
cut_wire tSPY 1
rm "${LAUNCH_STAGE_DIR}/tSNES/payloads.json"
if stage tSNES wire; then
  fail "tSNES wiring should have refused"
fi
[[ ! -f "${LAUNCH_STAGE_DIR}/tSNES/wire.json" ]] || fail "tSNES kept a stale wire file"

forge_script --sig 'record()' --rpc-url "${RPC}"
if forge_script --sig 'check()' --rpc-url "${RPC}"; then
  fail "check() should report tWMT, still owned by the signer"
fi

ledger="${LAUNCH_LEDGER}"
[[ "$(jq length "${ledger}")" == 2 ]] || fail "expected two ledger rows"
[[ "$(jq -r '.[0].symbol' "${ledger}")" == tDIS ]] || fail "first row is not tDIS"
[[ "$(jq -r '.[0].sft' "${ledger}")" == "${DIS_VAULT}" ]] || fail "tDIS vault differs"
[[ "$(jq -r '.[0].currentOwner' "${ledger}")" == "${SAFE}" ]] || fail "tDIS not handed off"
[[ "$(jq -r '.[1].symbol' "${ledger}")" == tWMT ]] || fail "second row is not tWMT"
[[ "$(jq -r '.[1].currentOwner' "${ledger}")" == "${SIGNER}" ]] || fail "tWMT should still be the signer's"
summary="${LAUNCH_STAGE_DIR}/summary.md"
grep -q "tSPY: vault .* stopped before its landing authoriser was set" "${summary}" || fail "tSPY missing from the summary"
grep -q "tSNES: vault .* stopped before its landing authoriser was set" "${summary}" || fail "tSNES missing from the summary"

echo "e2e passed"
