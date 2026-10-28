// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {OffchainAssetReceiptVaultRbacV1} from "rain-vats-0.2.12/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {IAuthorizeV1} from "rain-vats-0.2.12/src/interface/IAuthorizeV1.sol";

import {ST0xOrchestrator} from "../../../../src/concrete/ST0xOrchestrator.sol";
import {StoxReceiptVault} from "../../../../src/concrete/StoxReceiptVault.sol";
import {IST0xOrchestratorV2, MintAuthV1} from "../../../../src/interface/IST0xOrchestratorV2.sol";
import {LibProdDeployV4} from "../../../../src/generated/LibProdDeployV4.sol";
import {LibStoxConfig} from "../../../../src/lib/LibStoxConfig.sol";
import {LibTestDeploy} from "../../../lib/LibTestDeploy.sol";
import {OrchestratorIntegrationTest} from "./OrchestratorIntegrationTest.sol";

/// @title GuardChecksTokensOwnBeaconsTest
/// @notice The vault-logic guard reads each token's beacon, and its receipt's,
/// from their proxy bytecode: tokens built from different beacons are each
/// checked against their own, and a token that is not a registry beacon proxy
/// is refused.
contract GuardChecksTokensOwnBeaconsTest is OrchestratorIntegrationTest {
    address internal constant OTHER_AUTHORITY = address(uint160(uint256(keccak256("OTHER_AUTHORITY"))));
    address internal constant OTHER_VAULT_BEACON = address(uint160(uint256(keccak256("OTHER_VAULT_BEACON"))));
    address internal constant OTHER_RECEIPT_BEACON = address(uint160(uint256(keccak256("OTHER_RECEIPT_BEACON"))));

    /// A token and receipt from beacons other than `vault`'s, serving the same
    /// implementations.
    function otherToken() internal returns (StoxReceiptVault) {
        LibTestDeploy.placeBeacon(vm, OTHER_VAULT_BEACON, LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE, BEACON_OWNER);
        LibTestDeploy.placeBeacon(vm, OTHER_RECEIPT_BEACON, LibProdDeployV4.STOX_RECEIPT_CANDIDATE, BEACON_OWNER);
        LibTestDeploy.bind(
            vm, OTHER_AUTHORITY, LibStoxConfig.VAULT_BEACON_NAME, "address", abi.encode(OTHER_VAULT_BEACON)
        );
        LibTestDeploy.bind(
            vm, OTHER_AUTHORITY, LibStoxConfig.RECEIPT_BEACON_NAME, "address", abi.encode(OTHER_RECEIPT_BEACON)
        );
        LibTestDeploy.bind(
            vm,
            OTHER_AUTHORITY,
            RBAC_NAME,
            "(address,address)",
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: ADMIN, authorizer: IAuthorizeV1(address(authorizer))}))
        );
        return LibTestDeploy.newVault(
            OTHER_AUTHORITY, LibTestDeploy.vaultData("Other tStock", "tOTHER", OTHER_AUTHORITY, RBAC_NAME)
        );
    }

    function upgrade(address beacon) internal returns (address) {
        address newImpl = address(new ST0xOrchestrator());
        vm.prank(BEACON_OWNER);
        UpgradeableBeacon(beacon).upgradeTo(newImpl);
        return newImpl;
    }

    function mintVault(address token, bytes memory err) internal {
        (address eoa, uint256 pk) = makeAddrAndKey("own-beacon-recipient");
        MintAuthV1 memory auth = _signedMintAuth(token, eoa, 1e18, keccak256(abi.encode(token, err)), pk);
        if (err.length > 0) {
            vm.expectRevert(err);
        }
        vm.prank(MM);
        orchestrator.mint(token, eoa, 1e18, auth, "");
    }

    /// Upgrading the other token's vault beacon halts only the other token.
    function testUpgradedVaultBeaconHaltsOnlyItsTokens() external {
        StoxReceiptVault other = otherToken();
        assertTrue(orchestrator.vaultLogicIsExpected(address(vault)), "vault passes");
        assertTrue(orchestrator.vaultLogicIsExpected(address(other)), "other passes");

        address newImpl = upgrade(OTHER_VAULT_BEACON);

        assertTrue(orchestrator.vaultLogicIsExpected(address(vault)), "vault ignores the other beacon");
        assertFalse(orchestrator.vaultLogicIsExpected(address(other)), "other follows its own beacon");
        mintVault(address(vault), "");
        mintVault(
            address(other),
            abi.encodeWithSelector(
                IST0xOrchestratorV2.VaultLogicMismatch.selector, LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE, newImpl
            )
        );
    }

    /// Upgrading the other token's receipt beacon halts only the other token.
    function testUpgradedReceiptBeaconHaltsOnlyItsTokens() external {
        StoxReceiptVault other = otherToken();

        address newImpl = upgrade(OTHER_RECEIPT_BEACON);

        assertTrue(orchestrator.vaultLogicIsExpected(address(vault)), "vault ignores the other receipt beacon");
        assertFalse(orchestrator.vaultLogicIsExpected(address(other)), "other follows its own receipt beacon");
        mintVault(address(vault), "");
        mintVault(
            address(other),
            abi.encodeWithSelector(
                IST0xOrchestratorV2.ReceiptLogicMismatch.selector, LibProdDeployV4.STOX_RECEIPT_CANDIDATE, newImpl
            )
        );
    }

    /// The vault implementation itself is the expected logic but not a proxy.
    function testNonProxyTokenReverts() external {
        address token = LibProdDeployV4.STOX_RECEIPT_VAULT_CANDIDATE;
        assertFalse(orchestrator.vaultLogicIsExpected(token), "implementation is not a proxy");
        mintVault(token, abi.encodeWithSelector(IST0xOrchestratorV2.NotRegistryBeaconProxy.selector, token));
        vm.prank(MM);
        vm.expectRevert(abi.encodeWithSelector(IST0xOrchestratorV2.NotRegistryBeaconProxy.selector, token));
        orchestrator.burn(token, 1e18, "");
    }
}
