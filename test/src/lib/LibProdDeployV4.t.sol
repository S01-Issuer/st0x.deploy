// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {ERC1167_PREFIX, ERC1167_SUFFIX} from "rain-extrospection-0.1.16/src/lib/LibExtrospectERC1167Proxy.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";

/// @title LibProdDeployV4Test
/// @notice The `LibProdDeployV4` constants no deploy suite declares. Every
/// suite's address, codehash and code is checked by `StoxDeploySnapshotTest`.
contract LibProdDeployV4Test is Test {
    /// The beacon initial owner is rainlang.eth and unchanged across versions.
    function testBeaconInitialOwner() external pure {
        assertEq(LibProdDeployV4.BEACON_INITIAL_OWNER, address(0x8E4bdeec7CEB9570D440676345dA1dCe10329f5b));
    }

    /// The V4 authoriser clone pin. The address was hydrated from the
    /// 2026-07 broadcast of `20260619-deploy-v4-authoriser-clone.s.sol` on
    /// Base (see the `NewClone` event in the broadcast receipt); asserting
    /// the literal here means an accidental edit to the generator's
    /// hardcoded value fails a test rather than silently re-routing every
    /// consumer of the pin. The live-chain codehash cross-check runs in
    /// `StoxProdV4PostSwapTest.testBasePostSwapAuthoriserState`.
    function testAuthoriserV4ClonePin() external pure {
        assertEq(
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE,
            address(0x315b16faa6eE413faBCa877d3851B3818369f0cD),
            "clone address pin drifted from the deployed literal"
        );
        // The clone CODEHASH is deterministic from the pinned V4 impl (the
        // EIP-1167 runtime embeds the impl address). Re-derive it and assert
        // the pinned literal matches, so an impl-address change can't leave
        // it stale.
        assertEq(
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            keccak256(
                abi.encodePacked(
                    ERC1167_PREFIX,
                    LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
                    ERC1167_SUFFIX
                )
            ),
            "clone codehash literal drifted from the EIP-1167(impl) derivation"
        );
    }
}
