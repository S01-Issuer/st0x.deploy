// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {
    AuthoriserNotReady,
    AuthoriserNotWired,
    DeployMissingTokens,
    DeployerNotDeployed,
    DeploymentEventMissing,
    NoMissingTokens,
    OwnershipHandoffFailed,
    TokenTableMisaligned,
    TokenTableTooShort,
    UnsupportedTargetChain
} from "../../script/20260807-deploy-missing-tokens.s.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {DeployMissingTokensHarness} from "./DeployMissingTokensHarness.sol";

/// @title DeployMissingTokensTest
/// @notice Coverage for the unified token-copy script. The selection joins
/// two in-code tables (Base vs the target chain), so it is PURE — testable
/// without a fork — and the deploy pre-flight reuses the gate chain the
/// per-chain prod pins already exercise against live state.
contract DeployMissingTokensTest is Test {
    /// @dev The 0.1.1 authoriser implementation the production V4 authoriser
    /// clones. Written out rather than imported so this test states the
    /// implementation it expects the clone to proxy, independently of the
    /// generated pointers it would otherwise be checking against themselves.
    address constant AUTHORISER_IMPL_0_1_1 = address(0x2EA0d35d0B1F57C42e6130f298930228bCbFDe9b);

    /// @dev Arbitrary non-empty runtime, for standing something at an address
    /// that the code-presence checks accept and the codehash checks reject.
    bytes constant STUB_CODE = hex"600160005260206000f3";

    address constant DEPLOYER = address(0xDEB01);
    address constant RECEIPT_VAULT = address(0x1A17);
    address constant WRAPPED = address(0x1A18);
    address constant AUTHORISER = address(0xA077);
    address constant SAFE = address(0x5AFE);
    address constant STRAY = address(0xDEADBEEF);

    DeployMissingTokens internal script;
    DeployMissingTokensHarness internal harness;

    function setUp() external {
        script = new DeployMissingTokens();
        harness = new DeployMissingTokensHarness();
    }

    /// @notice A chain whose table already carries every Base underlying has
    /// nothing to copy. This is the guard that stops a re-dispatch minting
    /// duplicates of tokens that already landed.
    function testSelectionRevertsWhenTargetMatchesBase() external {
        vm.expectRevert(NoMissingTokens.selector);
        harness.selectMissing(
            LibProdTokenConfig.productionTokenConfigs(),
            LibTokenInvariants.productionTokensBase(),
            LibTokenInvariants.productionTokensBase()
        );
    }

    /// @notice A target chain missing a Base token selects exactly that token,
    /// by `underlying`, and nothing else. Built by dropping one row from a
    /// copy of Base rather than by hardcoding a ticker, so the test does not
    /// go stale as the token set grows.
    function testSelectionPicksTheTokensTheTargetLacks() external view {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        assertGt(base.length, 1, "need at least two Base tokens to drop one");

        uint256 dropped = base.length - 1;
        TokenInstance[] memory target = new TokenInstance[](base.length - 1);
        for (uint256 i = 0; i < dropped; i++) {
            target[i] = base[i];
        }

        TokenConfig[] memory missing = harness.selectMissing(LibProdTokenConfig.productionTokenConfigs(), base, target);
        assertEq(missing.length, 1, "expected exactly the dropped token");
        assertEq(missing[0].underlying, base[dropped].underlying, "selected the wrong token");
    }

    /// @notice An empty target table selects the whole Base set — the
    /// bootstrap case for a brand new chain.
    function testSelectionOnEmptyTargetCopiesEverything() external view {
        TokenConfig[] memory missing = harness.selectMissing(
            LibProdTokenConfig.productionTokenConfigs(),
            LibTokenInvariants.productionTokensBase(),
            new TokenInstance[](0)
        );
        assertEq(missing.length, LibTokenInvariants.productionTokensBase().length, "expected the full Base set");
    }

    /// @notice A config table running AHEAD of Base is a normal state, not a
    /// drift: rows are authored when a ticker is chosen and Base is pinned
    /// when it is deployed, so the config table leads until the Base deploy
    /// lands. The trailing rows Base does not carry are inert — selection
    /// still reads only the Base rows, and only the ones the target lacks.
    function testSelectionToleratesAConfigTableAheadOfBase() external view {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();

        TokenConfig[] memory ahead = new TokenConfig[](configs.length + 2);
        for (uint256 i = 0; i < configs.length; i++) {
            ahead[i] = configs[i];
        }
        ahead[configs.length] = TokenConfig("AAAA", "Ahead Of Base One ST0x", "tAAAA");
        ahead[configs.length + 1] = TokenConfig("BBBB", "Ahead Of Base Two ST0x", "tBBBB");

        TokenConfig[] memory missing = harness.selectMissing(ahead, base, new TokenInstance[](0));
        assertEq(missing.length, base.length, "the un-deployed rows must not be selected");
        assertEq(missing[base.length - 1].underlying, base[base.length - 1].underlying, "selected past the Base table");
    }

    /// @notice A config table SHORTER than Base is the genuine error: a
    /// deployed Base row would have no name/symbol to deploy under.
    function testSelectionRevertsWhenConfigTableIsShorterThanBase() external {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();

        TokenConfig[] memory short = new TokenConfig[](base.length - 1);
        for (uint256 i = 0; i < short.length; i++) {
            short[i] = configs[i];
        }

        vm.expectRevert(abi.encodeWithSelector(TokenTableTooShort.selector, base.length - 1, base.length));
        harness.selectMissing(short, base, new TokenInstance[](0));
    }

    /// @notice Every name/symbol deployed is read from the config row at the
    /// Base row's index, so a row-for-row key mismatch must abort rather than
    /// deploy a token under the wrong underlying's strings. Drifted by
    /// swapping two adjacent config rows, which leaves both tables the same
    /// length — the failure the length check cannot see.
    function testSelectionRevertsWhenConfigRowsDriftFromBase() external {
        TokenInstance[] memory base = LibTokenInvariants.productionTokensBase();
        TokenConfig[] memory configs = LibProdTokenConfig.productionTokenConfigs();
        assertGt(base.length, 1, "need at least two rows to swap");

        TokenConfig[] memory drifted = new TokenConfig[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            drifted[i] = configs[i];
        }
        (drifted[0], drifted[1]) = (drifted[1], drifted[0]);

        vm.expectRevert(
            abi.encodeWithSelector(TokenTableMisaligned.selector, 0, drifted[0].underlying, base[0].underlying)
        );
        harness.selectMissing(drifted, base, new TokenInstance[](0));
    }

    /// @notice Base is the SOURCE, so dispatching against it is a
    /// wrong-network dispatch rather than a no-op.
    function testTargetTokensRejectsBase() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, LibSafeInvariants.BASE_CHAIN_ID));
        harness.targetTokens();
    }

    /// @notice An unknown chain is rejected rather than silently resolving to
    /// an empty table, which would otherwise read as "copy everything".
    function testTargetTokensRejectsUnknownChain() external {
        vm.chainId(123456);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, 123456));
        harness.targetTokens();
    }

    /// @notice Each supported target chain resolves to its own table, keyed
    /// by chain id.
    function testTargetTokensResolvesPerChain() external {
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        TokenInstance[] memory ethereum = harness.targetTokens();
        assertEq(ethereum.length, LibTokenInvariants.productionTokensEthereum().length, "Ethereum table mismatch");

        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        TokenInstance[] memory hyperevm = harness.targetTokens();
        assertEq(hyperevm.length, LibTokenInvariants.productionTokensHyperEvm().length, "HyperEVM table mismatch");
    }

    /// @notice `run()` reverts `DeployerNotDeployed` when the 0.1.1 core has
    /// not been broadcast to the active chain — the pre-bootstrap state, and
    /// the first guard in the pre-flight chain.
    function testRunRevertsWhenCoreNotDeployed() external {
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1)
        );
        script.run();
    }

    /// @notice The core gate is three checks, not one: with the unified
    /// deployer present the next two are still enforced, each naming the
    /// deployer it found missing. Without this, a partial 0.1.1 bootstrap —
    /// the deployer landed, a beacon-set deployer did not — passes the gate
    /// and faults later, inside the broadcast.
    function testRunChecksEveryDeployerInTheCore() external {
        vm.etch(LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1, STUB_CODE);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployerNotDeployed.selector,
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1
            )
        );
        script.run();

        vm.etch(LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER_0_1_1, STUB_CODE);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployerNotDeployed.selector, LibProdDeployV4.STOX_WRAPPED_TOKEN_VAULT_BEACON_SET_DEPLOYER_0_1_1
            )
        );
        script.run();
    }

    /// @notice The chain's authoriser pin is rejected when nothing is deployed
    /// at it. Base and unknown chains never reach the readiness check at all —
    /// they have no authoriser to resolve, so they are a dispatch error.
    function testAuthoriserReadyRejectsChainsWithNoPin() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, LibSafeInvariants.BASE_CHAIN_ID));
        harness.assertAuthoriserReady();

        vm.chainId(123456);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedTargetChain.selector, 123456));
        harness.assertAuthoriserReady();
    }

    /// @notice An unpinned or undeployed authoriser is caught before any
    /// broadcast — dispatching ahead of the authoriser clone landing on the
    /// target chain would otherwise deploy tokens with nothing to wire them to.
    function testAuthoriserNotReadyWhenNothingIsDeployedAtThePin() external {
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        vm.expectRevert(
            abi.encodeWithSelector(AuthoriserNotReady.selector, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM)
        );
        harness.assertAuthoriserReady();
    }

    /// @notice Code at the pin is not enough: a contract that is not the
    /// audited clone is rejected on codehash. This is the check that makes the
    /// pin mean "the V4 authoriser" rather than "some contract".
    function testAuthoriserNotReadyWhenTheCodehashIsWrong() external {
        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        vm.etch(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM, STUB_CODE);
        vm.expectRevert(
            abi.encodeWithSelector(AuthoriserNotReady.selector, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM)
        );
        harness.assertAuthoriserReady();
    }

    /// @notice The audited clone passes on every supported target chain, so
    /// the rejections above are not vacuous.
    ///
    /// The runtime is rebuilt here rather than fetched, which also pins what
    /// the codehash MEANS: `STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH` is the
    /// EIP-1167 runtime embedding the 0.1.1 authoriser implementation, and
    /// nothing else asserted that derivation — the invariants lib states it in
    /// prose and compares hashes. A clone of a different implementation would
    /// fail here rather than silently satisfy every codehash check in the repo.
    function testAuthoriserReadyAcceptsTheAuditedClone() external {
        bytes memory cloneRuntime =
            abi.encodePacked(hex"363d3d373d3d3d363d73", AUTHORISER_IMPL_0_1_1, hex"5af43d82803e903d91602b57fd5bf3");
        assertEq(
            keccak256(cloneRuntime),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            "the pinned codehash is not an EIP-1167 clone of the 0.1.1 authoriser"
        );

        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        vm.etch(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM, cloneRuntime);
        assertEq(
            harness.assertAuthoriserReady(),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            "Ethereum authoriser rejected"
        );

        vm.chainId(LibSafeInvariants.HYPEREVM_CHAIN_ID);
        vm.etch(LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM, cloneRuntime);
        assertEq(
            harness.assertAuthoriserReady(),
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_HYPEREVM,
            "HyperEVM authoriser rejected"
        );
    }

    /// @notice A deploy call that emitted no `Deployment` event reverts named,
    /// rather than carrying a zero address into the receipt readback and
    /// faulting as a raw call to an empty account — mid-broadcast, with the
    /// tokens before it already live.
    function testReadDeploymentRevertsWhenTheEventIsMissing() external {
        vm.expectRevert(abi.encodeWithSelector(DeploymentEventMissing.selector, "RKLB"));
        harness.readDeployment(new Vm.Log[](0), DEPLOYER, "RKLB");
    }

    /// @notice A `Deployment` from anything other than the unified deployer is
    /// not this script's deployment. Nothing stops an unrelated contract in
    /// the same transaction emitting the same signature.
    function testReadDeploymentIgnoresOtherEmitters() external {
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _deploymentLog(address(0xBAD), RECEIPT_VAULT, WRAPPED);

        vm.expectRevert(abi.encodeWithSelector(DeploymentEventMissing.selector, "RKLB"));
        harness.readDeployment(logs, DEPLOYER, "RKLB");
    }

    /// @notice Other events from the unified deployer are not deployments
    /// either — the topic is matched, not just the emitter.
    function testReadDeploymentIgnoresOtherEventsFromTheDeployer() external {
        Vm.Log[] memory logs = new Vm.Log[](1);
        logs[0] = _deploymentLog(DEPLOYER, RECEIPT_VAULT, WRAPPED);
        logs[0].topics[0] = keccak256("SomethingElse(address,address,address)");

        vm.expectRevert(abi.encodeWithSelector(DeploymentEventMissing.selector, "RKLB"));
        harness.readDeployment(logs, DEPLOYER, "RKLB");
    }

    /// @notice The matching event's pair is decoded, picked out from among
    /// logs that do not match — so the rejections above are not vacuous.
    function testReadDeploymentDecodesTheDeployedPair() external view {
        Vm.Log[] memory logs = new Vm.Log[](3);
        logs[0] = _deploymentLog(address(0xBAD), address(0xDEAD), address(0xDEAD));
        logs[1] = _deploymentLog(DEPLOYER, RECEIPT_VAULT, WRAPPED);
        logs[2] = _deploymentLog(DEPLOYER, RECEIPT_VAULT, WRAPPED);
        logs[2].topics[0] = keccak256("SomethingElse(address,address,address)");

        (address receiptVault, address wrapped) = harness.readDeployment(logs, DEPLOYER, "RKLB");
        assertEq(receiptVault, RECEIPT_VAULT, "wrong receipt vault decoded");
        assertEq(wrapped, WRAPPED, "wrong wrapped vault decoded");
    }

    /// @notice Ownership that did not land on the Safe is caught: otherwise
    /// the broadcast finishes "successfully" leaving a production vault owned
    /// by the CI deploy key.
    function testHandoffCaughtWhenOwnershipDidNotLand() external {
        vm.mockCall(RECEIPT_VAULT, abi.encodeWithSignature("authorizer()"), abi.encode(AUTHORISER));
        vm.mockCall(RECEIPT_VAULT, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(STRAY));
        vm.expectRevert(abi.encodeWithSelector(OwnershipHandoffFailed.selector, RECEIPT_VAULT, SAFE, STRAY));
        script.assertHandoffLanded(RECEIPT_VAULT, AUTHORISER, SAFE);
    }

    /// @notice A vault left on the wrong authoriser is caught — until
    /// `setAuthorizer` lands, every operation on the vault reverts.
    function testHandoffCaughtWhenAuthoriserNotWired() external {
        vm.mockCall(RECEIPT_VAULT, abi.encodeWithSignature("authorizer()"), abi.encode(STRAY));
        vm.mockCall(RECEIPT_VAULT, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(SAFE));
        vm.expectRevert(abi.encodeWithSelector(AuthoriserNotWired.selector, RECEIPT_VAULT, AUTHORISER, STRAY));
        script.assertHandoffLanded(RECEIPT_VAULT, AUTHORISER, SAFE);
    }

    /// @notice Both landed passes, so the two above are not vacuous.
    function testHandoffPassesWhenBothLanded() external {
        vm.mockCall(RECEIPT_VAULT, abi.encodeWithSignature("authorizer()"), abi.encode(AUTHORISER));
        vm.mockCall(RECEIPT_VAULT, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(SAFE));
        script.assertHandoffLanded(RECEIPT_VAULT, AUTHORISER, SAFE);
    }

    /// @notice A `Deployment(sender, asset, wrapper)` log as the unified
    /// deployer emits it.
    /// @param emitter The contract the log is attributed to.
    /// @param receiptVault The deployed receipt vault.
    /// @param wrapped The deployed wrapped token vault.
    /// @return log The synthesised log.
    function _deploymentLog(address emitter, address receiptVault, address wrapped)
        internal
        pure
        returns (Vm.Log memory log)
    {
        log.topics = new bytes32[](1);
        log.topics[0] = keccak256("Deployment(address,address,address)");
        log.data = abi.encode(address(0x5E11E4), receiptVault, wrapped);
        log.emitter = emitter;
    }
}
