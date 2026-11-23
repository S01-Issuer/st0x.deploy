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

## `src/lib/LibUnderlyingNamingRollout.sol`: row check and leading-rows cut

Mutants: `assertUnderlyingsWellFormed` drops its `assertRowsWellFormed(rows)`
call, and `tokens()` returns the chain's table without `leadingRows`. Both are
equivalent while every production row is well formed and every table has exactly
`TOKEN_COUNT` rows, so no test can tell them apart. The behavior is pinned
around them: `testEveryChainsRowsAreWellFormed` checks the production rows
through `assertRowsWellFormed` directly, the row loop's refusals are tested on
built rows, `testLeadingRowsCutsALongerTableAndRefusesAShorterOne` tests the cut
on a longer table, and `testTokenSetIsPinnedByIdentity` fails on a 57th row.
Both calls stay: the rename pre-flight must check the rows it sets, and the
rename id must not move when a table grows.

## `src/lib/LibTokenInvariants.sol`: hydrated guard on the placeholder 0G table

Mutants: in `hydrated(chainId, tokens)`, the loop bound `i < tokens.length`
becomes `i < 1`, `return tokens;` becomes `return new TokenInstance[](0);`, and
`tokens[i].receiptVault` becomes `tokens[i].wrappedTokenVault`. The guard is
interim: the only table it reads is the 0G table, and every row of that table is
still a placeholder, so each mutant reverts `TokenTableNotHydrated` on the first
row exactly as the original does. On the tables that exist today the mutants are
indistinguishable; `testZerogPlaceholderTableIsRefused` pins the refusal.
Killing them is deferred to the hydration PR
([RAI-4598](https://linear.app/makeitrain/issue/RAI-4598)), which replaces the
0G table and adds 0G to
`testProductionTokenAddressesAreNonzeroAndUniquePerChain`, where the row-for-row
coverage lands. Remove this entry in that PR.
