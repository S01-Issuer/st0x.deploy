// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {
    CorporateActionRegistry,
    ACTION_TYPE_NAME_SYMBOL,
    UPDATE_NAME_SYMBOL,
    UPDATE_NAME_SYMBOL_ADMIN,
    ActionState,
    Action
} from "../../../src/concrete/CorporateActionRegistry.sol";
import {StoxReceiptVault, EmptyName, EmptySymbol} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxAuthorizer} from "../../../src/concrete/authorize/StoxAuthorizer.sol";
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
import {
    EffectiveTimeMustBeFuture,
    ActionNotScheduled,
    ActionNotYetEffective,
    ActionDoesNotExist
} from "../../../src/error/ErrCorporateActionRegistry.sol";

contract CorporateActionRegistryTest is Test {
    StoxReceiptVault internal vault;
    StoxAuthorizer internal authorizer;
    CorporateActionRegistry internal registry;
    address internal admin;

    OffchainAssetReceiptVaultBeaconSetDeployer internal deployer;

    function setUp() public {
        admin = makeAddr("admin");

        // Deploy implementations and deployer.
        ReceiptContract receiptImpl = new ReceiptContract();
        StoxReceiptVault vaultImpl = new StoxReceiptVault();
        deployer = new OffchainAssetReceiptVaultBeaconSetDeployer(
            OffchainAssetReceiptVaultBeaconSetDeployerConfig({
                initialOwner: address(this),
                initialReceiptImplementation: address(receiptImpl),
                initialOffchainAssetReceiptVaultImplementation: address(vaultImpl)
            })
        );

        // Deploy vault via the deployer.
        vault = StoxReceiptVault(
            payable(address(
                    deployer.newOffchainAssetReceiptVault(
                        OffchainAssetReceiptVaultConfigV2({
                            initialAdmin: admin,
                            receiptVaultConfig: ReceiptVaultConfigV2({
                                asset: address(0), name: "tCOIN", symbol: "tCOIN", receipt: address(0)
                            })
                        })
                    )
                ))
        );

        // Deploy and initialize the StoxAuthorizer.
        StoxAuthorizer authorizerImpl = new StoxAuthorizer();
        authorizer = StoxAuthorizer(Clones.clone(address(authorizerImpl)));
        authorizer.initialize(abi.encode(OffchainAssetReceiptVaultAuthorizerV1Config({initialAdmin: admin})));

        // Set the authorizer on the vault.
        vm.prank(admin);
        vault.setAuthorizer(authorizer);

        // Deploy the registry.
        registry = new CorporateActionRegistry();

        // Grant the registry the UPDATE_NAME_SYMBOL role.
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, address(registry));
        vm.stopPrank();
    }

    /// Scheduling a name/symbol update works and produces the correct state.
    function testScheduleNameSymbol() external {
        uint256 effectiveTime = block.timestamp + 1 days;
        bytes memory data = abi.encode("NewCOIN", "NCOIN");

        // Admin schedules through the registry.
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, admin);
        uint256 number = registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, data, effectiveTime);
        vm.stopPrank();

        assertEq(number, 1);
        assertEq(registry.counters(address(vault), ACTION_TYPE_NAME_SYMBOL), 1);

        Action memory action = registry.getAction(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);
        assertEq(action.actionType, ACTION_TYPE_NAME_SYMBOL);
        assertTrue(action.state == ActionState.SCHEDULED);
        assertEq(action.effectiveTime, effectiveTime);
        assertEq(keccak256(action.data), keccak256(data));
    }

    /// Executing a name/symbol update updates the vault's name and symbol.
    function testExecuteNameSymbol() external {
        uint256 effectiveTime = block.timestamp + 1 days;
        bytes memory data = abi.encode("NewCOIN", "NCOIN");

        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, admin);
        registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, data, effectiveTime);
        vm.stopPrank();

        // Warp past effective time.
        vm.warp(effectiveTime + 1);

        // Anyone can execute.
        registry.execute(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);

        // Verify vault state.
        assertEq(vault.name(), "NewCOIN");
        assertEq(vault.symbol(), "NCOIN");

        // Verify action is COMPLETE.
        ActionState state = registry.getActionState(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);
        assertTrue(state == ActionState.COMPLETE);
    }

    /// Scheduling with effective time in the past reverts.
    function testScheduleRevertsPastEffectiveTime() external {
        bytes memory data = abi.encode("NewCOIN", "NCOIN");

        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, admin);
        vm.expectRevert(
            abi.encodeWithSelector(EffectiveTimeMustBeFuture.selector, block.timestamp - 1, block.timestamp)
        );
        registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, data, block.timestamp - 1);
        vm.stopPrank();
    }

    /// Executing before effective time reverts.
    function testExecuteRevertsBeforeEffectiveTime() external {
        uint256 effectiveTime = block.timestamp + 1 days;
        bytes memory data = abi.encode("NewCOIN", "NCOIN");

        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, admin);
        registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, data, effectiveTime);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(ActionNotYetEffective.selector, effectiveTime, block.timestamp));
        registry.execute(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);
    }

    /// Double execution reverts.
    function testDoubleExecuteReverts() external {
        uint256 effectiveTime = block.timestamp + 1 days;
        bytes memory data = abi.encode("NewCOIN", "NCOIN");

        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, admin);
        registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, data, effectiveTime);
        vm.stopPrank();

        vm.warp(effectiveTime + 1);
        registry.execute(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);

        vm.expectRevert(abi.encodeWithSelector(ActionNotScheduled.selector, address(vault), ACTION_TYPE_NAME_SYMBOL, 1));
        registry.execute(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);
    }

    /// Scheduling without the UPDATE_NAME_SYMBOL role reverts.
    function testScheduleRevertsUnauthorized() external {
        uint256 effectiveTime = block.timestamp + 1 days;
        bytes memory data = abi.encode("NewCOIN", "NCOIN");

        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert();
        registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, data, effectiveTime);
    }

    /// Multiple actions produce sequential numbers.
    function testSequentialNumbers() external {
        vm.startPrank(admin);
        authorizer.grantRole(UPDATE_NAME_SYMBOL, admin);

        uint256 n1 =
            registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, abi.encode("A", "A"), block.timestamp + 1 days);
        uint256 n2 =
            registry.schedule(address(vault), ACTION_TYPE_NAME_SYMBOL, abi.encode("B", "B"), block.timestamp + 2 days);
        vm.stopPrank();

        assertEq(n1, 1);
        assertEq(n2, 2);
    }

    /// Querying a non-existent action reverts.
    function testGetActionRevertsNonExistent() external {
        vm.expectRevert(abi.encodeWithSelector(ActionDoesNotExist.selector, address(vault), ACTION_TYPE_NAME_SYMBOL, 1));
        registry.getAction(address(vault), ACTION_TYPE_NAME_SYMBOL, 1);
    }

    /// Name/symbol before any corporate action falls through to the base vault.
    function testDefaultNameSymbol() external view {
        assertEq(vault.name(), "tCOIN");
        assertEq(vault.symbol(), "tCOIN");
    }

    /// Calling updateNameSymbol directly on the vault without the role reverts.
    function testDirectUpdateNameSymbolRevertsUnauthorized() external {
        address rando = makeAddr("rando");
        vm.prank(rando);
        vm.expectRevert();
        vault.updateNameSymbol(ACTION_TYPE_NAME_SYMBOL, 1, "Hacked", "HACK");
    }
}
