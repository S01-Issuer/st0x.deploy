// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {StoxReceiptVault, EmptyName, EmptySymbol} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxAuthorizer} from "../../../src/concrete/authorize/StoxAuthorizer.sol";
import {
    ACTION_TYPE_NAME_SYMBOL,
    UPDATE_NAME_SYMBOL,
    UPDATE_NAME_SYMBOL_ADMIN
} from "../../../src/concrete/CorporateActionRegistry.sol";
import {
    OffchainAssetReceiptVaultConfigV2,
    OffchainAssetReceiptVault,
    ReceiptVaultConfigV2
} from "ethgild/concrete/vault/OffchainAssetReceiptVault.sol";
import {
    OffchainAssetReceiptVaultAuthorizerV1Config
} from "ethgild/concrete/authorize/OffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    OffchainAssetReceiptVaultBeaconSetDeployer,
    OffchainAssetReceiptVaultBeaconSetDeployerConfig
} from "ethgild/concrete/deploy/OffchainAssetReceiptVaultBeaconSetDeployer.sol";
import {Receipt as ReceiptContract} from "ethgild/concrete/receipt/Receipt.sol";
import {Unauthorized} from "ethgild/interface/IAuthorizeV1.sol";

/// @title StoxReceiptVault name/symbol tests
/// @notice Tests for the StoxReceiptVault name/symbol override functionality
/// in isolation — independent of the CorporateActionRegistry.
contract StoxReceiptVaultNameSymbolTest is Test {
    StoxReceiptVault internal vault;
    StoxAuthorizer internal authorizer;
    address internal admin;

    function setUp() public {
        admin = makeAddr("admin");

        ReceiptContract receiptImpl = new ReceiptContract();
        StoxReceiptVault vaultImpl = new StoxReceiptVault();
        OffchainAssetReceiptVaultBeaconSetDeployer deployer = new OffchainAssetReceiptVaultBeaconSetDeployer(
            OffchainAssetReceiptVaultBeaconSetDeployerConfig({
                initialOwner: address(this),
                initialReceiptImplementation: address(receiptImpl),
                initialOffchainAssetReceiptVaultImplementation: address(vaultImpl)
            })
        );

        vault = StoxReceiptVault(
            payable(address(
                    deployer.newOffchainAssetReceiptVault(
                        OffchainAssetReceiptVaultConfigV2({
                            initialAdmin: admin,
                            receiptVaultConfig: ReceiptVaultConfigV2({
                                asset: address(0), name: "Tokenized COIN", symbol: "tCOIN", receipt: address(0)
                            })
                        })
                    )
                ))
        );

        StoxAuthorizer authImpl = new StoxAuthorizer();
        authorizer = StoxAuthorizer(Clones.clone(address(authImpl)));
        authorizer.initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})));

        vm.prank(admin);
        vault.setAuthorizer(authorizer);
    }

    // =========================================================================
    // name() / symbol() fallthrough
    // =========================================================================

    /// Before any update, name() returns the base vault name.
    function testNameFallsThrough() external view {
        assertEq(vault.name(), "Tokenized COIN");
    }

    /// Before any update, symbol() returns the base vault symbol.
    function testSymbolFallsThrough() external view {
        assertEq(vault.symbol(), "tCOIN");
    }

    // =========================================================================
    // updateNameSymbol — authorised caller
    // =========================================================================

    /// An authorised caller can update name and symbol.
    function testUpdateNameSymbolAuthorised() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.prank(caller);
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "New COIN", "NCOIN");

        assertEq(vault.name(), "New COIN");
        assertEq(vault.symbol(), "NCOIN");
    }

    /// Updating name/symbol emits NameSymbolUpdated with correct params.
    function testUpdateNameSymbolEmitsEvent() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit StoxReceiptVault.NameSymbolUpdated(caller, "New COIN", "NCOIN");

        vm.prank(caller);
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "New COIN", "NCOIN");
    }

    /// Multiple updates — latest values win.
    function testMultipleUpdatesLatestWins() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.startPrank(caller);
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "First", "F1");
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 2, "Second", "S2");
        vm.stopPrank();

        assertEq(vault.name(), "Second");
        assertEq(vault.symbol(), "S2");
    }

    // =========================================================================
    // updateNameSymbol — unauthorised caller
    // =========================================================================

    /// An unauthorised caller is reverted.
    function testUpdateNameSymbolRevertsUnauthorised() external {
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert();
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "Hacked", "HACK");
    }

    /// A caller whose role was revoked is reverted.
    function testUpdateNameSymbolRevertsAfterRevocation() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        authorizer.revokeRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert();
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "Hacked", "HACK");
    }

    // =========================================================================
    // updateNameSymbol — empty name/symbol reverts
    // =========================================================================

    /// Empty name reverts.
    function testUpdateRevertsEmptyName() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(EmptyName.selector);
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "", "SYM");
    }

    /// Empty symbol reverts.
    function testUpdateRevertsEmptySymbol() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(EmptySymbol.selector);
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "Name", "");
    }

    /// Both empty reverts with EmptyName (checked first).
    function testUpdateRevertsBothEmpty() external {
        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.prank(caller);
        vm.expectRevert(EmptyName.selector);
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "", "");
    }

    // =========================================================================
    // Fuzz
    // =========================================================================

    /// Fuzz: any non-empty name/symbol pair is accepted for authorised callers.
    function testFuzzUpdateNameSymbol(
        bytes32 actionType,
        uint256 number,
        string memory newName,
        string memory newSymbol
    ) external {
        vm.assume(bytes(newName).length > 0);
        vm.assume(bytes(newSymbol).length > 0);

        address caller = makeAddr("caller");
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, caller);
        vm.stopPrank();

        vm.prank(caller);
        vault.updateNameSymbol(actionType, number, newName, newSymbol);

        assertEq(vault.name(), newName);
        assertEq(vault.symbol(), newSymbol);
    }
}
