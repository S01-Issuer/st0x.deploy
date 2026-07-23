// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeployTokensEthereum,
    DeployerNotDeployed,
    EthereumTokensAlreadyDeployed,
    AuthoriserNotWired,
    OwnershipHandoffFailed
} from "../../script/20260706-deploy-tokens-ethereum.s.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibProdDeployV4} from "../../src/generated/LibProdDeployV4.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";

/// @title DeployTokensEthereumTest
/// @notice Pre-flight coverage for the Ethereum token-deploy script, on the
/// forcing-function pattern (OPERATIONAL_SCRIPTS.md): the happy path cannot
/// complete until every upstream dependency has landed, so the tests prove
/// each gate fires in order — and, critically, prove the gates that SHOULD
/// pass against live Ethereum actually do, on every CI run. `run()` is a
/// single deploy-key broadcast (deploy → setAuthorizer → transferOwnership to
/// the Safe), so there is one entrypoint and one pre-flight chain: core
/// 0.1.1 deployers, in-use beacon ownership, then the clone (setAuthorizer
/// target), then the Safe (handoff target).
contract DeployTokensEthereumTest is Test {
    /// `run()` reverts `DeployerNotDeployed` when the 0.1.1 core has not been
    /// broadcast to the active chain — the unified deployer's pinned address
    /// has no code, so no token can be deployed. (No fork: the deployer is
    /// absent, which is the pre-bootstrap state, and is the first guard in
    /// the pre-flight chain.)
    function testRunRevertsWhenCoreNotDeployed() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        vm.expectRevert(
            abi.encodeWithSelector(DeployerNotDeployed.selector, LibProdDeployV4.STOX_UNIFIED_DEPLOYER_0_1_1)
        );
        script.run();
    }

    /// The guard fires on a hydrated table — the half that matters. A
    /// re-dispatch after a successful deploy has every dependency satisfied,
    /// so nothing else would stop it minting a second full production set.
    function testRunOnceGateFiresOnAHydratedTable() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        TokenInstance[] memory table = LibTokenInvariants.productionTokensEthereum();
        table[7] = TokenInstance("SPYM", address(0), address(0xBEEF), address(0));
        vm.expectRevert(abi.encodeWithSelector(EthereumTokensAlreadyDeployed.selector, address(0xBEEF)));
        script.assertTableVirgin(table);
    }

    /// Each leg trips it independently. A guard reading only `receiptVault`
    /// would miss a table hydrated receipt-first — which is what a broadcast
    /// that failed midway leaves behind.
    function testRunOnceGateInspectsEveryLeg() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        for (uint256 leg = 0; leg < 3; leg++) {
            TokenInstance[] memory table = LibTokenInvariants.productionTokensEthereum();
            address hydrated = address(uint160(0xC0DE + leg));
            table[27] = TokenInstance(
                "TTWO",
                leg == 0 ? hydrated : address(0),
                leg == 1 ? hydrated : address(0),
                leg == 2 ? hydrated : address(0)
            );
            vm.expectRevert(abi.encodeWithSelector(EthereumTokensAlreadyDeployed.selector, hydrated));
            script.assertTableVirgin(table);
        }
    }

    /// It does NOT fire on the shipped placeholders, or the deploy could never
    /// run and the two tests above would be vacuous.
    function testRunOnceGatePassesOnTheShippedTable() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        script.assertTableVirgin(LibTokenInvariants.productionTokensEthereum());
    }

    /// Ownership that did not land on the Safe is caught: otherwise the
    /// broadcast finishes "successfully" leaving a production vault owned by
    /// the CI deploy key.
    function testHandoffCaughtWhenOwnershipDidNotLand() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        address vault = address(0x1A17);
        address safe = address(0x5AFE);
        address auth = address(0xA077);
        address stray = address(0xDEADBEEF);
        vm.mockCall(vault, abi.encodeWithSignature("authorizer()"), abi.encode(auth));
        vm.mockCall(vault, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(stray));
        vm.expectRevert(abi.encodeWithSelector(OwnershipHandoffFailed.selector, vault, safe, stray));
        script.assertHandoffLanded(vault, auth, safe);
    }

    /// A vault left on the wrong authoriser is caught — until setAuthorizer
    /// lands, every operation on the vault reverts.
    function testHandoffCaughtWhenAuthoriserNotWired() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        address vault = address(0x1A17);
        address safe = address(0x5AFE);
        address auth = address(0xA077);
        address wrong = address(0xBAD);
        vm.mockCall(vault, abi.encodeWithSignature("authorizer()"), abi.encode(wrong));
        vm.mockCall(vault, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(safe));
        vm.expectRevert(abi.encodeWithSelector(AuthoriserNotWired.selector, vault, auth, wrong));
        script.assertHandoffLanded(vault, auth, safe);
    }

    /// Both landed passes, so the two above are not vacuous.
    function testHandoffPassesWhenBothLanded() external {
        DeployTokensEthereum script = new DeployTokensEthereum();
        address vault = address(0x1A17);
        address safe = address(0x5AFE);
        address auth = address(0xA077);
        vm.mockCall(vault, abi.encodeWithSignature("authorizer()"), abi.encode(auth));
        vm.mockCall(vault, abi.encodeWithSelector(Ownable.owner.selector), abi.encode(safe));
        script.assertHandoffLanded(vault, auth, safe);
    }

    /// The hydrated clone pin matches LIVE Ethereum: the V4 authoriser
    /// clone (deployed 2026-07-22) is at the pinned address with the shared
    /// EIP-1167 codehash and carries the full grant map parameterised on
    /// ETHEREUM's Safe. With this green the script's `_assertAuthoriserReady` +
    /// grant expectations are proven against real chain state on every CI
    /// run. `run()` itself is not driven here: under `forge test`,
    /// `vm.startBroadcast` cannot emulate the broadcast sender the way
    /// `forge script` does (the same limitation the 20260619 suite
    /// documents), so the end-to-end simulation lives in the
    /// `manual-broadcast` dry-run instead.
    function testEthereumClonePinMatchesLive() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        address clone = LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM;
        assertTrue(clone.code.length > 0, "Ethereum V4 authoriser clone not deployed at pin");
        assertEq(
            clone.codehash, LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH, "Ethereum clone codehash mismatch"
        );

        RoleGrant[] memory grants =
            LibAuthoriserInvariants.expectedGrants(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_ETHEREUM);
        for (uint256 i = 0; i < grants.length; i++) {
            assertTrue(
                IAccessControl(clone).hasRole(grants[i].role, grants[i].grantee),
                "Ethereum clone missing expected grant"
            );
        }
    }
}
