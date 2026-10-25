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
