// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {
    LibLvmhAuthoriserInvariants,
    LvmhAuthoriserNotReady,
    LvmhExpectedGrantMissing,
    LvmhForbiddenGrant,
    UnsupportedChainForLvmhAuthoriser
} from "../../../src/lib/LibLvmhAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {
    LibTokenInvariants,
    TokenInstance,
    ReceiptVaultAuthoriserMismatch
} from "../../../src/lib/LibTokenInvariants.sol";

/// @dev Minimal `hasRole` oracle so the invariant can be driven without a fork.
contract RoleOracle {
    mapping(bytes32 => mapping(address => bool)) public hasRole;

    function set(bytes32 role, address account, bool held) external {
        hasRole[role][account] = held;
    }
}

/// @title LibLvmhAuthoriserInvariantsTest
/// @notice Fork-free coverage of the tMC role map: its exact shape, the
/// exclusivity checks, and the unset-pin behaviour every consumer relies on.
contract LibLvmhAuthoriserInvariantsTest is Test {
    address constant SAFE = address(0x5AFE);
    address constant TIMELOCK = address(0x71AE);

    RoleOracle internal oracle;

    function setUp() external {
        oracle = new RoleOracle();
        RoleGrant[] memory grants = LibLvmhAuthoriserInvariants.expectedGrants(SAFE, TIMELOCK);
        for (uint256 i = 0; i < grants.length; i++) {
            oracle.set(grants[i].role, grants[i].grantee, true);
        }
    }

    function externalAssert(address authoriser) external view {
        LibLvmhAuthoriserInvariants.assertExpectedGrants(authoriser, SAFE, TIMELOCK);
    }

    /// @notice The map is exactly: seven `_ADMIN` on the admin holder, Safe
    /// D/W/C, minter D/W, 3d0c CERTIFY — and no DEPOSIT/WITHDRAW for 3d0c or
    /// the orchestrator.
    function testMapShape() external pure {
        RoleGrant[] memory g = LibLvmhAuthoriserInvariants.expectedGrants(SAFE, TIMELOCK);
        assertEq(g.length, 13);
        bytes32[7] memory admins = LibLvmhAuthoriserInvariants.adminRoles();
        for (uint256 i = 0; i < 7; i++) {
            assertEq(g[i].role, admins[i]);
            assertEq(g[i].grantee, TIMELOCK);
        }
        assertEq(g[7].role, keccak256("DEPOSIT"));
        assertEq(g[7].grantee, SAFE);
        assertEq(g[8].role, keccak256("WITHDRAW"));
        assertEq(g[8].grantee, SAFE);
        assertEq(g[9].role, keccak256("CERTIFY"));
        assertEq(g[9].grantee, SAFE);
        assertEq(g[10].role, keccak256("DEPOSIT"));
        assertEq(g[10].grantee, 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C);
        assertEq(g[11].role, keccak256("WITHDRAW"));
        assertEq(g[11].grantee, 0x0958d9E94D9D4139280947ACd86D4a50F13bfA8C);
        assertEq(g[12].role, keccak256("CERTIFY"));
        assertEq(g[12].grantee, LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        for (uint256 i = 0; i < g.length; i++) {
            if (g[i].role == keccak256("DEPOSIT") || g[i].role == keccak256("WITHDRAW")) {
                assertTrue(g[i].grantee != LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, "3d0c mints tMC");
                assertTrue(g[i].grantee != LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR, "orchestrator mints tMC");
            }
        }
    }

    /// @notice Each chain's map uses that chain's Safe and governance timelock.
    function testMapPerChainUsesTimelockAsAdmin() external pure {
        uint256[5] memory chains = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 c = 0; c < chains.length; c++) {
            RoleGrant[] memory g = LibLvmhAuthoriserInvariants.expectedGrantsForChainId(chains[c]);
            for (uint256 i = 0; i < 7; i++) {
                assertEq(g[i].grantee, LibTimelockInvariants.timelockForChainId(chains[c]));
            }
            assertEq(g[7].grantee, LibSafeInvariants.safeForChainId(chains[c]));
        }
    }

    function testExactMapPasses() external view {
        this.externalAssert(address(oracle));
    }

    function testRejectsServiceSignerDeposit() external {
        oracle.set(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhForbiddenGrant.selector,
                address(oracle),
                keccak256("DEPOSIT"),
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsServiceSignerWithdraw() external {
        oracle.set(keccak256("WITHDRAW"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhForbiddenGrant.selector,
                address(oracle),
                keccak256("WITHDRAW"),
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsOrchestratorDeposit() external {
        oracle.set(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhForbiddenGrant.selector,
                address(oracle),
                keccak256("DEPOSIT"),
                LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsOrchestratorWithdraw() external {
        oracle.set(keccak256("WITHDRAW"), LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhForbiddenGrant.selector,
                address(oracle),
                keccak256("WITHDRAW"),
                LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR
            )
        );
        this.externalAssert(address(oracle));
    }

    /// @notice The Safe keeping any `_ADMIN` breaks exclusive timelock holding.
    function testRejectsSafeRetainingAnAdmin() external {
        oracle.set(keccak256("DEPOSIT_ADMIN"), SAFE, true);
        vm.expectRevert(
            abi.encodeWithSelector(LvmhForbiddenGrant.selector, address(oracle), keccak256("DEPOSIT_ADMIN"), SAFE)
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsDefaultAdminHolder() external {
        oracle.set(bytes32(0), TIMELOCK, true);
        vm.expectRevert(abi.encodeWithSelector(LvmhForbiddenGrant.selector, address(oracle), bytes32(0), TIMELOCK));
        this.externalAssert(address(oracle));
    }

    function testRejectsMinterCertify() external {
        oracle.set(keccak256("CERTIFY"), LibLvmhAuthoriserInvariants.GRANTEE_LVMH_MINTER, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhForbiddenGrant.selector,
                address(oracle),
                keccak256("CERTIFY"),
                LibLvmhAuthoriserInvariants.GRANTEE_LVMH_MINTER
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsMissingMinterDeposit() external {
        oracle.set(keccak256("DEPOSIT"), LibLvmhAuthoriserInvariants.GRANTEE_LVMH_MINTER, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhExpectedGrantMissing.selector,
                address(oracle),
                keccak256("DEPOSIT"),
                LibLvmhAuthoriserInvariants.GRANTEE_LVMH_MINTER
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsMissingServiceCertify() external {
        oracle.set(keccak256("CERTIFY"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                LvmhExpectedGrantMissing.selector,
                address(oracle),
                keccak256("CERTIFY"),
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        this.externalAssert(address(oracle));
    }

    /// @notice Every pin is unset until its broadcast lands, and an unset pin
    /// is never "ready" — the copy script refuses tMC on it.
    function testPinsUnsetAndNotReady() external {
        uint256[5] memory chains = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 c = 0; c < chains.length; c++) {
            assertEq(LibLvmhAuthoriserInvariants.lvmhAuthoriserForChainId(chains[c]), address(0));
        }
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(LvmhAuthoriserNotReady.selector, address(0)));
        this.externalActiveChain();
    }

    function testUnknownChainReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForLvmhAuthoriser.selector, 123456));
        this.externalPin(123456);
    }

    function externalActiveChain() external view returns (address) {
        return LibLvmhAuthoriserInvariants.activeChainLvmhAuthoriser();
    }

    function externalPin(uint256 chainId) external pure returns (address) {
        return LibLvmhAuthoriserInvariants.lvmhAuthoriserForChainId(chainId);
    }

    function testIsLvmh() external pure {
        assertTrue(LibLvmhAuthoriserInvariants.isLvmh("MC"));
        assertFalse(LibLvmhAuthoriserInvariants.isLvmh("MC.PA"));
        assertFalse(LibLvmhAuthoriserInvariants.isLvmh("lvmh"));
    }

    function externalUniformAuthoriser(TokenInstance[] memory tokens, address expected) external view {
        LibTokenInvariants.assertUniformAuthoriser(tokens, expected);
    }

    /// @notice The uniform-authoriser invariant expects a tMC row on the
    /// chain's dedicated tMC authoriser and every other row on the shared
    /// one — so a tMC vault wired to the SHARED authoriser is drift.
    function testUniformAuthoriserRoutesLvmhToItsOwnAuthoriser() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        address shared = address(0x5AA4ED);
        address vaultA = address(0xA1);
        address vaultL = address(0xA2);
        TokenInstance[] memory tokens = new TokenInstance[](2);
        tokens[0] = TokenInstance("SNES", address(0), vaultA, address(0));
        tokens[1] = TokenInstance("MC", address(0), vaultL, address(0));
        vm.mockCall(vaultA, abi.encodeWithSignature("authorizer()"), abi.encode(shared));
        vm.mockCall(vaultL, abi.encodeWithSignature("authorizer()"), abi.encode(shared));
        address want = LibLvmhAuthoriserInvariants.lvmhAuthoriserForChainId(block.chainid);
        vm.expectRevert(abi.encodeWithSelector(ReceiptVaultAuthoriserMismatch.selector, vaultL, want, shared));
        this.externalUniformAuthoriser(tokens, shared);

        vm.mockCall(vaultL, abi.encodeWithSignature("authorizer()"), abi.encode(want));
        this.externalUniformAuthoriser(tokens, shared);
    }
}
