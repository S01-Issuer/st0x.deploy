// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {
    DeploySafeEthereum,
    ISafeProxyFactory,
    SafeInfraMissing,
    SafeAlreadyDeployed
} from "../../script/20260707-deploy-safe-ethereum.s.sol";
import {LibStoxSafeGenesis} from "../../src/lib/LibStoxSafeGenesis.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {LibRainDeploy} from "rain-deploy-0.1.4/src/lib/LibRainDeploy.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";

/// @notice Minimal Safe getters for asserting the reproduced genesis state.
interface ISafeState {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

/// @title DeploySafeEthereumTest
/// @notice Proves the pinned genesis parameters in `LibStoxSafeGenesis`
/// actually reproduce the ST0x token-owner Safe's Base address — the whole
/// point of the matched-address deploy. Runs the real Safe v1.3.0 factory on
/// an Ethereum fork and asserts the produced proxy is byte-for-byte the
/// pinned `LibSafeInvariants.STOX_TOKEN_OWNER_SAFE`, then checks the freshly
/// deployed Safe is in the documented genesis state (3 owners, threshold 2).
contract DeploySafeEthereumTest is Test {
    /// The genesis params reproduce the exact Base Safe address on Ethereum,
    /// and the resulting Safe is in its genesis policy state.
    function testReproducesBaseSafeAddressOnEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);

        address expected = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        // Precondition: the target is empty on Ethereum (nothing to collide
        // with) and the v1.3.0 infra is present.
        assertEq(expected.code.length, 0, "target already has code on Ethereum");
        assertGt(LibStoxSafeGenesis.SAFE_1_3_0_PROXY_FACTORY.code.length, 0, "v1.3.0 factory missing on Ethereum");
        assertGt(LibStoxSafeGenesis.SAFE_1_3_0_L2_SINGLETON.code.length, 0, "v1.3.0 singleton missing on Ethereum");

        address proxy = ISafeProxyFactory(LibStoxSafeGenesis.SAFE_1_3_0_PROXY_FACTORY)
            .createProxyWithNonce(
                LibStoxSafeGenesis.SAFE_1_3_0_L2_SINGLETON,
                LibStoxSafeGenesis.GENESIS_SETUP,
                LibStoxSafeGenesis.GENESIS_SALT_NONCE
            );

        assertEq(proxy, expected, "reproduced Safe address != Base token-owner Safe");

        // Genesis policy state, as documented: 3 owners, threshold 2.
        address[] memory owners = ISafeState(proxy).getOwners();
        assertEq(owners.length, 3, "genesis owner count");
        assertEq(owners[0], LibStoxSafeGenesis.GENESIS_OWNER_1, "genesis owner 1");
        assertEq(owners[1], LibStoxSafeGenesis.GENESIS_OWNER_2, "genesis owner 2");
        assertEq(owners[2], LibStoxSafeGenesis.GENESIS_OWNER_3, "genesis owner 3");
        assertEq(ISafeState(proxy).getThreshold(), LibStoxSafeGenesis.GENESIS_THRESHOLD, "genesis threshold");
    }

    /// `run()` reverts `SafeInfraMissing` when the Safe v1.3.0 factory has no
    /// code on the active chain — with no fork the canonical infra is absent,
    /// so the reproduction would not land at the expected address. Guards
    /// against dispatching on a chain that lacks the v1.3.0 contracts.
    function testRunRevertsWhenInfraMissing() external {
        DeploySafeEthereum script = new DeploySafeEthereum();
        vm.expectRevert(abi.encodeWithSelector(SafeInfraMissing.selector, LibStoxSafeGenesis.SAFE_1_3_0_PROXY_FACTORY));
        script.run();
    }

    /// `run()` reverts `SafeAlreadyDeployed` when the target address already
    /// has code — proven on a BASE fork, where the matched address IS already
    /// a live Safe (it is the Base token-owner Safe). This exercises both the
    /// matched-address property and the idempotence guard: re-running against
    /// a chain that already carries the Safe is refused rather than
    /// double-deploying.
    function testRunRevertsWhenAlreadyDeployedOnBase() external {
        DeploySafeEthereum script = new DeploySafeEthereum();
        vm.makePersistent(address(script));
        vm.createSelectFork(LibRainDeploy.BASE);
        // Precondition: the Safe is live at the matched address on Base.
        assertGt(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE.code.length, 0, "Base Safe expected live at matched address");
        vm.expectRevert(abi.encodeWithSelector(SafeAlreadyDeployed.selector, LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
        script.run();
    }

    /// **Cross-chain Safe-policy parity — the forcing function for the
    /// genesis→current replay.** The Ethereum token-owner Safe is the SAME
    /// Safe reproduced at the SAME address on every chain, so it must satisfy
    /// the identical Safe invariants as Base: v1.4.1 singleton + proxy
    /// codehash, the same owner set, and the same threshold — all pinned once
    /// in `LibSafeInvariants` and shared by both chains. This test runs those
    /// pins against the LIVE Ethereum Safe.
    ///
    /// It is deliberately RED until the Ethereum Safe is both deployed AND
    /// policy-aligned: the matched-address deploy (§ 3a) lands the Safe in its
    /// GENESIS state (3 owners, threshold 2, v1.3.0), which fails these pins;
    /// only the owner-add + threshold-raise + v1.4.1 upgrade replay makes it
    /// pass. So standing up the Ethereum Safe immediately surfaces this
    /// failing test, and it is resolved precisely by changing the owners +
    /// threshold over to match Base.
    function testEthereumSafeMatchesBasePolicy() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        LibSafeInvariants.assertAll(IGnosisSafe(LibSafeInvariants.STOX_TOKEN_OWNER_SAFE));
    }
}
