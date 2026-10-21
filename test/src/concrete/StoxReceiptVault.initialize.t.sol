// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.7.0/access/IAccessControl.sol";
import {Base64} from "@openzeppelin-contracts-5.7.0/utils/Base64.sol";
import {IAuthorizeV1} from "rain-vats-0.2.6-pr345/src/interface/IAuthorizeV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.2.6-pr345/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.1/src/concrete/CloneFactory.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxReceipt} from "../../../src/concrete/StoxReceipt.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {AuthorizerMissingCorporateActionAdmin} from "../../../src/error/ErrCorporateAction.sol";
import {SCHEDULE_CORPORATE_ACTION} from "../../../src/lib/LibCorporateAction.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {LibRainDeploy} from "rain-deploy-0.1.20/src/lib/LibRainDeploy.sol";
import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {OwnedStoxReceiptVault} from "./OwnedStoxReceiptVault.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";

/// @title StoxReceiptVault initialize
/// @notice A vault built by the clone factory resolves its authorizer from
/// the registry RBAC and holds it to the corporate-action admin check, and
/// its receipt's metadata names the off-chain asset.
contract StoxReceiptVaultInitializeTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");

    function setUp() external {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
    }

    function _newCorporateActionsAuthorizer() internal returns (IAuthorizeV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        return IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl),
                    abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: OWNER})),
                    bytes32(uint256(uint160(address(impl))))
                )
        );
    }

    function _data() internal pure returns (bytes memory) {
        return LibTestDeploy.vaultData("Test tStock", "tTEST", AUTHORITY, RBAC_NAME);
    }

    /// The RBAC's authorizer and owner are installed, replacing the vault
    /// itself, which `_initialize` installs first.
    function testInitializeInstallsTheRbacAuthorizer() external {
        IAuthorizeV1 authorizer = _newCorporateActionsAuthorizer();
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
        StoxReceiptVault vault = LibTestDeploy.newVault(_data());
        assertEq(address(vault.authorizer()), address(authorizer));
        assertEq(vault.owner(), OWNER);
    }

    /// An RBAC authorizer without a corporate-action admin is refused at
    /// initialize, as it is at `setAuthorizer`.
    function testInitializeRejectsAnRbacAuthorizerMissingAnAdmin() external {
        address bad = makeAddr("authorizer-without-schedule-admin");
        vm.etch(bad, hex"00");
        vm.mockCall(
            bad,
            abi.encodeWithSelector(IAccessControl.getRoleAdmin.selector, SCHEDULE_CORPORATE_ACTION),
            abi.encode(bytes32(0))
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, IAuthorizeV1(bad));
        StoxReceiptVault vault =
            StoxReceiptVault(payable(address(new BeaconProxy(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, ""))));
        vm.expectRevert(
            abi.encodeWithSelector(AuthorizerMissingCorporateActionAdmin.selector, bad, SCHEDULE_CORPORATE_ACTION)
        );
        vault.initialize(_data());
    }

    /// Outside initialization the vault is no exemption: it lacks
    /// `getRoleAdmin`, so installing it as its own authorizer reverts.
    function testSetAuthorizerRejectsTheVaultItself() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        vm.prank(OWNER);
        vm.expectRevert();
        vault.setAuthorizer(IAuthorizeV1(address(vault)));
        assertEq(address(vault.authorizer()), address(0));
    }

    /// The receipt's `uri` is vats' receipt JSON with the off-chain asset
    /// named, where the generic receipt reads `asset()` at `address(0)`.
    function testReceiptUriNamesTheOffchainAsset() external {
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, _newCorporateActionsAuthorizer());
        StoxReceipt receipt = StoxReceipt(address(LibTestDeploy.newVault(_data()).receipt()));
        assertEq(
            receipt.uri(0),
            string.concat(
                "data:application/json;base64,",
                Base64.encode(
                    bytes(
                        "{\"decimals\":18,\"description\":\"1 of these receipts can be burned alongside 1 tTEST to redeem the underlying off-chain asset from the vault.\",\"name\":\"tTEST Receipt\"}"
                    )
                )
            )
        );
    }
}
