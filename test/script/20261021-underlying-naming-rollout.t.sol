// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/IBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts-5.7.0/token/ERC20/extensions/IERC20Metadata.sol";
import {LibRainDeploy, SupportedNetwork} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";

import {
    ExecuteUnderlyingNaming,
    NoUnderlyingNamingOperationReady,
    UnderlyingNamingExecutorHoldsRole,
    UnderlyingNamingNotExecuted
} from "../../script/20261021-execute-underlying-naming.s.sol";
import {
    ScheduleUnderlyingNamingBeacons,
    ImplementationNotDeployed,
    BeaconAlreadyUpgraded,
    OperationAlreadyScheduled
} from "../../script/20261021-schedule-underlying-naming-beacons.s.sol";
import {
    ScheduleUnderlyingNamingRename,
    RenameAlreadyScheduled,
    RenamedMetadataMismatch
} from "../../script/20261021-schedule-underlying-naming-rename.s.sol";
import {ScheduleUnderlyingNamingBeaconsHarness} from "./ScheduleUnderlyingNamingBeaconsHarness.sol";
import {ScheduleUnderlyingNamingRenameHarness} from "./ScheduleUnderlyingNamingRenameHarness.sol";
import {ExecuteUnderlyingNamingHarness} from "./ExecuteUnderlyingNamingHarness.sol";
import {LibTestPreBackfillFork} from "../lib/LibTestPreBackfillFork.sol";
import {UnderlyingNamingRolloutFixture} from "./UnderlyingNamingRolloutFixture.sol";
import {LibStoxMigrations, UnexpectedMigrationLine} from "../../src/lib/LibStoxMigrations.sol";

import {ICorporateActionsV1} from "../../src/interface/ICorporateActionsV1.sol";
import {IStoxUnderlyingV1} from "../../src/interface/IStoxUnderlyingV1.sol";
import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {MintAuthV1, Digest} from "../../src/interface/IST0xOrchestratorV2.sol";
import {IST0xOrchestratorV1} from "../../src/interface/deprecated/IST0xOrchestratorV1.sol";
import {LibTimelockController} from "rain-deploy-0.1.30/src/lib/LibTimelockController.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance, NoTokenTableForChain} from "../../src/lib/LibTokenInvariants.sol";
import {BeaconOwnerMismatch} from "../../src/lib/LibBeaconInvariants.sol";
import {ST0X_NAME_SUFFIX} from "../../src/lib/LibUnderlying.sol";
import {LibTestTokenMetadata} from "../lib/LibTestTokenMetadata.sol";
import {
    LibUnderlyingNamingRollout,
    TickerNotBoundToVault,
    UnderlyingNamingReleaseNotFrozen
} from "../../src/lib/LibUnderlyingNamingRollout.sol";

