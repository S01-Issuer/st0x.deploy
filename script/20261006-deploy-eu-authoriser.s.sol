// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.17.0/src/Script.sol";
import {console2} from "forge-std-1.17.0/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {
    DEPLOYED_ADDRESS as CLONE_FACTORY_V4,
    BYTECODE_HASH as CLONE_FACTORY_V4_CODEHASH
} from "rain-factory-deploy-0.1.10/src/generated/0_1_10/CloneFactory.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.6/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";

import {ICloneableFactoryV4} from "../src/interface/ICloneableFactoryV4.sol";
import {IGnosisSafe} from "../src/interface/IGnosisSafe.sol";
import {RoleGrant} from "../src/lib/LibAuthoriserInvariants.sol";
import {LibEuAuthoriserInvariants} from "../src/lib/LibEuAuthoriserInvariants.sol";
import {LibProdDeployV4} from "../src/generated/LibProdDeployV4.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";
import {LibSafeOps, SafeTx} from "../src/lib/LibSafeOps.sol";
import {LibTimelockInvariants} from "../src/lib/LibTimelockInvariants.sol";

bytes32 constant EU_AUTHORISER_SALT = keccak256("st0x.eu-assets-authoriser");

error EuAuthoriserPinAlreadyHydrated(address pinned);

error EuImplNotReady(address impl);

error EuCloneFactoryNotReady(address factory);

error EuCloneAddressMismatch(address predicted, address deployed);

error EuSafeNotInitialAdmin(address clone, bytes32 role);

/// @title DeployEuAuthoriser
/// @notice Clones the audited 0.1.1 authoriser at its open-salt address with
/// the Safe as initial admin, then authors the Safe bundle that grants the EU
/// assets role map, hands the `_ADMIN` roles to the timelock and renounces
/// them from the Safe.
contract DeployEuAuthoriser is Script {
    string internal constant BUNDLE_NAME = "ST0x EU assets authoriser: role map and admin handover to the timelock";

    function artifactPath() internal view virtual returns (string memory) {
        return string.concat("out/20261006-deploy-eu-authoriser-", vm.toString(block.chainid), ".json");
    }

    function pinnedAuthoriser() internal view virtual returns (address) {
        return LibEuAuthoriserInvariants.euAuthoriserForChainId(block.chainid);
    }

    function run() external {
        (address safe, address timelock, address impl, address factory) = preflight();
        address clone = predictedClone(factory, impl, safe);

        if (clone.code.length == 0) {
            vm.startBroadcast();
            address deployed =
                ICloneableFactoryV4(factory).cloneDeterministicOpenSalt(impl, cloneData(safe), EU_AUTHORISER_SALT);
            vm.stopBroadcast();
            if (deployed != clone) revert EuCloneAddressMismatch(clone, deployed);
        }
        assertInitialState(clone, safe);

        SafeTx[] memory txs = handoverBundle(clone, safe, timelock);
        IGnosisSafe gnosisSafe = IGnosisSafe(safe);
        uint256 nonce = gnosisSafe.nonce();
        bytes32 bundleSafeTxHash = LibSafeOps.computeMultiSendSafeTxHash(gnosisSafe, txs, nonce);
        for (uint256 i = 0; i < txs.length; i++) {
            LibSafeOps.simulateExternalCall(gnosisSafe, txs[i].to, txs[i].data);
        }
        LibEuAuthoriserInvariants.assertExpectedGrants(clone, safe, timelock);

        string memory json = LibSafeOps.emitTxBuilderJson(safe, block.chainid, BUNDLE_NAME, txs);
        vm.writeFile(artifactPath(), json);
        console2.log("==== TX BUILDER JSON BEGIN ====");
        console2.log(json);
        console2.log("==== TX BUILDER JSON END ====");
        console2.log("EU assets authoriser:", vm.toString(clone));
        console2.log("Bundle MultiSend SafeTxHash:", vm.toString(bundleSafeTxHash));
        console2.log("Nonce:", nonce);
        console2.log("Chain:", block.chainid);
    }

    function verify(string calldata jsonPath) external view {
        (address safe, address timelock, address impl, address factory) = preflight();
        address clone = predictedClone(factory, impl, safe);
        assertInitialState(clone, safe);
        SafeTx[] memory expected = handoverBundle(clone, safe, timelock);
        LibSafeOps.assertParsedTxsMatch(expected, jsonPath);
        console2.log("Artifact verified against live state.");
        console2.log(
            "Bundle MultiSend SafeTxHash:",
            vm.toString(LibSafeOps.computeMultiSendSafeTxHash(IGnosisSafe(safe), expected, IGnosisSafe(safe).nonce()))
        );
    }

    function preflight() public view returns (address safe, address timelock, address impl, address factory) {
        address pinned = pinnedAuthoriser();
        if (pinned != address(0)) revert EuAuthoriserPinAlreadyHydrated(pinned);

        safe = LibSafeInvariants.assertActiveChainTokenOwnerSafe(block.chainid);
        timelock = LibTimelockInvariants.timelockForChainId(block.chainid);
        LibTimelockInvariants.assertTimelockState(timelock, safe);

        impl = LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_0_1_1;
        if (
            impl.code.length == 0
                || impl.codehash != LibProdDeployV4.STOX_OFFCHAIN_ASSET_RECEIPT_VAULT_AUTHORIZER_V1_CODEHASH_0_1_1
        ) {
            revert EuImplNotReady(impl);
        }

        factory = CLONE_FACTORY_V4;
        if (factory.code.length == 0 || factory.codehash != CLONE_FACTORY_V4_CODEHASH) {
            revert EuCloneFactoryNotReady(factory);
        }
    }

    function cloneData(address safe) public pure returns (bytes memory) {
        return abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: safe}));
    }

    function predictedClone(address factory, address impl, address safe) public view returns (address) {
        return
            ICloneableFactoryV4(factory).predictDeterministicAddressOpenSalt(impl, cloneData(safe), EU_AUTHORISER_SALT);
    }

    /// @notice The clone exists, is the audited clone, and the Safe still
    /// holds every `_ADMIN` role it was initialised with.
    function assertInitialState(address clone, address safe) public view {
        LibEuAuthoriserInvariants.assertIsAuditedClone(clone);
        bytes32[7] memory admins = LibEuAuthoriserInvariants.adminRoles();
        for (uint256 i = 0; i < admins.length; i++) {
            if (!IAccessControl(clone).hasRole(admins[i], safe)) revert EuSafeNotInitialAdmin(clone, admins[i]);
        }
    }

    /// @notice Every expected grant, then the Safe renouncing each `_ADMIN`.
    function handoverBundle(address clone, address safe, address timelock) public pure returns (SafeTx[] memory txs) {
        RoleGrant[] memory grants = LibEuAuthoriserInvariants.expectedGrants(safe, timelock);
        bytes32[7] memory admins = LibEuAuthoriserInvariants.adminRoles();
        txs = new SafeTx[](grants.length + admins.length);
        for (uint256 i = 0; i < grants.length; i++) {
            txs[i] = SafeTx({
                to: clone,
                value: 0,
                data: abi.encodeCall(IAccessControl.grantRole, (grants[i].role, grants[i].grantee)),
                operation: 0
            });
        }
        for (uint256 i = 0; i < admins.length; i++) {
            txs[grants.length + i] = SafeTx({
                to: clone, value: 0, data: abi.encodeCall(IAccessControl.renounceRole, (admins[i], safe)), operation: 0
            });
        }
    }
}
