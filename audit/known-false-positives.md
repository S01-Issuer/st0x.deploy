# Known false positives

Mutation-probe survivors that no test can kill, and why. Each stays in the code
as written.

## `subgraph/src/clonefactory.ts`: template created for an already-indexed proxy

Mutant: `ReceiptVault.create(event.params.proxy)` runs even when
`createDiscoveredContract` reports the proxy is already indexed. Matchstick
cannot observe a repeated template `create`, since a data source for an address
is only ever created once in its store, so the guard is unobservable in tests.
`subgraph/tests/discovery.test.ts` records the same limitation for the deployer
path. The guard stays: graph-node would otherwise spawn a second data source for
the same address.

## `script/20261006-grant-orchestrator-emergency.s.sol`: `EmergencyNotGranted` skipped

Mutant: the post-state's `EmergencyNotGranted` check never reverts. The script
is spent: it has executed on every chain, so its preflight refuses with
`EmergencyAlreadyGranted` and its post-state is only reachable after its own
bundle, on a chain where the bundle has not run. #508 removed its test suite for
that reason. No fork at head can reach the check, so no test can kill the
mutant. The check stays: it is the script's own assertion of the role it grants,
now that `LibOrchestratorInvariants.assertInstance` no longer reads it from the
registry record.
