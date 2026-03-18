# Audit Triage — 2026-03-18-01

## Audit Notes

Three source files were not included in passes 1-3 due to glob result limits:
- `src/concrete/StoxWrappedTokenVaultBeacon.sol` (12 lines, inherits UpgradeableBeacon)
- `src/concrete/deploy/StoxOffchainAssetReceiptVaultBeaconSetDeployer.sol` (25 lines, inherits with hardcoded config)
- `src/lib/LibProdDeploy.sol` (12 lines, version-independent BEACON_INITIAL_OWNER constant)

These were discovered during triage validation. Pass 4 and 5 agents did discover them cross-referentially.

## Findings (LOW+)

| ID | Pass | Severity | Title | Status |
|---|---|---|---|---|
| P0-1 | 0 | MEDIUM | No guidance on library pragma convention | PENDING |
| P0-2 | 0 | MEDIUM | No guidance on deployment constant preservation | PENDING |
| P0-3 | 0 | LOW | No guidance on test contract file placement | PENDING |
| P0-4 | 0 | LOW | No guidance on immutable naming convention | PENDING |
| P0-5 | 0 | MEDIUM | No guidance to prefer forge tests over cast queries | PENDING |
| P0-6 | 0 | LOW | No guidance on fork test block pinning | PENDING |
| P0-7 | 0 | LOW | No guidance on creation vs runtime bytecode | PENDING |
| P0-8 | 0 | LOW | No guidance on single-file constants | PENDING |
| P0-9 | 0 | MEDIUM | No guidance on slither configuration | PENDING |
| P0-10 | 0 | LOW | No guidance on checking repo state before proceeding | PENDING |
| P0-11 | 0 | MEDIUM | No guidance on versioned deploy libraries | PENDING |
| P0-12 | 0 | LOW | No guidance on dependency management ownership | PENDING |
| P0-13 | 0 | LOW | No guidance on skill installation | PENDING |
| P0-14 | 0 | LOW | No guidance on distinguishing proxies from implementations | PENDING |
| P0-15 | 0 | LOW | No guidance on changelog maintenance | PENDING |
| A07-3 | 1 | LOW | Event emitted before initialization confirmed in BeaconSetDeployer | PENDING |
| A02-1 | 2 | LOW | Deploy suite branches untested | PENDING |
| A03-P2-1 | 2 | LOW | No behavioral unit tests for StoxReceipt | PENDING |
| A04-3 | 2 | LOW | No behavioral unit tests for StoxReceiptVault | PENDING |
| A05-1 | 2 | LOW | Bare vm.expectRevert() in testConstructorDisablesInitializers | PENDING |
| A05-2 | 2 | LOW | Bare vm.expectRevert() in testInitializeZeroAssetViaDeployer | PENDING |
| A05-3 | 2 | LOW | ICLONEABLE_V2_SUCCESS return value never asserted | PENDING |
| A05-4 | 2 | LOW | StoxWrappedTokenVaultInitialized event not tested | PENDING |
| A05-5 | 2 | LOW | No double-initialization revert test | PENDING |
| A05-6 | 2 | MEDIUM | ERC4626 operations entirely untested | PENDING |
| A06-P2-1 | 2 | LOW | Integration test for StoxUnifiedDeployer not implemented | PENDING |
| A07-P2-4 | 2 | LOW | InitializeVaultFailed error path untested | PENDING |
| A07-P2-5 | 2 | LOW | Deployment event parameters not asserted | PENDING |
| A08-P2-1 | 2 | LOW | BEACON_INITIAL_OWNER not verified on-chain via fork test | PENDING |
| A09-1 | 2 | LOW | No fork test verifying V2 addresses on Base mainnet | PENDING |
| A02-P3-1 | 3 | LOW | run() missing env var documentation | PENDING |
| A03-P3-1 | 3 | LOW | StoxReceipt missing @dev note and initialize encoding docs | PENDING |
| A05-P3-1 | 3 | LOW | StoxWrappedTokenVault constructor() has no NatSpec | PENDING |
| A05-P3-3 | 3 | LOW | name() uses @inheritdoc for materially different implementation | PENDING |
| A05-P3-4 | 3 | LOW | symbol() uses @inheritdoc for materially different implementation | PENDING |
| A06-P3-1 | 3 | LOW | Reentrancy justification outside NatSpec tags | PENDING |
| A07-P3-3 | 3 | LOW | @notice claims contract "manages" beacon after V2 refactor removed management | PENDING |
| A07-P3-4 | 3 | LOW | Event NatSpec says "successfully initialized" but emitted before init | PENDING |
| A08-P3-1 | 3 | LOW | Missing Basescan URLs for STOX_RECEIPT_IMPLEMENTATION and STOX_RECEIPT_VAULT_IMPLEMENTATION | PENDING |
| A09-P3-1 | 3 | LOW | LibProdDeployV2 beacon/deployer constants have zero test coverage | PENDING |
| A02-P4-1 | 4 | ~~HIGH~~ | ~~Deploy.t.sol imports removed constant~~ | DISMISSED — constant still exists at Deploy.sol:23; agent misread |
| A07-P4-2 | 4 | HIGH | Build broken — test files reference V1-era symbols removed in refactor | PENDING |
| A07-P4-3 | 4 | LOW | Unused IBeacon import in StoxWrappedTokenVaultBeaconSetDeployer.sol | PENDING |
| A02-P5-1 | 5 | HIGH | Ungenerated pointer placeholder — StoxOffchainAssetReceiptVaultBeaconSetDeployer address(0) | PENDING |
| A07-P5-2 | 5 | HIGH | Build broken — test files reference removed V1-era symbols | DISMISSED — duplicate of A07-P4-2 |
| A07-P5-3 | 5 | LOW | Unused IBeacon import | DISMISSED — duplicate of A07-P4-3 |
| A09-P5-4 | 5 | LOW | LibProdDeployV2.t.sol missing tests for beacon and deployer constants | PENDING |
| A09-P5-5 | 5 | LOW | CHANGELOG missing documentation for new V2 contracts | PENDING |
