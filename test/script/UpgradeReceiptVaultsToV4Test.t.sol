// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

import {UpgradeReceiptVaultsToV4, V4ImplementationNotDeployed} from "../../script/UpgradeReceiptVaultsToV4.s.sol";
import {IGnosisSafe} from "../../src/interface/IGnosisSafe.sol";
import {LibProdAuthoriser} from "../../src/lib/LibProdAuthoriser.sol";
import {LibProdDeployV1} from "../../src/lib/LibProdDeployV1.sol";
import {LibProdDeployV4} from "../../src/lib/LibProdDeployV4.sol";
import {LibProdSafes} from "../../src/lib/LibProdSafes.sol";
import {LibRainDeploy} from "rain-deploy-0.1.3/src/lib/LibRainDeploy.sol";

/// @title UpgradeReceiptVaultsToV4Test
/// @notice Fork tests for the V4 receipt-vault upgrade + authoriser-swap
/// script. Two halves:
///
/// 1. **Placeholder-posture guards** (always run): assert that the V4 pointers
///    in `LibProdDeployV4` and the V4 authoriser clone in `LibProdAuthoriser`
///    are still `address(0)` / `bytes32(0)` placeholders. The instant any of
///    those is hydrated with a real value, the guard fails and the second
///    half (currently a TODO skeleton) must be authored to cover the live
///    values.
///
/// 2. **Hydrated end-to-end coverage** (TODO): the V3 predecessor
///    (`UpgradeReceiptVaultToV3Test.t.sol`, replaced by this rename) carried
///    happy-path + inverted coverage that planted the impl via `deployCodeTo`
///    and simulated the beacon-ownership migration. None of that is
///    portable against `address(0)` constants — `deployCodeTo(_, address(0))`
///    is a no-op. Once the patched rain.vats tag lands, the `RAIN_VATS_TBD`
///    suffix is renamed, and real addresses replace the zeros, port the V3
///    suite here and re-add: planted-codehash sanity, happy-path artifact
///    write + bundle-shape pin, snapshot/restore = pre-upgrade pin, and
///    inverted cases for every error path the script declares (every
///    `V4*` error in `UpgradeReceiptVaultsToV4.s.sol`).
///
/// While the placeholders are in place, `run()` reverts on the first
/// placeholder check it reaches; the third test below asserts that revert
/// path is `V4ImplementationNotDeployed(address(0))`.
///
/// @dev Uses an unpinned Base head fork (same precedent as the other Safe
/// fork tests in this repo).
contract UpgradeReceiptVaultsToV4Test is Test {
    UpgradeReceiptVaultsToV4 internal script;
    IGnosisSafe internal safe;

    address internal constant BEACON = LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1;

    function selectBaseFork() internal {
        vm.createSelectFork(LibRainDeploy.BASE);
        script = new UpgradeReceiptVaultsToV4();
        safe = IGnosisSafe(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice Simulate the beacon-ownership migration (#196) landing on-chain:
    /// prank the EOA owner and transfer the receipt vault beacon to the Safe.
    /// The script's pre-flight requires the beacon to be Safe-owned before it
    /// reaches the V4 impl checks.
    function simulateBeaconOwnershipMigration() internal {
        vm.prank(LibProdSafes.BEACON_PRE_MIGRATION_OWNER);
        Ownable(BEACON).transferOwnership(LibProdSafes.STOX_TOKEN_OWNER_SAFE);
    }

    /// @notice Placeholder-posture guard: `LibProdDeployV4`'s V4 impl pointer
    /// is still `address(0)`. The instant this fails, the lib has been
    /// hydrated and the hydrated end-to-end test suite must be authored.
    function testV4ImplPointerStillPlaceholder() external pure {
        assertEq(
            LibProdDeployV4.STOX_RECEIPT_VAULT_RAIN_VATS_TBD,
            address(0),
            "V4 receipt vault impl pointer hydrated - write the hydrated test suite"
        );
        assertEq(
            LibProdDeployV4.STOX_RECEIPT_VAULT_CODEHASH_RAIN_VATS_TBD,
            bytes32(0),
            "V4 receipt vault codehash hydrated - write the hydrated test suite"
        );
    }

    /// @notice Placeholder-posture guard: `LibProdAuthoriser`'s V4 clone
    /// pointer is still `address(0)`. The instant this fails, the clone has
    /// been deployed and pinned and the hydrated end-to-end test suite must
    /// be authored.
    function testV4AuthoriserClonePointerStillPlaceholder() external pure {
        assertEq(
            LibProdAuthoriser.STOX_PROD_AUTHORISER_V4_CLONE,
            address(0),
            "V4 authoriser clone hydrated - write the hydrated test suite"
        );
        assertEq(
            LibProdAuthoriser.STOX_PROD_AUTHORISER_V4_CLONE_CODEHASH,
            bytes32(0),
            "V4 authoriser clone codehash hydrated - write the hydrated test suite"
        );
    }

    /// @notice With every V4 placeholder still at zero, `run()` must trip the
    /// first hard-fail check it reaches after the Safe + beacon invariants
    /// pass: `V4ImplementationNotDeployed(address(0))`. The beacon-ownership
    /// migration is simulated first so the script's `assertBeaconInvariants`
    /// passes and the V4 impl check is reached.
    function testRunRevertsOnUnhydratedV4ImplPlaceholder() external {
        selectBaseFork();
        simulateBeaconOwnershipMigration();
        vm.expectRevert(abi.encodeWithSelector(V4ImplementationNotDeployed.selector, address(0)));
        script.run();
    }
}
