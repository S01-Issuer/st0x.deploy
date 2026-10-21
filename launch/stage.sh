#!/usr/bin/env bash
# Run one broadcasting stage of the Base token launch for one token:
#
#   launch/stage.sh <symbol> <deploy|clone|wire> <forge script args...>
#
# The stage reads the previous stage's mined receipts from
# $LAUNCH_STAGE_DIR/<symbol>/<stage>.json, so forge's broadcast file is copied
# there after every run, whatever its outcome: a stage that failed after
# sending still leaves its receipts for record(). Forge overwrites
# <stage>-latest.json on every invocation, so it is deleted first, and an
# earlier token's file can never be read as this token's.
#
# A stage is retried only when it reverted with StageNotReady: the RPC has not
# reached the block the previous stage landed in, and nothing was sent. Forge
# prints the error by name when it can decode it and by selector otherwise, so
# both are matched.
set -euo pipefail

: "${LAUNCH_STAGE_DIR:?LAUNCH_STAGE_DIR must name the stage directory}"

symbol=$1
sig=$2
shift 2

script=script/20261020-launch-base-tokens.s.sol
stage_dir="${LAUNCH_STAGE_DIR}/${symbol}"
# cast sig "StageNotReady(uint256,uint256)"
not_ready='StageNotReady|0xabf07c3e'
latest="broadcast/$(basename "${script}")/8453/${sig}-latest.json"
log=$(mktemp)
trap 'rm -f "${log}"' EXIT
mkdir -p "${stage_dir}"

status=0
for attempt in 1 2 3 4 5; do
  rm -f "${latest}"
  status=0
  forge script "${script}" --sig "${sig}(string)" "${symbol}" --broadcast --slow "$@" 2>&1 \
    | tee "${log}" || status=$?
  if [[ -f "${latest}" ]]; then
    cp "${latest}" "${stage_dir}/${sig}.json"
  fi
  if [[ "${status}" == 0 ]] || ! grep -qE "${not_ready}" "${log}"; then
    break
  fi
  echo "${symbol} ${sig}: RPC behind the previous stage (attempt ${attempt}); retrying"
  sleep $((attempt * 5))
done
exit "${status}"
