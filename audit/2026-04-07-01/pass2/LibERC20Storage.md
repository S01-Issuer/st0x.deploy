# A23 — Pass 2 (Test Coverage): LibERC20Storage

**Source:** `src/lib/LibERC20Storage.sol`
**Tests:** None directly. Indirect via `LibRebaseHarness`, `LibTotalSupplyHarness`, both of which use `setOzTotalSupply`.

## Findings

### A23-P2-1 — No direct unit tests; in particular no test verifies that `LibERC20Storage` reads/writes match `ERC20Upgradeable`'s native getters/setters

**Severity:** LOW (paired with the MEDIUM A23-1 layout-drift finding)

**Location:** No test file exists for `LibERC20Storage.sol`.

The library is the load-bearing bridge between custom rebase accounting and the OZ ERC20 storage layout. There is no test that:

1. Constructs a real `ERC20Upgradeable` instance.
2. Performs a normal mint via OZ's `_mint`.
3. Asserts `LibERC20Storage.getBalance(account) == ERC20Upgradeable.balanceOf(account)`.
4. Asserts `LibERC20Storage.getTotalSupply() == ERC20Upgradeable.totalSupply()`.
5. Then performs `LibERC20Storage.setBalance(account, newValue)` and asserts the OZ getter reflects the new value.

Without this test, A23-1's silent drift scenario (an OZ submodule bump that re-orders storage) cannot be detected by CI.

**Suggested fix:** see `.fixes/A23-P2-1.md`. The fix file proposes a test contract that uses a minimal `ERC20Upgradeable` subclass (test-only), exercises the four scenarios above, and adds a regression assertion comparing slot reads to OZ getters.

The same test also doubles as the regression guard for A23-1 — if the OZ layout drifts, this test's assertions diverge.

## Items not flagged

- Indirect coverage via `LibRebaseHarness::setOzTotalSupply` and `LibTotalSupplyHarness::setOzTotalSupply` exercises the `setTotalSupply` path. But neither calls `getBalance` or `setBalance` against an OZ-managed mapping, only against the bare slot. The drift detection requires going through OZ's actual `_balances` mapping.
