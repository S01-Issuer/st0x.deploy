// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    LibProdAuthoriserClones,
    UnsupportedChainForAuthoriserClone
} from "../../../src/lib/LibProdAuthoriserClones.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";

/// @title LibProdAuthoriserClonesTest
/// @notice Guards the hand-maintained per-chain V4 authoriser clone pins.
/// The clone ADDRESS is non-deterministic (a nonce-based `CloneFactory`
/// clone), so it is `address(0)` until a post-deploy hydrate PR fills the
/// real literal — asserting the placeholder explicitly stops it being
/// silently shipped as a real pin, and fails (prompting a real address
/// assertion) the moment a chain's clone is hydrated. The codehash is
/// deterministic and re-exported from the generated `LibProdDeployV4`.
contract LibProdAuthoriserClonesTest is Test {
    /// The Base clone pin is the deployed V4 authoriser clone (hydrated);
    /// guards the literal against accidental drift.
    function testBaseClonePinned() external pure {
        assertEq(
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE,
            address(0x315b16faa6eE413faBCa877d3851B3818369f0cD),
            "Base clone pin drifted from the deployed clone"
        );
    }

    /// The Ethereum clone pin is still a placeholder. Replace this guard with
    /// a real address assertion when Ethereum's bootstrap clone is hydrated.
    function testEthereumClonePlaceholder() external pure {
        assertEq(
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            address(0),
            "Ethereum clone hydrated: replace this placeholder guard with a real address assertion"
        );
    }

    /// The shared codehash is re-exported verbatim from the generated pin, so
    /// every chain's clone is validated against one deterministic value.
    function testCodehashReexportsGeneratedPin() external pure {
        assertEq(
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            LibProdDeployV4.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            "clone codehash re-export drifted from the generated pin"
        );
    }

    /// The chain-id selector returns each chain's own pin.
    function testCloneForChainIdSelectsPerChain() external pure {
        assertEq(
            LibProdAuthoriserClones.cloneForChainId(LibProdAuthoriserClones.BASE_CHAIN_ID),
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_BASE,
            "Base chain id did not select the Base clone"
        );
        assertEq(
            LibProdAuthoriserClones.cloneForChainId(LibProdAuthoriserClones.ETHEREUM_CHAIN_ID),
            LibProdAuthoriserClones.STOX_PROD_AUTHORISER_V4_CLONE_ETHEREUM,
            "Ethereum chain id did not select the Ethereum clone"
        );
    }

    /// The selector reverts for an unsupported chain rather than falling back
    /// to another chain's pin — reading the wrong chain's clone is the exact
    /// failure it exists to prevent.
    function testCloneForChainIdRevertsUnsupported() external {
        uint256 unsupported = 137; // Polygon: no clone pin defined.
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForAuthoriserClone.selector, unsupported));
        // Call across an external boundary so `expectRevert` sees the revert
        // one call depth down (the selector is an internal library function).
        this.cloneForChainId(unsupported);
    }

    /// @notice External wrapper for `cloneForChainId` so `vm.expectRevert` can
    /// observe the revert at a lower call depth.
    function cloneForChainId(uint256 chainId) external pure returns (address clone) {
        clone = LibProdAuthoriserClones.cloneForChainId(chainId);
    }
}
