// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Safe} from "safe-global-safe-smart-account-1.4.1-3/contracts/Safe.sol";

import {ExpectedGrantMissing, LibAuthoriserInvariants} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibInvariants} from "../../../src/lib/LibInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../../src/lib/LibTokenInvariants.sol";
import {LibLocalProdState} from "../../lib/LibLocalProdState.sol";

/// @title LibInvariantsTest
/// @notice The composed production-state bundles pass against each chain's
/// production state built locally.
contract LibInvariantsTest is Test {
    /// @notice Base's bundle passes for Base's Safe with its owners in
    /// `expectedOwners()` order.
    function testAssertAllPassesOnLocalBase() external {
        LibLocalProdState.build(vm, LibSafeInvariants.BASE_CHAIN_ID);
        LibInvariants.assertAll(Safe(payable(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE)));
    }

    /// @notice On 0G the multichain bundle checks 0G's token table and 0G's
    /// whole US map, the orchestrator's pairs included: an authoriser that
    /// holds it passes, and one without the orchestrator's `DEPOSIT` is
    /// refused.
    function testAssertProductionStateOnZerogRequiresTheOrchestrator() external {
        uint256 id = LibSafeInvariants.ZEROG_CHAIN_ID;
        vm.chainId(id);
        LibLocalProdState.safe(vm, id, LibSafeInvariants.expectedOwners());
        LibLocalProdState.timelock(vm, id);
        LibLocalProdState.beacons(vm, id);
        LibLocalProdState.authorisers(vm, id);
        LibLocalProdState.tokens(vm, id);
        TokenInstance[] memory tokens = LibTokenInvariants.productionTokensForChainId(id);
        address authoriser = LibAuthoriserInvariants.authoriserForChainId(id);
        LibInvariants.assertProductionState(tokens, authoriser);

        bytes32 deposit = keccak256("DEPOSIT");
        address orchestrator = LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR;
        vm.mockCall(authoriser, abi.encodeCall(IAccessControl.hasRole, (deposit, orchestrator)), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(ExpectedGrantMissing.selector, authoriser, deposit, orchestrator));
        this.assertProductionState(tokens, authoriser);
    }

    function assertProductionState(TokenInstance[] memory tokens, address authoriser) external view {
        LibInvariants.assertProductionState(tokens, authoriser);
    }

    /// @notice On every chain the multichain bundle passes for that chain's
    /// token table and US authoriser.
    function testAssertProductionStatePassesOnEveryChain() external {
        uint256[] memory chainIds = LibLocalProdState.chainIds();
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 snapshot = vm.snapshotState();
            LibLocalProdState.build(vm, chainIds[i]);
            LibInvariants.assertProductionState(
                LibTokenInvariants.productionTokensForChainId(chainIds[i]),
                LibAuthoriserInvariants.authoriserForChainId(chainIds[i])
            );
            vm.revertToState(snapshot);
        }
    }
}
