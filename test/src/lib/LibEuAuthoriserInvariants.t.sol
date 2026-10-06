// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibAuthoriserInvariants, RoleGrant} from "../../../src/lib/LibAuthoriserInvariants.sol";
import {
    LibEuAuthoriserInvariants,
    EuAuthoriserNotReady,
    EuExpectedGrantMissing,
    EuForbiddenGrant,
    UnsupportedChainForEuAuthoriser
} from "../../../src/lib/LibEuAuthoriserInvariants.sol";
import {RoleOracle} from "../../concrete/RoleOracle.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../../../src/lib/LibSafeInvariants.sol";
import {
    LibTokenInvariants,
    TokenInstance,
    ReceiptVaultAuthoriserMismatch
} from "../../../src/lib/LibTokenInvariants.sol";

contract LibEuAuthoriserInvariantsTest is Test {
    address constant SAFE = address(0x5AFE);
    address constant TIMELOCK = address(0x71AE);

    RoleOracle internal oracle;

    function setUp() external {
        oracle = new RoleOracle();
        RoleGrant[] memory grants = LibEuAuthoriserInvariants.expectedGrants(SAFE, TIMELOCK);
        for (uint256 i = 0; i < grants.length; i++) {
            oracle.set(grants[i].role, grants[i].grantee, true);
        }
    }

    function externalAssert(address authoriser) external view {
        LibEuAuthoriserInvariants.assertExpectedGrants(authoriser, SAFE, TIMELOCK);
    }

    function testMapShape() external pure {
        RoleGrant[] memory g = LibEuAuthoriserInvariants.expectedGrants(SAFE, TIMELOCK);
        assertEq(g.length, 13);
        bytes32[7] memory admins = LibEuAuthoriserInvariants.adminRoles();
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

    function testExactMapPasses() external view {
        this.externalAssert(address(oracle));
    }

    function testRejectsServiceSignerDeposit() external {
        oracle.set(keccak256("DEPOSIT"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                EuForbiddenGrant.selector,
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
                EuForbiddenGrant.selector,
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
                EuForbiddenGrant.selector,
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
                EuForbiddenGrant.selector,
                address(oracle),
                keccak256("WITHDRAW"),
                LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsOrchestratorCertify() external {
        oracle.set(keccak256("CERTIFY"), LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                EuForbiddenGrant.selector,
                address(oracle),
                keccak256("CERTIFY"),
                LibAuthoriserInvariants.GRANTEE_ORCHESTRATOR
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsRetiredSignerActionRoles() external {
        bytes32[3] memory actions = LibEuAuthoriserInvariants.actionRoles();
        for (uint256 i = 0; i < actions.length; i++) {
            oracle.set(actions[i], LibAuthoriserInvariants.GRANTEE_SERVICE_1C66, true);
            vm.expectRevert(
                abi.encodeWithSelector(
                    EuForbiddenGrant.selector, address(oracle), actions[i], LibAuthoriserInvariants.GRANTEE_SERVICE_1C66
                )
            );
            this.externalAssert(address(oracle));
            oracle.set(actions[i], LibAuthoriserInvariants.GRANTEE_SERVICE_1C66, false);
        }
    }

    function testRejectsSafeRetainingAnAdmin() external {
        oracle.set(keccak256("DEPOSIT_ADMIN"), SAFE, true);
        vm.expectRevert(
            abi.encodeWithSelector(EuForbiddenGrant.selector, address(oracle), keccak256("DEPOSIT_ADMIN"), SAFE)
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsDefaultAdminHolder() external {
        oracle.set(bytes32(0), TIMELOCK, true);
        vm.expectRevert(abi.encodeWithSelector(EuForbiddenGrant.selector, address(oracle), bytes32(0), TIMELOCK));
        this.externalAssert(address(oracle));
    }

    function testRejectsMinterCertify() external {
        oracle.set(keccak256("CERTIFY"), LibEuAuthoriserInvariants.GRANTEE_EU_MINTER, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                EuForbiddenGrant.selector,
                address(oracle),
                keccak256("CERTIFY"),
                LibEuAuthoriserInvariants.GRANTEE_EU_MINTER
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsMissingMinterDeposit() external {
        oracle.set(keccak256("DEPOSIT"), LibEuAuthoriserInvariants.GRANTEE_EU_MINTER, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                EuExpectedGrantMissing.selector,
                address(oracle),
                keccak256("DEPOSIT"),
                LibEuAuthoriserInvariants.GRANTEE_EU_MINTER
            )
        );
        this.externalAssert(address(oracle));
    }

    function testRejectsMissingServiceCertify() external {
        oracle.set(keccak256("CERTIFY"), LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                EuExpectedGrantMissing.selector,
                address(oracle),
                keccak256("CERTIFY"),
                LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C
            )
        );
        this.externalAssert(address(oracle));
    }

    function testPinsUnsetAndNotReady() external {
        uint256[5] memory chains = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 c = 0; c < chains.length; c++) {
            assertEq(LibEuAuthoriserInvariants.euAuthoriserForChainId(chains[c]), address(0));
        }
        vm.chainId(LibSafeInvariants.ETHEREUM_CHAIN_ID);
        vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotReady.selector, address(0)));
        this.externalActiveChain();
    }

    function testAuditedCloneMatchesOnlyTheAuditedProxy() external {
        address clone = address(0xC10E);
        vm.etch(
            clone,
            abi.encodePacked(
                hex"363d3d373d3d3d363d73",
                LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1,
                hex"5af43d82803e903d91602b57fd5bf3"
            )
        );
        this.externalAuditedClone(clone);

        address other = address(0x0DD);
        vm.etch(other, hex"00");
        vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotReady.selector, other));
        this.externalAuditedClone(other);

        address empty = address(0xE3);
        vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotReady.selector, empty));
        this.externalAuditedClone(empty);
    }

    function testPinnedAuthoriserSkipsUnsetPins() external view {
        uint256[5] memory chains = [
            LibSafeInvariants.BASE_CHAIN_ID,
            LibSafeInvariants.ETHEREUM_CHAIN_ID,
            LibSafeInvariants.HYPEREVM_CHAIN_ID,
            LibSafeInvariants.ROBINHOOD_CHAIN_ID,
            LibSafeInvariants.BSC_CHAIN_ID
        ];
        for (uint256 c = 0; c < chains.length; c++) {
            if (LibEuAuthoriserInvariants.euAuthoriserForChainId(chains[c]) == address(0)) {
                LibEuAuthoriserInvariants.assertPinnedAuthoriser(chains[c], SAFE, TIMELOCK);
            }
        }
    }

    function externalAuditedClone(address authoriser) external view {
        LibEuAuthoriserInvariants.assertIsAuditedClone(authoriser);
    }

    function testUnknownChainReverts() external {
        vm.expectRevert(abi.encodeWithSelector(UnsupportedChainForEuAuthoriser.selector, 123456));
        this.externalPin(123456);
    }

    function externalActiveChain() external view returns (address) {
        return LibEuAuthoriserInvariants.activeChainEuAuthoriser();
    }

    function externalPin(uint256 chainId) external pure returns (address) {
        return LibEuAuthoriserInvariants.euAuthoriserForChainId(chainId);
    }

    function externalUniformAuthoriser(TokenInstance[] memory tokens, address expected) external view {
        LibTokenInvariants.assertUniformAuthoriser(tokens, expected);
    }

    function testUniformAuthoriserRoutesEuAssetToItsOwnAuthoriser() external {
        vm.chainId(LibSafeInvariants.BASE_CHAIN_ID);
        address shared = address(0x5AA4ED);
        address vaultA = address(0xA1);
        address vaultL = address(0xA2);
        TokenInstance[] memory tokens = new TokenInstance[](2);
        tokens[0] = TokenInstance({
            underlying: "SNES", receipt: address(0), receiptVault: vaultA, wrappedTokenVault: address(0)
        });
        tokens[1] =
            TokenInstance({underlying: "MC", receipt: address(0), receiptVault: vaultL, wrappedTokenVault: address(0)});
        vm.mockCall(vaultA, abi.encodeWithSignature("authorizer()"), abi.encode(shared));
        vm.mockCall(vaultL, abi.encodeWithSignature("authorizer()"), abi.encode(shared));
        address want = LibEuAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
        if (want == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotReady.selector, address(0)));
            this.externalUniformAuthoriser(tokens, shared);

            vm.mockCall(vaultL, abi.encodeWithSignature("authorizer()"), abi.encode(address(0)));
            vm.expectRevert(abi.encodeWithSelector(EuAuthoriserNotReady.selector, address(0)));
            this.externalUniformAuthoriser(tokens, shared);
        } else {
            vm.expectRevert(abi.encodeWithSelector(ReceiptVaultAuthoriserMismatch.selector, vaultL, want, shared));
            this.externalUniformAuthoriser(tokens, shared);

            vm.mockCall(vaultL, abi.encodeWithSignature("authorizer()"), abi.encode(want));
            this.externalUniformAuthoriser(tokens, shared);
        }
    }
}
