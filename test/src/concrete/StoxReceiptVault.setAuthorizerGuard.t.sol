// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "rain-vats-0.1.3/src/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config
} from "rain-vats-0.1.3/src/concrete/authorize/OffchainAssetReceiptVaultPaymentMintAuthorizerV1.sol";
import {IAuthorizeV1} from "rain-vats-0.1.3/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-0.1.0/src/concrete/CloneFactory.sol";
import {VerifyAlwaysApproved} from "rain-verify-interface-0.1.0/src/concrete/VerifyAlwaysApproved.sol";
import {AuthorizerMissingCorporateActionAdmin} from "../../../src/error/ErrCorporateAction.sol";
import {SCHEDULE_CORPORATE_ACTION, CANCEL_CORPORATE_ACTION} from "../../../src/lib/LibCorporateAction.sol";
import {MockERC20} from "../../concrete/MockERC20.sol";

/// Minimal subclass that transfers ownership to a known address in its
/// constructor so the test can pose as the vault owner without running
/// the full Zoltu-deployer-and-initialize flow. The guard under test is
/// `setAuthorizer`, which only depends on `OwnableUpgradeable`'s owner
/// being set — not on the rest of vault initialization.
contract OwnedStoxReceiptVault is StoxReceiptVault {
    constructor(address owner) {
        _transferOwnership(owner);
    }
}

/// @title StoxReceiptVault setAuthorizer guard
/// @notice Pins that `StoxReceiptVault.setAuthorizer` rejects authorizers
/// that lack admin hierarchy for either corporate-action role, surfacing
/// `AuthorizerMissingCorporateActionAdmin` at the pairing point instead
/// of the (much later) first attempted use.
contract StoxReceiptVaultSetAuthorizerGuardTest is Test {
    address constant OWNER = address(uint160(uint256(keccak256("OWNER"))));

    function _newPaymentMintAuthorizer() internal returns (StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1) {
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 impl =
            new StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        bytes memory initData = abi.encode(
            OffchainAssetReceiptVaultPaymentMintAuthorizerV1Config({
                receiptVault: address(this),
                verify: address(new VerifyAlwaysApproved()),
                owner: OWNER,
                paymentToken: address(new MockERC20()),
                maxSharesSupply: 1e27
            })
        );
        return StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1(factory.clone(address(impl), initData));
    }

    function _newCorporateActionsAuthorizer() internal returns (StoxOffchainAssetReceiptVaultAuthorizerV1) {
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        CloneFactory factory = new CloneFactory();
        bytes memory initData = abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: OWNER}));
        return StoxOffchainAssetReceiptVaultAuthorizerV1(factory.clone(address(impl), initData));
    }

    /// Pairing the PaymentMint authorizer (missing corporate-action role
    /// admin hierarchy) reverts at setAuthorizer time on
    /// SCHEDULE_CORPORATE_ACTION before it ever lands.
    function testSetAuthorizerRejectsPaymentMintAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultPaymentMintAuthorizerV1 bad = _newPaymentMintAuthorizer();
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuthorizerMissingCorporateActionAdmin.selector, address(bad), SCHEDULE_CORPORATE_ACTION
            )
        );
        vault.setAuthorizer(IAuthorizeV1(address(bad)));
    }

    /// The corporate-actions authorizer configures both role admins, so
    /// the guard accepts it and the installation goes through.
    function testSetAuthorizerAcceptsCorporateActionsAuthorizer() external {
        OwnedStoxReceiptVault vault = new OwnedStoxReceiptVault(OWNER);
        StoxOffchainAssetReceiptVaultAuthorizerV1 good = _newCorporateActionsAuthorizer();
        vm.prank(OWNER);
        vault.setAuthorizer(IAuthorizeV1(address(good)));
    }
}
