// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";
import {LibRainDeploy} from "rain-deploy-0.1.25/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.25/src/lib/LibSafeTx.sol";
import {SafeBundleScript} from "rain-deploy-0.1.25/src/abstract/SafeBundleScript.sol";
import {LibSafeFork} from "rain-deploy-0.1.25/src/lib/LibSafeFork.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.25/src/lib/LibSafeTxBuilderJson.sol";

import {
    DeployUnderlyingNamingImplementations
} from "../../script/20261021-deploy-underlying-naming-implementations.s.sol";
import {
    ExecuteUnderlyingNaming,
    NoUnderlyingNamingOperationReady,
    UnderlyingNamingExecutorHoldsRole
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    ScheduleUnderlyingNamingBeacons,
    ImplementationNotDeployed,
    BeaconAlreadyUpgraded,
    OperationAlreadyScheduled
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {
    ScheduleUnderlyingNamingRename,
    BeaconBatchNotScheduled,
    RenameAlreadyScheduled,
    RenamedMetadataMismatch
} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";

import {ICorporateActionsV1} from "../../src/interface/ICorporateActionsV1.sol";
import {IStoxUnderlyingV1} from "../../src/interface/IStoxUnderlyingV1.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {MintAuthV1, Digest} from "../../src/interface/IST0xOrchestratorV2.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibTimelockController} from "rain-deploy-0.1.25/src/lib/LibTimelockController.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {
    LibTokenInvariants,
    TokenInstance,
    ReceiptVaultOwnerMismatch,
    NoTokenTableForChain
} from "../../src/lib/LibTokenInvariants.sol";
import {BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {ST0X_NAME_SUFFIX} from "../../src/lib/LibUnderlying.sol";
import {IOwnable} from "../../src/interface/IOwnable.sol";
import {
    LibUnderlyingNamingRollout,
    TickerNotBoundToVault,
    UnderlyingNamingReleaseNotFrozen
} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title UnderlyingNamingRolloutTest
/// @notice The underlying-naming rollout on every deployment network. Per
/// network, whatever part of the rollout is not yet on chain is authored,
/// verified and executed on a fork with the candidate implementations
/// planted, executed from a roleless key, and every production vault and
/// wrapper is checked renamed. The refusal tests cover each pre-flight check.
contract UnderlyingNamingRolloutTest is Test {
    /// @notice Distinguishes each mint-and-burn round's operator and nonce.
    uint256 internal sMintRound;

    /// @notice Plants the three implementations at their pinned addresses,
    /// running their constructors there (the facet's `_SELF`).
    function plantImplementations() internal {
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet", LibUnderlyingNamingRollout.FACET
        );
        deployCodeTo(
            "src/concrete/StoxReceiptVault.sol:StoxReceiptVault",
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION
        );
        deployCodeTo(
            "src/concrete/StoxWrappedTokenVault.sol:StoxWrappedTokenVault",
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        );
    }

    /// @notice The beacon batch is exactly: the wrapper beacon upgrade, the
    /// vault beacon upgrade, then the facet probe on the first production
    /// vault.
    function assertBeaconBatchExact(uint256 chainId) internal view {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.beaconBatch(chainId);
        assertEq(targets.length, 3, "beacon batch length");
        assertEq(targets[0], LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(chainId), "wrapper beacon");
        assertEq(
            payloads[0],
            abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION))
        );
        assertEq(targets[1], LibUnderlyingNamingRollout.receiptVaultBeacon(chainId), "vault beacon");
        assertEq(
            payloads[1],
            abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION))
        );
        assertEq(targets[2], LibUnderlyingNamingRollout.tokens(chainId)[0].receiptVault, "probe vault");
        assertEq(payloads[2], abi.encodeCall(ICorporateActionsV1.completedActionCount, ()));
        for (uint256 callIndex = 0; callIndex < values.length; callIndex++) {
            assertEq(values[callIndex], 0, "value");
        }
    }

    /// @notice The rename batch is exactly one `setUnderlying(underlying,
    /// underlyingName)` per production token of the chain, in table order,
    /// and every row's symbol is `"t" + underlying`.
    function assertRenameBatchExact(uint256 chainId) internal pure {
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainId);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.renameBatch(chainId);
        assertEq(targets.length, chainTokens.length, "one call per production token");
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            string memory ticker = chainTokens[tokenIndex].underlying;
            TokenConfig memory config = LibProdTokenConfig.configOf(ticker);
            assertEq(config.underlying, ticker, ticker);
            assertEq(config.symbol, string.concat("t", ticker), ticker);
            assertEq(targets[tokenIndex], chainTokens[tokenIndex].receiptVault, ticker);
            assertEq(values[tokenIndex], 0, ticker);
            (string memory setTicker, string memory setName) = decodeSetUnderlying(payloads[tokenIndex]);
            assertEq(setTicker, ticker, ticker);
            assertEq(setName, config.underlyingName, ticker);
        }
    }

    /// @notice Decodes a `setUnderlying` call after checking its selector.
    function decodeSetUnderlying(bytes memory payload)
        internal
        pure
        returns (string memory ticker, string memory plainName)
    {
        bytes memory selector = abi.encodePacked(IStoxUnderlyingV1.setUnderlying.selector);
        for (uint256 byteIndex = 0; byteIndex < selector.length; byteIndex++) {
            assertEq(payload[byteIndex], selector[byteIndex], "selector");
        }
        bytes memory args = new bytes(payload.length - 4);
        for (uint256 byteIndex = 0; byteIndex < args.length; byteIndex++) {
            args[byteIndex] = payload[byteIndex + 4];
        }
        (ticker, plainName) = abi.decode(args, (string, string));
    }

    /// @notice The rollout renames 56 rows on every chain, from MSTR to DIS,
    /// pinned by literals so a changed `TOKEN_COUNT` or a reordered table
    /// fails here.
    function testTokenSetIsPinnedByIdentity() external pure {
        assertEq(LibUnderlyingNamingRollout.TOKEN_COUNT, 56, "count");
        uint256[5] memory chainIds = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 chainIndex = 0; chainIndex < chainIds.length; chainIndex++) {
            TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainIds[chainIndex]);
            assertEq(chainTokens.length, 56, "chain count");
            assertEq(chainTokens[0].underlying, "MSTR", "first row");
            assertEq(chainTokens[53].underlying, "WMT", "row 53");
            assertEq(chainTokens[54].underlying, "MC", "row 54");
            assertEq(chainTokens[55].underlying, "DIS", "last row");
        }
    }

    /// @notice A chain with no token table refuses rather than resolving to
    /// another chain's vaults.
    function testTokensRefusesAnUnsupportedChain() external {
        vm.expectRevert(abi.encodeWithSelector(NoTokenTableForChain.selector, uint256(1337)));
        this.externalTokens(1337);
    }

    function externalTokens(uint256 chainId) external pure returns (TokenInstance[] memory) {
        return LibUnderlyingNamingRollout.tokens(chainId);
    }

    function testRenameBatchExactBase() external pure {
        assertRenameBatchExact(LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testRenameBatchExactEthereum() external pure {
        assertRenameBatchExact(LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testRenameBatchExactHyperEvm() external pure {
        assertRenameBatchExact(LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testRenameBatchExactRobinhood() external pure {
        assertRenameBatchExact(LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testRenameBatchExactBsc() external pure {
        assertRenameBatchExact(LibSafeInvariants.BSC_CHAIN_ID);
    }

    /// @dev For the issuers renamed since launch, the name the live `name`
    /// carries and the issuer's current legal name: MicroStrategy Incorporated
    /// became Strategy Inc (August 2025), and Rocket Lab USA, Inc. was replaced
    /// as the listed company by Rocket Lab Corporation (May 2025). Both empty
    /// for every other ticker.
    function renamedIssuer(string memory underlying)
        internal
        pure
        returns (string memory launchName, string memory currentName)
    {
        if (keccak256(bytes(underlying)) == keccak256("MSTR")) {
            return ("MicroStrategy Incorporated", "Strategy Inc");
        }
        if (keccak256(bytes(underlying)) == keccak256("RKLB")) return ("Rocket Lab USA Inc", "Rocket Lab Corporation");
        return ("", "");
    }

    /// @notice Every underlying name is the live name without its " ST0x"
    /// suffix and without surrounding whitespace, except for renamed
    /// issuers, whose live name carries the launch name and whose underlying
    /// name is pinned to the current legal name.
    function testUnderlyingNamesAreTheTrimmedLiveNames() external pure {
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        uint256 renamedSeen = 0;
        for (uint256 rowIndex = 0; rowIndex < configs.length; rowIndex++) {
            TokenConfig memory config = configs[rowIndex];
            bytes memory plain = bytes(config.underlyingName);
            assertGt(plain.length, 0, config.underlying);
            assertTrue(plain[0] != " " && plain[plain.length - 1] != " ", config.underlying);
            (string memory launchName, string memory currentName) = renamedIssuer(config.underlying);
            if (bytes(launchName).length > 0) {
                renamedSeen++;
                assertEq(config.underlyingName, currentName, config.underlying);
            } else {
                launchName = config.underlyingName;
            }
            assertEq(string.concat(launchName, " ST0x"), vm.trim(config.name), config.underlying);
            assertFalse(vm.contains(config.underlyingName, "ST0x"), config.underlying);
        }
        assertEq(renamedSeen, 2, "both renamed issuers are listed");
    }

    /// @notice The step-1 deploy refuses: no frozen, audited release carries
    /// these implementations yet.
    function testDeployStubRefuses() external {
        DeployUnderlyingNamingImplementations deploy = new DeployUnderlyingNamingImplementations();
        vm.expectRevert(UnderlyingNamingReleaseNotFrozen.selector);
        deploy.run();
    }

    /// @notice Authors, verifies and executes both batches on `network` and
    /// checks the result; asserts the renamed state where the rollout has
    /// executed.
    function assertRollout(string memory network) internal {
        vm.createSelectFork(network);
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock, chainId);
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, chainId);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness(network);

        if (controller.isOperationDone(renameId)) {
            console2.log(string.concat("EXECUTED [", network, "]: asserting the renamed state"));
            rename.callAssertRenamed(chainId);
            return;
        }
        console2.log(string.concat("PENDING [", network, "]: authoring and executing the rollout on the fork"));

        assertBeaconBatchExact(chainId);
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness(network);
        if (!controller.isOperation(beaconId)) {
            // Before step 1 the beacon batch refuses.
            if (LibUnderlyingNamingRollout.FACET.code.length == 0) {
                vm.expectPartialRevert(ImplementationNotDeployed.selector);
                beacons.callPreflight();
                vm.expectRevert(abi.encodeWithSelector(BeaconBatchNotScheduled.selector, beaconId));
                rename.callPreflight();
            }
            plantImplementations();
            authorVerifyExecute(address(beacons), beacons.callArtifactPath());
        }
        completeOwnershipHandover(chainId, rename);
        if (!controller.isOperation(renameId)) {
            authorVerifyExecute(address(rename), rename.callArtifactPath());
        }

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteUnderlyingNaming execute = new ExecuteUnderlyingNaming();
        if (!controller.isOperationDone(beaconId)) execute.run();
        assertEq(
            IBeacon(LibUnderlyingNamingRollout.receiptVaultBeacon(chainId)).implementation(),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION
        );
        logRenameExecutionGas(controller, chainId, beaconId);
        execute.run();
        assertTrue(controller.isOperationDone(renameId), "rename executed");
        rename.callAssertRenamed(chainId);

        vm.expectPartialRevert(NoUnderlyingNamingOperationReady.selector);
        execute.run();
    }

    /// @notice `run()` authors and proves the bundle on a snapshot, `verify`
    /// holds the artifact to the live re-derivation, and the artifact is then
    /// executed by the owners as the Safe UI would.
    function authorVerifyExecute(address script, string memory artifactPath) internal {
        uint256 preRun = vm.snapshotState();
        SafeBundleScript(script).run();
        vm.revertToState(preRun);
        SafeBundleScript(script).verify(artifactPath);
        (, address artifactSafe, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(artifactPath));
        assertEq(artifactSafe, LibSafeInvariants.safeForChainId(block.chainid), "artifact Safe");
        uint256 gasBefore = gasleft();
        LibSafeFork.executeBundle(vm, Safe(payable(artifactSafe)), txs);
        console2.log("Safe bundle execution gas (upper bound, includes signing):", gasBefore - gasleft());
    }

    /// @notice Every production vault must be owned by the timelock before
    /// the rename batch can be authored. Where one is not, the rename
    /// pre-flight refuses, and the pending ownership handover is applied on the
    /// fork so the rest of the rollout can be exercised.
    function completeOwnershipHandover(uint256 chainId, ScheduleUnderlyingNamingRenameHarness rename) internal {
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainId);
        bool refused = false;
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            address owner = IOwnable(chainTokens[tokenIndex].receiptVault).owner();
            if (owner == timelock) continue;
            if (!refused) {
                vm.expectPartialRevert(ReceiptVaultOwnerMismatch.selector);
                rename.callPreflight();
                refused = true;
            }
            console2.log("PREREQUISITE: vault not owned by the timelock, handed over on the fork");
            console2.log(chainTokens[tokenIndex].receiptVault);
            vm.prank(owner);
            OwnableUpgradeable(chainTokens[tokenIndex].receiptVault).transferOwnership(timelock);
        }
    }

    /// @notice Logs the gas the rename batch's `executeBatch` alone takes, on a
    /// snapshot: what the executing key must fit in one block.
    function logRenameExecutionGas(TimelockController controller, uint256 chainId, bytes32 beaconId) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.renameBatch(chainId);
        uint256 snapshot = vm.snapshotState();
        uint256 gasBefore = gasleft();
        controller.executeBatch(targets, values, payloads, beaconId, LibUnderlyingNamingRollout.RENAME_SALT);
        console2.log("Rename batch executeBatch gas:", gasBefore - gasleft());
        vm.revertToState(snapshot);
    }

    function testRolloutBase() external {
        assertRollout(LibRainDeploy.BASE);
    }

    function testRolloutEthereum() external {
        assertRollout(LibStoxDeployNetworks.ETHEREUM);
    }

    function testRolloutHyperEvm() external {
        assertRollout(LibStoxDeployNetworks.HYPEREVM);
    }

    function testRolloutRobinhood() external {
        assertRollout(LibStoxDeployNetworks.ROBINHOOD);
    }

    function testRolloutBsc() external {
        assertRollout(LibStoxDeployNetworks.BSC);
    }

    /// @notice On Base, before execution: after both batches NVDA reads
    /// `tNVDA` / `NVDAs` / `NVIDIA Corporation (ST0x)`, and the orchestrator
    /// keeps minting and burning NVDA across the beacon upgrade.
    function testBaseNvdaAndOrchestratorAcrossTheRollout() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TimelockController controller = TimelockController(payable(timelock));
        if (controller.isOperation(LibUnderlyingNamingRollout.beaconOperationId(timelock, chainId))) {
            console2.log("SPENT: the beacon batch is scheduled or executed on Base");
            return;
        }
        ST0xOrchestrator orchestrator = ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));
        assertTrue(
            IST0xOrchestratorV1(address(orchestrator)).vaultLogicIsExpected(), "lock accepts the beacon set before"
        );

        plantImplementations();
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("nvda");
        authorVerifyExecute(address(beacons), beacons.callArtifactPath());
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("nvda");
        completeOwnershipHandover(chainId, rename);
        authorVerifyExecute(address(rename), rename.callArtifactPath());
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteUnderlyingNaming execute = new ExecuteUnderlyingNaming();
        execute.run();

        assertTrue(
            IST0xOrchestratorV1(address(orchestrator)).vaultLogicIsExpected(), "lock accepts the beacon set after"
        );
        mintAndBurn(orchestrator, LibTokenInvariants.NVDA_RECEIPT_VAULT);

        // Upgraded but not yet renamed: the initialized metadata stands.
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).symbol(), "tNVDA");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).symbol(), "wtNVDA");

        execute.run();
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).symbol(), "tNVDA");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).name(), "NVIDIA Corporation (ST0x)");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).symbol(), "NVDAs");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).name(), "NVIDIA Corporation (ST0x)");
        mintAndBurn(orchestrator, LibTokenInvariants.NVDA_RECEIPT_VAULT);
    }

    /// @notice Mints `token` through the live orchestrator to a fresh EOA that
    /// signs its own authorisation, then burns it back, with roles granted by
    /// the orchestrator's current admin.
    function mintAndBurn(ST0xOrchestrator orchestrator, address token) internal {
        sMintRound++;
        (address operator, uint256 key) = makeAddrAndKey(string.concat("operator-", vm.toString(sMintRound)));
        grantOperator(orchestrator, operator);
        uint256 amount = 1e18;
        uint256 supplyBefore = IERC20(token).totalSupply();
        mintTo(orchestrator, token, operator, key, amount);
        assertEq(IERC20(token).balanceOf(operator), amount, "minted");
        vm.startPrank(operator);
        IERC20(token).approve(address(orchestrator), amount);
        orchestrator.burn(token, amount, "");
        vm.stopPrank();
        assertEq(IERC20(token).balanceOf(operator), 0, "burned");
        assertEq(IERC20(token).totalSupply(), supplyBefore, "supply restored");
    }

    /// @notice Grants `operator` MINT and BURN as the orchestrator's current
    /// admin.
    function grantOperator(ST0xOrchestrator orchestrator, address operator) internal {
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address admin =
            orchestrator.hasRole(bytes32(0), safe) ? safe : LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 mintRole = orchestrator.MINT_ROLE();
        bytes32 burnRole = orchestrator.BURN_ROLE();
        vm.startPrank(admin);
        orchestrator.grantRole(mintRole, operator);
        orchestrator.grantRole(burnRole, operator);
        vm.stopPrank();
    }

    /// @notice Mints `amount` of `token` to `operator`, which signs its own
    /// authorisation.
    function mintTo(ST0xOrchestrator orchestrator, address token, address operator, uint256 key, uint256 amount)
        internal
    {
        bytes32 nonce = keccak256(abi.encode(token, sMintRound));
        bytes32 digest = Digest.unwrap(orchestrator.mintAuthDigest(token, operator, amount, nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        vm.prank(operator);
        orchestrator.mint(token, operator, amount, MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)}), "");
    }

    /// @notice Whether the beacon batch is already registered on the forked
    /// chain. The refusal tests below build their own beacon batch on a fork of
    /// the latest block, so once the real rollout starts they have nothing to
    /// refuse and log `SPENT` instead.
    function beaconBatchSpent() internal view returns (bool) {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock, block.chainid);
        if (!TimelockController(payable(timelock)).isOperation(beaconId)) return false;
        console2.log("SPENT: the beacon batch is scheduled or executed on this chain");
        return true;
    }

    /// @notice Brings the forked chain to the point where the rename can be
    /// authored: the beacon batch registered (authored here only if it is not
    /// on chain yet) and every vault owned by the timelock. Returns false and
    /// logs `SPENT` once the rename itself is registered on chain, the only
    /// state in which the rename refusal tests have nothing left to refuse.
    function prepareRename(ScheduleUnderlyingNamingRenameHarness rename) internal returns (bool) {
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        TimelockController controller = TimelockController(payable(timelock));
        if (controller.isOperation(LibUnderlyingNamingRollout.renameOperationId(timelock, block.chainid))) {
            console2.log("SPENT: the rename batch is scheduled or executed on this chain");
            return false;
        }
        plantImplementations();
        if (!controller.isOperation(LibUnderlyingNamingRollout.beaconOperationId(timelock, block.chainid))) {
            ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("prepare");
            LibSafeFork.executeBundle(
                vm, Safe(payable(LibSafeInvariants.safeForChainId(block.chainid))), beacons.callAuthorBundle()
            );
        }
        completeOwnershipHandover(block.chainid, rename);
        return true;
    }

    /// @notice Until the release is frozen, both schedule scripts refuse in
    /// `run()` and `verify()`, even with the implementations deployed.
    function testSchedulingRefusesUntilTheReleaseIsFrozen() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        plantImplementations();
        ScheduleUnderlyingNamingBeacons beacons = new ScheduleUnderlyingNamingBeacons();
        ScheduleUnderlyingNamingRename rename = new ScheduleUnderlyingNamingRename();
        vm.expectRevert(UnderlyingNamingReleaseNotFrozen.selector);
        beacons.run();
        vm.expectRevert(UnderlyingNamingReleaseNotFrozen.selector);
        beacons.verify("out/never-written.json");
        vm.expectRevert(UnderlyingNamingReleaseNotFrozen.selector);
        rename.run();
        vm.expectRevert(UnderlyingNamingReleaseNotFrozen.selector);
        rename.verify("out/never-written.json");
    }

    /// @notice The beacon pre-flight refuses each missing implementation by
    /// name, with the others present.
    function testBeaconPreflightRefusesEachMissingImplementation() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (beaconBatchSpent()) return;
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("refusals");
        address[3] memory implementations = [
            LibUnderlyingNamingRollout.FACET,
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION,
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        ];
        bytes32[3] memory codehashes = [
            LibUnderlyingNamingRollout.FACET_CODEHASH,
            LibUnderlyingNamingRollout.RECEIPT_VAULT_CODEHASH,
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_CODEHASH
        ];
        plantImplementations();
        beacons.callPreflight();
        for (uint256 missing = 0; missing < implementations.length; missing++) {
            uint256 snapshot = vm.snapshotState();
            vm.etch(implementations[missing], hex"00");
            vm.expectRevert(
                abi.encodeWithSelector(
                    ImplementationNotDeployed.selector,
                    implementations[missing],
                    codehashes[missing],
                    keccak256(hex"00")
                )
            );
            beacons.callPreflight();
            vm.revertToState(snapshot);
        }
    }

    /// @notice The beacon pre-flight refuses once either beacon has moved, and
    /// once the operation is registered.
    function testBeaconPreflightRefusesAnUpgradedBeaconAndARegisteredOperation() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (beaconBatchSpent()) return;
        plantImplementations();
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("refusals");
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        address[2] memory beaconAddresses = [
            LibUnderlyingNamingRollout.receiptVaultBeacon(block.chainid),
            LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(block.chainid)
        ];
        address[2] memory targets = [
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION,
            LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION
        ];
        for (uint256 beaconIndex = 0; beaconIndex < beaconAddresses.length; beaconIndex++) {
            uint256 snapshot = vm.snapshotState();
            vm.prank(timelock);
            UpgradeableBeacon(beaconAddresses[beaconIndex]).upgradeTo(targets[beaconIndex]);
            vm.expectRevert(abi.encodeWithSelector(BeaconAlreadyUpgraded.selector, beaconAddresses[beaconIndex]));
            beacons.callPreflight();
            vm.revertToState(snapshot);
        }

        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), beacons.callAuthorBundle());
        vm.expectRevert(
            abi.encodeWithSelector(
                OperationAlreadyScheduled.selector,
                LibUnderlyingNamingRollout.beaconOperationId(timelock, block.chainid)
            )
        );
        beacons.callPreflight();
    }

    /// @notice The rename pre-flight refuses once the rename is registered.
    function testRenamePreflightRefusesARegisteredRename() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("refusals");
        if (!prepareRename(rename)) return;
        rename.callPreflight();
        LibSafeFork.executeBundle(vm, Safe(payable(safe)), rename.callAuthorBundle());
        vm.expectRevert(
            abi.encodeWithSelector(
                RenameAlreadyScheduled.selector, LibUnderlyingNamingRollout.renameOperationId(timelock, block.chainid)
            )
        );
        rename.callPreflight();
    }

    /// @notice The executor refuses a key that holds the timelock's executor
    /// role, before executing anything.
    function testExecutorRefusesAKeyHoldingTheExecutorRole() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ExecuteUnderlyingNaming execute = new ExecuteUnderlyingNaming();
        bytes32 executorRole = LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE;
        vm.prank(timelock);
        TimelockController(payable(timelock)).grantRole(executorRole, address(this));
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingExecutorHoldsRole.selector, timelock, address(this)));
        execute.run();
    }

    /// @notice A ticker that does not match its vault's live symbol refuses.
    function testTickerBindingRefusesAMismatchedVault() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        TokenInstance memory first = LibUnderlyingNamingRollout.tokens(block.chainid)[0];
        vm.mockCall(first.receiptVault, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("tWRONG"));
        vm.expectRevert(
            abi.encodeWithSelector(TickerNotBoundToVault.selector, first.underlying, first.receiptVault, "tWRONG")
        );
        this.externalAssertTickersBound(block.chainid);
    }

    function externalAssertTickersBound(uint256 chainId) external view {
        LibUnderlyingNamingRollout.assertTickersBound(chainId);
    }

    /// @notice The beacon pre-flight refuses when the timelock does not own an
    /// in-use beacon, and when the timelock is not in its pinned state.
    function testBeaconPreflightRefusesBeaconOwnerAndTimelockState() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        if (beaconBatchSpent()) return;
        plantImplementations();
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("owners");
        beacons.callPreflight();
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);

        uint256 snapshot = vm.snapshotState();
        address vaultBeacon = LibUnderlyingNamingRollout.receiptVaultBeacon(block.chainid);
        vm.prank(timelock);
        UpgradeableBeacon(vaultBeacon).transferOwnership(address(0xbeef));
        vm.expectRevert(abi.encodeWithSelector(BeaconOwnerMismatch.selector, vaultBeacon, timelock, address(0xbeef)));
        beacons.callPreflight();
        vm.revertToState(snapshot);

        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        vm.prank(timelock);
        TimelockController(payable(timelock)).revokeRole(LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE, safe);
        vm.expectRevert(
            abi.encodeWithSelector(
                LibTimelockController.TimelockMissingRole.selector,
                timelock,
                LibTimelockInvariants.TIMELOCK_PROPOSER_ROLE,
                safe
            )
        );
        beacons.callPreflight();
    }

    /// @notice The rename pre-flight binds each ticker to its vault: with
    /// everything else ready, a vault whose live symbol does not match its
    /// row refuses.
    function testRenamePreflightRefusesAMismatchedTicker() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("ticker");
        if (!prepareRename(rename)) return;
        rename.callPreflight();
        TokenInstance memory last =
            LibUnderlyingNamingRollout.tokens(block.chainid)[LibUnderlyingNamingRollout.TOKEN_COUNT - 1];
        vm.mockCall(last.receiptVault, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("tWRONG"));
        vm.expectRevert(
            abi.encodeWithSelector(TickerNotBoundToVault.selector, last.underlying, last.receiptVault, "tWRONG")
        );
        rename.callPreflight();
    }

    /// @notice After the rollout executes, `assertRenamed` refuses a token
    /// whose vault symbol, vault name, wrapper symbol or wrapper name is not
    /// the renamed value.
    function testAssertRenamedRefusesEachWrongField() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        uint256 chainId = block.chainid;
        address safe = LibSafeInvariants.safeForChainId(chainId);
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("renamed");
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, chainId);
        // Whatever part of the rollout is not on chain yet runs on the fork,
        // so the refusals below hold in every state, renamed included.
        if (!controller.isOperation(renameId)) {
            assertTrue(prepareRename(rename), "prepared");
            LibSafeFork.executeBundle(vm, Safe(payable(safe)), rename.callAuthorBundle());
        }
        if (!controller.isOperationDone(renameId)) {
            // forge-lint: disable-next-line(block-timestamp)
            vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
            ExecuteUnderlyingNaming execute = new ExecuteUnderlyingNaming();
            if (!controller.isOperationDone(LibUnderlyingNamingRollout.beaconOperationId(timelock, chainId))) {
                execute.run();
            }
            execute.run();
        }
        rename.callAssertRenamed(chainId);

        TokenInstance memory token = LibUnderlyingNamingRollout.tokens(chainId)[0];
        string memory vaultName =
            string.concat(LibProdTokenConfig.configOf(token.underlying).underlyingName, ST0X_NAME_SUFFIX);
        address[4] memory targets =
            [token.receiptVault, token.receiptVault, token.wrappedTokenVault, token.wrappedTokenVault];
        bytes4[4] memory selectors = [
            IERC20Metadata.symbol.selector,
            IERC20Metadata.name.selector,
            IERC20Metadata.symbol.selector,
            IERC20Metadata.name.selector
        ];
        string[4] memory expected =
            [string.concat("t", token.underlying), vaultName, string.concat(token.underlying, "s"), vaultName];
        for (uint256 field = 0; field < 4; field++) {
            uint256 snapshot = vm.snapshotState();
            vm.mockCall(targets[field], abi.encodeWithSelector(selectors[field]), abi.encode("WRONG"));
            vm.expectRevert(
                abi.encodeWithSelector(RenamedMetadataMismatch.selector, targets[field], expected[field], "WRONG")
            );
            rename.callAssertRenamed(chainId);
            vm.clearMockedCalls();
            vm.revertToState(snapshot);
        }
    }
}
