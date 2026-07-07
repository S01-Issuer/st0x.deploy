// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.1/src/Script.sol";
import {console2} from "forge-std-1.16.1/src/console2.sol";

import {LibStoxSafeGenesis} from "../src/lib/LibStoxSafeGenesis.sol";
import {LibSafeInvariants} from "../src/lib/LibSafeInvariants.sol";

/// @notice Minimal surface for the Safe v1.3.0 `GnosisSafeProxyFactory`.
interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

/// @notice Pre-flight failed: a required Safe v1.3.0 infrastructure contract
/// (proxy factory or singleton) has no runtime code on the active chain, so
/// the reproduction would not deploy to the expected address.
/// @param infra The missing infrastructure address.
error SafeInfraMissing(address infra);

/// @notice Pre-flight failed: something is already deployed at the target
/// Safe address on this chain. Re-running after the Safe exists would be a
/// no-op at best and a wrong-Safe collision at worst, so the script stops.
/// @param safe The target Safe address that already has code.
error SafeAlreadyDeployed(address safe);

/// @notice The factory returned a proxy at an address other than the pinned
/// Base token-owner Safe. Means a genesis parameter in `LibStoxSafeGenesis`
/// drifted from what Base was actually created with — the reproduction is
/// only meaningful if it lands on the exact same address.
/// @param expected The pinned Base Safe address.
/// @param actual The address the factory actually produced.
error UnexpectedSafeAddress(address expected, address actual);

/// @title DeploySafeEthereum
/// @notice **PENDING.** Reproduces the ST0x token-owner Safe at its Base
/// address on Ethereum in one EOA-broadcast `createProxyWithNonce`; flips to
/// `**EXECUTED YYYY-MM-DD.**` once the Safe is live on Ethereum. This is a
/// permissionless deploy (not a Safe Tx Builder bundle), so it is run
/// locally with `--broadcast` per `docs/ETHEREUM_BOOTSTRAP.md` § 3a rather
/// than dispatched through `run-script.yaml`.
/// @dev Reproduces the ST0x token-owner Safe at its Base address on
/// Ethereum mainnet (RAI-1109, Josh 2026-07-07), by replaying the exact
/// genesis creation call — the canonical Safe v1.3.0 proxy factory +
/// singleton + the verbatim genesis `setup` initializer + `saltNonce`, all
/// pinned in `LibStoxSafeGenesis`. Because the Safe address is
/// `CREATE2(factory, keccak(keccak(initializer) ++ saltNonce), …)`, the same
/// inputs yield the same address on any chain where the v1.3.0 factory +
/// singleton live (they do on Ethereum, verified 2026-07-07).
///
/// **This deploys the Safe in its GENESIS state — 3 owners, threshold 2, on
/// the v1.3.0 singleton.** The live Base Safe has since been upgraded to
/// v1.4.1 and expanded to 6 owners / threshold 3. Reaching parity with that
/// current policy is a separate post-deploy replay (upgrade + owner adds +
/// threshold change), authored as Safe bundles signed by the genesis owners
/// — see `docs/ETHEREUM_BOOTSTRAP.md` § 3a. This script's job is solely to
/// put the matched address on-chain; it deliberately does not touch policy,
/// which only the genesis signers can.
///
/// EOA broadcast (`createProxyWithNonce` is permissionless): reads
/// `DEPLOYMENT_KEY`. Idempotent-guarded — refuses to run if the target
/// already has code.
contract DeploySafeEthereum is Script {
    /// @notice Simulate/broadcast the matched-address Safe deploy. Asserts
    /// the produced address equals the pinned Base Safe before returning, so
    /// a genesis-param drift fails loudly rather than silently deploying a
    /// different Safe.
    function run() external {
        address expected = LibSafeInvariants.STOX_TOKEN_OWNER_SAFE;
        address factory = LibStoxSafeGenesis.SAFE_1_3_0_PROXY_FACTORY;
        address singleton = LibStoxSafeGenesis.SAFE_1_3_0_L2_SINGLETON;

        if (factory.code.length == 0) revert SafeInfraMissing(factory);
        if (singleton.code.length == 0) revert SafeInfraMissing(singleton);
        if (expected.code.length != 0) revert SafeAlreadyDeployed(expected);

        console2.log("Reproducing ST0x token-owner Safe on chain id", block.chainid);
        console2.log("Expected (Base) address:", expected);
        console2.log("Genesis state: 3 owners, threshold 2, Safe v1.3.0 (upgrade + owner replay is a follow-up)");

        uint256 deployerKey = vm.envUint("DEPLOYMENT_KEY");
        vm.broadcast(deployerKey);
        address proxy = ISafeProxyFactory(factory)
            .createProxyWithNonce(singleton, LibStoxSafeGenesis.GENESIS_SETUP, LibStoxSafeGenesis.GENESIS_SALT_NONCE);

        if (proxy != expected) revert UnexpectedSafeAddress(expected, proxy);

        console2.log("Deployed matched-address Safe at:", proxy);
        console2.log("NEXT: run the state-alignment replay (upgrade to v1.4.1, add owners, set threshold 3).");
    }
}