/// @title UnderlyingNamingRolloutTest
/// @notice The underlying-naming rollout on every deployment network. Per
/// network, at its pinned pre-backfill block, the rollout is authored,
/// verified and executed on a fork with the candidate implementations
/// planted, executed from a roleless key, and every production vault and
/// wrapper is checked renamed. The refusal tests cover each pre-flight check.
contract UnderlyingNamingRolloutTest is UnderlyingNamingRolloutFixture {
    /// @notice Distinguishes each mint-and-burn round's operator and nonce.
    uint256 internal sMintRound;

    /// @notice The beacon batch is exactly: the wrapper beacon upgrade, the
    /// vault beacon upgrade, then the facet probe on the first production
    /// vault.
    function assertBeaconBatchExact(uint256 chainId, string memory network) internal view {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.beaconBatch(chainId);
        assertEq(targets.length, 3, string.concat(network, ": beacon batch length"));
        assertEq(
            targets[0],
            LibUnderlyingNamingRollout.wrappedTokenVaultBeacon(chainId),
            string.concat(network, ": wrapper beacon")
        );
        assertEq(
            payloads[0],
            abi.encodeCall(
                UpgradeableBeacon.upgradeTo, (LibUnderlyingNamingRollout.WRAPPED_TOKEN_VAULT_IMPLEMENTATION)
            ),
            string.concat(network, ": beacon upgrade 0")
        );
        assertEq(
            targets[1], LibUnderlyingNamingRollout.receiptVaultBeacon(chainId), string.concat(network, ": vault beacon")
        );
        assertEq(
            payloads[1],
            abi.encodeCall(UpgradeableBeacon.upgradeTo, (LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION)),
            string.concat(network, ": beacon upgrade 1")
        );
        assertEq(
            targets[2],
            LibUnderlyingNamingRollout.tokens(chainId)[0].receiptVault,
            string.concat(network, ": probe vault")
        );
        assertEq(
            payloads[2],
            abi.encodeCall(ICorporateActionsV1.completedActionCount, ()),
            string.concat(network, ": probe call")
        );
        for (uint256 callIndex = 0; callIndex < values.length; callIndex++) {
            assertEq(values[callIndex], 0, string.concat(network, ": value"));
        }
    }

    /// @notice The rename batch is exactly one `setUnderlying(underlying,
    /// underlyingName)` per production token of the chain, in table order,
    /// and every row's symbol is `"t" + underlying`.
    function assertRenameBatchExact(uint256 chainId, string memory network) internal pure {
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainId);
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) =
            LibUnderlyingNamingRollout.renameBatch(chainId);
        assertEq(targets.length, chainTokens.length, string.concat(network, ": one call per production token"));
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            string memory ticker = chainTokens[tokenIndex].underlying;
            string memory label = string.concat(network, ": ", ticker);
            TokenConfig memory config = LibProdTokenConfig.configOf(ticker);
            assertEq(config.underlying, ticker, label);
            assertEq(config.symbol, string.concat("t", ticker), label);
            assertEq(targets[tokenIndex], chainTokens[tokenIndex].receiptVault, label);
            assertEq(values[tokenIndex], 0, label);
            (string memory setTicker, string memory setName) = decodeSetUnderlying(payloads[tokenIndex]);
            assertEq(setTicker, ticker, label);
            assertEq(setName, config.underlyingName, label);
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

    function testRenameBatchExactOnEveryDeploymentNetwork() external pure {
        SupportedNetwork[] memory networks =
            LibRainDeploy.declaredNetworkConfigs(LibStoxDeployNetworks.deploymentNetworks());
        for (uint256 i = 0; i < networks.length; i++) {
            assertRenameBatchExact(networks[i].chainId, networks[i].name);
        }
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

    /// @notice Authors, verifies and executes both batches on `network` and
    /// checks the result.
    function assertRollout(string memory network) internal {
        LibTestPreBackfillFork.select(vm, network);
        uint256 chainId = block.chainid;
        address timelock = LibTimelockInvariants.timelockForChainId(chainId);
        TimelockController controller = TimelockController(payable(timelock));
        bytes32 beaconId = LibUnderlyingNamingRollout.beaconOperationId(timelock, chainId);
        bytes32 renameId = LibUnderlyingNamingRollout.renameOperationId(timelock, chainId);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness(network);
        ExecuteUnderlyingNamingHarness execution = new ExecuteUnderlyingNamingHarness(network);

        assertBeaconBatchExact(chainId, network);
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness(network);
        advanceRootLineToBeaconSchedule();
        // Before step 1 the beacon batch refuses, and the rename refuses the
        // line until the beacon record lands.
        vm.expectPartialRevert(ImplementationNotDeployed.selector);
        beacons.callPreflight();
        vm.expectRevert(
            abi.encodeWithSelector(UnexpectedMigrationLine.selector, LibStoxMigrations.ORCHESTRATOR_ADMIN_TO_TIMELOCK)
        );
        rename.callPreflight();
        plantImplementations();
        authorVerifyExecute(address(beacons), beacons.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_BEACONS,
            string.concat(network, ": beacon record")
        );
        completeOwnershipHandover(chainId, rename);
        authorVerifyExecute(address(rename), rename.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.SCHEDULE_UNDERLYING_NAMING_RENAME,
            string.concat(network, ": rename record")
        );

        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        execution.execute();
        assertEq(
            IBeacon(LibUnderlyingNamingRollout.receiptVaultBeacon(chainId)).implementation(),
            LibUnderlyingNamingRollout.RECEIPT_VAULT_IMPLEMENTATION,
            string.concat(network, ": vault beacon upgraded")
        );
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingNotExecuted.selector, renameId));
        execution.callPreflight();
        logRenameExecutionGas(controller, chainId, beaconId);
        execution.execute();
        assertTrue(controller.isOperationDone(renameId), string.concat(network, ": rename executed"));
        rename.callAssertRenamed(chainId);

        vm.expectPartialRevert(NoUnderlyingNamingOperationReady.selector);
        execution.execute();

        authorVerifyExecute(address(execution), execution.callArtifactPath());
        assertEq(
            LibStoxMigrations.head(),
            LibStoxMigrations.EXECUTE_UNDERLYING_NAMING,
            string.concat(network, ": line at the execution")
        );
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

    function testRolloutOnEveryDeploymentNetwork() external {
        string[] memory networks = LibStoxDeployNetworks.deploymentNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            assertRollout(networks[i]);
        }
    }

    /// @notice On Base, before execution: after both batches NVDA reads
    /// `tNVDA` / `NVDAs` / `NVIDIA Corporation (ST0x)`, and the orchestrator
    /// keeps minting and burning NVDA across the beacon upgrade.
    function testBaseNvdaAndOrchestratorAcrossTheRollout() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        uint256 chainId = block.chainid;
        ST0xOrchestrator orchestrator = ST0xOrchestrator(payable(LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE));
        assertTrue(
            IST0xOrchestratorV1(address(orchestrator)).vaultLogicIsExpected(), "lock accepts the beacon set before"
        );

        advanceRootLineToBeaconSchedule();
        plantImplementations();
        ScheduleUnderlyingNamingBeaconsHarness beacons = new ScheduleUnderlyingNamingBeaconsHarness("nvda");
        authorVerifyExecute(address(beacons), beacons.callArtifactPath());
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("nvda");
        completeOwnershipHandover(chainId, rename);
        authorVerifyExecute(address(rename), rename.callArtifactPath());
        // forge-lint: disable-next-line(block-timestamp)
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY);
        ExecuteUnderlyingNaming executor = new ExecuteUnderlyingNaming();
        executor.execute();

        assertTrue(
            IST0xOrchestratorV1(address(orchestrator)).vaultLogicIsExpected(), "lock accepts the beacon set after"
        );
        mintAndBurn(orchestrator, LibTokenInvariants.NVDA_RECEIPT_VAULT);

        // Upgraded but not yet renamed: the initialized metadata stands.
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).symbol(), "tNVDA");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).symbol(), "wtNVDA");

        executor.execute();
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).symbol(), "tNVDA");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_RECEIPT_VAULT).name(), "NVIDIA Corporation (ST0x)");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).symbol(), "NVDAs");
        assertEq(IERC20Metadata(LibTokenInvariants.NVDA_WRAPPED_TOKEN_VAULT).name(), "NVIDIA Corporation (ST0x)");
        mintAndBurn(orchestrator, LibTokenInvariants.NVDA_RECEIPT_VAULT);

        // The live-fork name pins accept exactly this renamed state, for
        // every renamed token.
        TokenInstance[] memory chainTokens = LibUnderlyingNamingRollout.tokens(chainId);
        for (uint256 tokenIndex = 0; tokenIndex < chainTokens.length; tokenIndex++) {
            TokenInstance memory token = chainTokens[tokenIndex];
            TokenConfig memory config = LibProdTokenConfig.configOf(token.underlying);
            string memory vaultName = IERC20Metadata(token.receiptVault).name();
            assertTrue(LibTestTokenMetadata.vaultRenamed(config, vaultName), token.underlying);
            assertTrue(
                LibTestTokenMetadata.consistent(
                    config,
                    vaultName,
                    IERC20Metadata(token.receiptVault).symbol(),
                    IERC20Metadata(token.wrappedTokenVault).name(),
                    IERC20Metadata(token.wrappedTokenVault).symbol()
                ),
                token.underlying
            );
        }
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

    /// @notice Grants `operator` MINT and BURN as the orchestrator's admin,
    /// the timelock once the admin move has landed.
    function grantOperator(ST0xOrchestrator orchestrator, address operator) internal {
        address admin = LibTimelockInvariants.timelockForChainId(block.chainid);
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
        IST0xOrchestratorV1(address(orchestrator))
            .mint(token, operator, amount, MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)}), "");
    }

    /// @notice Until the release is frozen, both schedule scripts refuse in
    /// `run()` and `verify()`, even with the implementations deployed.
    function testSchedulingRefusesUntilTheReleaseIsFrozen() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
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

        executePrefix(beacons.callAuthorBundle(), 1);
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("refusals");
        prepareRename(rename);
        rename.callPreflight();
        executePrefix(rename.callAuthorBundle(), 1);
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        address timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        ExecuteUnderlyingNaming executor = new ExecuteUnderlyingNaming();
        bytes32 executorRole = LibTimelockInvariants.TIMELOCK_EXECUTOR_ROLE;
        vm.prank(timelock);
        TimelockController(payable(timelock)).grantRole(executorRole, address(this));
        vm.expectRevert(abi.encodeWithSelector(UnderlyingNamingExecutorHoldsRole.selector, timelock, address(this)));
        executor.execute();
    }

    /// @notice A ticker that does not match its vault's live symbol refuses.
    function testTickerBindingRefusesAMismatchedVault() external {
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        advanceRootLineToBeaconSchedule();
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("ticker");
        prepareRename(rename);
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
        LibTestPreBackfillFork.select(vm, LibRainDeploy.BASE);
        uint256 chainId = block.chainid;
        ScheduleUnderlyingNamingRenameHarness rename = new ScheduleUnderlyingNamingRenameHarness("renamed");
        executeRollout(rename);
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
