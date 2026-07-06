// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {LibChainPrincipals, ChainPrincipals, UnknownPrincipalsNetwork} from "../../../src/lib/LibChainPrincipals.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../../src/lib/LibStoxDeployNetworks.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";

/// @title LibChainPrincipalsTest
/// @notice Pins the per-chain principal tables and the invariants that make
/// them safe to consume: Base's principals equal the live pinned constants,
/// Ethereum's are cleanly pending (all-or-nothing), lookups for undefined
/// networks revert, and the chain-parametric grant map reproduces the pinned
/// Base map exactly when fed Base's principals.
contract LibChainPrincipalsTest is Test {
    /// Wrapper so the internal-library revert can be asserted with
    /// `vm.expectRevert` (an internal pure call cannot revert-match inline).
    function forNetworkExternal(string memory network) external pure returns (ChainPrincipals memory) {
        return LibChainPrincipals.forNetwork(network);
    }

    /// Base's principals are the live pinned production addresses.
    function testBasePrincipals() external pure {
        ChainPrincipals memory principals = LibChainPrincipals.base();
        assertEq(principals.network, LibRainDeploy.BASE, "network");
        assertEq(principals.tokenOwnerSafe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "tokenOwnerSafe");
        assertEq(principals.serviceSigner, LibAuthoriserInvariants.GRANTEE_SERVICE_1C66, "serviceSigner");
    }

    /// Ethereum's principals are concrete pins identical to Base's: the
    /// matched-address token-owner Safe and the shared service signer. Only
    /// the `network` field differs. (The Safe's on-chain existence is a
    /// bootstrap step, not represented in the principals.)
    function testEthereumPrincipalsMatchBase() external pure {
        ChainPrincipals memory eth = LibChainPrincipals.ethereum();
        ChainPrincipals memory base = LibChainPrincipals.base();
        assertEq(eth.network, LibStoxDeployNetworks.ETHEREUM, "network");
        assertEq(eth.tokenOwnerSafe, base.tokenOwnerSafe, "Ethereum Safe == Base Safe (matched address)");
        assertEq(eth.tokenOwnerSafe, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE, "Safe == pinned token-owner Safe");
        assertEq(eth.serviceSigner, base.serviceSigner, "service signer shared with Base");
    }

    /// Every supported deploy network has a principals entry — a network
    /// added to `LibStoxDeployNetworks.supportedNetworks()` without a
    /// principals table fails here instead of at first use.
    function testEveryDeployNetworkHasPrincipals() external pure {
        string[] memory networks = LibStoxDeployNetworks.supportedNetworks();
        for (uint256 i = 0; i < networks.length; i++) {
            ChainPrincipals memory principals = LibChainPrincipals.forNetwork(networks[i]);
            assertEq(principals.network, networks[i], "principals must echo their network");
        }
    }

    /// Lookup for an undefined network reverts with the typed error — it
    /// must never zero-fill, which would be indistinguishable from a
    /// pending-bootstrap chain.
    function testUnknownNetworkReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnknownPrincipalsNetwork.selector, "flare"));
        this.forNetworkExternal("flare");
    }

    /// The chain-parametric grant map with Base's principals reproduces the
    /// pinned Base map pair-for-pair, so the parametric refactor cannot have
    /// changed what Base-side pins and scripts assert.
    function testParametricGrantsMatchPinnedBaseGrants() external pure {
        RoleGrant[] memory pinned = LibAuthoriserInvariants.expectedGrants();
        RoleGrant[] memory parametric = LibAuthoriserInvariants.expectedGrants(LibChainPrincipals.base());
        assertEq(pinned.length, parametric.length, "length");
        for (uint256 i = 0; i < pinned.length; i++) {
            assertEq(pinned[i].role, parametric[i].role, "role");
            assertEq(pinned[i].grantee, parametric[i].grantee, "grantee");
        }
    }

    /// The grant structure is exactly 11 pairs: 5 `_ADMIN` + 3 service
    /// action + 3 Safe action. Scripts slice this array by index (the
    /// grants-mirror bundles), so a reshape must fail loudly here too.
    function testGrantStructureShape() external pure {
        RoleGrant[] memory grants = LibAuthoriserInvariants.expectedGrants(LibChainPrincipals.base());
        assertEq(grants.length, 11, "grant count");
        for (uint256 i = 0; i < 5; i++) {
            assertEq(grants[i].grantee, LibChainPrincipals.base().tokenOwnerSafe, "_ADMIN roles held by Safe");
        }
        for (uint256 i = 5; i < 8; i++) {
            assertEq(grants[i].grantee, LibChainPrincipals.base().serviceSigner, "service action roles");
        }
        for (uint256 i = 8; i < 11; i++) {
            assertEq(grants[i].grantee, LibChainPrincipals.base().tokenOwnerSafe, "Safe action roles");
        }
    }
}
