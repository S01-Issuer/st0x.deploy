# Audit Triage — 2026-03-18-01

## Audit Notes

The codebase was significantly updated between the time audit agents ran and triage validation. Many files were rewritten (Deploy.sol, test files, new LibTestDeploy.sol, pointer files regenerated). Findings are validated against the CURRENT code state.

Three source files were not included in the agent file list due to glob result limits:
- `src/concrete/StoxWrappedTokenVaultBeacon.sol`
- `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol`
- `src/lib/LibProdDeploy.sol`

CLAUDE.md Deployment section (lines 80-83) still references old suite names (`offchain-asset-receipt-vault-beacon-set`, `wrapped-token-vault-beacon-set`, `unified-deployer`) but Deploy.sol now has 7 per-contract suites. This was not caught by audit agents because it's a post-audit change.

## Findings (LOW+)

| ID | Pass | Severity | Title | Status |
|---|---|---|---|---|
| P0-1 | 0 | MEDIUM | No guidance on library pragma convention | FIXED — CLAUDE.md line 67 documents `=0.8.25` contracts, `^0.8.25` libraries |
| P0-2 | 0 | MEDIUM | No guidance on deployment constant preservation | FIXED — added audit trail note to CLAUDE.md |
| P0-3 | 0 | LOW | No guidance on test contract file placement | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-4 | 0 | LOW | No guidance on immutable naming convention | DISMISSED — slither already flags this |
| P0-5 | 0 | MEDIUM | No guidance to prefer forge tests over cast queries | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-6 | 0 | LOW | No guidance on fork test block pinning | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-7 | 0 | LOW | No guidance on creation vs runtime bytecode | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-8 | 0 | LOW | No guidance on single-file constants | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-9 | 0 | MEDIUM | No guidance on slither configuration | FIXED — 4 items added to global ~/.claude/CLAUDE.md |
| P0-10 | 0 | LOW | No guidance on checking repo state before proceeding | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-11 | 0 | MEDIUM | No guidance on versioned deploy libraries | FIXED — CLAUDE.md lines 72-76 documents versioning approach |
| P0-12 | 0 | LOW | No guidance on dependency management ownership | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-13 | 0 | LOW | No guidance on skill installation | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-14 | 0 | LOW | No guidance on distinguishing proxies from implementations | FIXED — added to global ~/.claude/CLAUDE.md |
| P0-15 | 0 | LOW | No guidance on changelog maintenance | FIXED — CLAUDE.md line 75 documents changelog updates |
| A07-3 | 1 | LOW | Event emitted before initialization confirmed in BeaconSetDeployer | DISMISSED — intentional CEI pattern per CHANGELOG |
| A02-1 | 2 | LOW | Deploy suite branches untested | DISMISSED — deployment mechanics covered by LibProdDeployV2 tests; full script test requires multi-network RPC |
| A03-P2-1 | 2 | LOW | No behavioral unit tests for StoxReceipt | DISMISSED — all behavior is in ethgild Receipt base; testing deps is out of scope |
| A04-3 | 2 | LOW | No behavioral unit tests for StoxReceiptVault | DISMISSED — all behavior is in ethgild OffchainAssetReceiptVault base; testing deps is out of scope |
| A05-1 | 2 | LOW | Bare vm.expectRevert() in testConstructorDisablesInitializers | FIXED — now uses Initializable.InvalidInitialization.selector |
| A05-2 | 2 | LOW | Bare vm.expectRevert() in testInitializeZeroAssetViaDeployer | FIXED — now uses ZeroVaultAsset.selector |
| A05-3 | 2 | LOW | ICLONEABLE_V2_SUCCESS return value never asserted | FIXED — testInitializeReturnsCloneableV2Success added |
| A05-4 | 2 | LOW | StoxWrappedTokenVaultInitialized event not tested | FIXED — testInitializeEmitsEvent added |
| A05-5 | 2 | LOW | No double-initialization revert test | FIXED — testDoubleInitializeReverts added |
| A05-6 | 2 | MEDIUM | ERC4626 operations entirely untested | FIXED — 10 ERC4626 tests added (deposit, withdraw, mint, redeem, convert, preview, max) |
| A06-P2-1 | 2 | LOW | Integration test for StoxUnifiedDeployer not implemented | FIXED — StoxUnifiedDeployer.newTokenAndWrapperVault.t.sol added; also updated source to use V2 deployer addresses |
| A07-P2-4 | 2 | LOW | InitializeVaultFailed error path untested | FIXED — testNewVaultInitializeVaultFailed added using BadInitializeVault mock + beacon upgrade |
| A07-P2-5 | 2 | LOW | Deployment event parameters not asserted | FIXED — testNewVaultSuccess now asserts Deployment event sender and vault address |
| A08-P2-1 | 2 | LOW | BEACON_INITIAL_OWNER not verified on-chain via fork test | FIXED — V1 fork test now checks all 3 beacon owners; V2 checked in StoxWrappedTokenVaultBeacon.t.sol |
| A09-1 | 2 | LOW | No fork test verifying V2 addresses on Base mainnet | FIXED — testProdDeployBaseV2 exists in StoxProdV2.t.sol; will pass after deployment |
| A02-P3-1 | 3 | LOW | run() missing env var documentation | FIXED — @dev added documenting DEPLOYMENT_KEY and DEPLOYMENT_SUITE |
| A03-P3-1 | 3 | LOW | StoxReceipt missing @dev note and initialize encoding docs | FIXED — @dev added with base contract reference and initialize encoding |
| A05-P3-1 | 3 | LOW | StoxWrappedTokenVault constructor() has no NatSpec | FIXED — @dev added |
| A05-P3-3 | 3 | LOW | name() uses @inheritdoc for materially different implementation | FIXED — replaced @inheritdoc with accurate description |
| A05-P3-4 | 3 | LOW | symbol() uses @inheritdoc for materially different implementation | FIXED — replaced @inheritdoc with accurate description |
| A06-P3-1 | 3 | LOW | Reentrancy justification outside NatSpec tags | FIXED — converted to @dev in both StoxUnifiedDeployer and StoxWrappedTokenVaultBeaconSetDeployer |
| A07-P3-3 | 3 | LOW | @notice claims contract "manages" beacon after V2 refactor | FIXED — updated to "Deploys new StoxWrappedTokenVault beacon proxy instances" |
| A07-P3-4 | 3 | LOW | Event NatSpec says "successfully initialized" but emitted before init | DISMISSED — NatSpec is accurate; event only observable in successful transactions |
| A08-P3-1 | 3 | LOW | Missing Basescan URLs for STOX_RECEIPT_IMPLEMENTATION and STOX_RECEIPT_VAULT_IMPLEMENTATION | FIXED — Basescan URLs added |
| A09-P3-1 | 3 | LOW | LibProdDeployV2 beacon/deployer constants have zero test coverage | FIXED — 16 tests added for beacon, beacon set deployer, and OARV deployer |
| A02-P4-1 | 4 | HIGH | Deploy.t.sol imports removed constant | FIXED — both Deploy.sol and Deploy.t.sol rewritten together |
| A07-P4-2 | 4 | HIGH | Build broken — test files reference V1-era symbols | FIXED — test files rewritten to use LibTestDeploy + Zoltu |
| A07-P4-3 | 4 | LOW | Unused IBeacon import in StoxWrappedTokenVaultBeaconSetDeployer.sol | FIXED — import already removed |
| A02-P5-1 | 5 | HIGH | Ungenerated pointer placeholder — address(0) | FIXED — pointer file regenerated with real address |
| A07-P5-2 | 5 | HIGH | Build broken — duplicate of A07-P4-2 | FIXED — duplicate |
| A07-P5-3 | 5 | LOW | Unused IBeacon import — duplicate of A07-P4-3 | DISMISSED — duplicate |
| A09-P5-4 | 5 | LOW | LibProdDeployV2.t.sol missing tests for beacon and deployer constants | FIXED — same as A09-P3-1 |
| A09-P5-5 | 5 | LOW | CHANGELOG missing documentation for new V2 contracts | FIXED — CHANGELOG updated |
