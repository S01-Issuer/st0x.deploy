// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {OwnerManager} from "safe-global-safe-smart-account-1.4.1-3/contracts/base/OwnerManager.sol";
import {LibSafe} from "rain-deploy-0.1.38/src/lib/LibSafe.sol";
import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";
import {LibSafeTxBuilderJson} from "rain-deploy-0.1.38/src/lib/LibSafeTxBuilderJson.sol";

import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {RootLineRecordScriptTest} from "../lib/RootLineRecordScriptTest.sol";
import {ZerogRootLineFixture} from "./ZerogRootLineFixture.sol";

/// @dev The script's own entry point and where it writes its artifact.
interface IRunnableRecordScript {
    function run() external returns (bytes32);

    function callArtifactPath() external view returns (string memory);
}

/// @title ZerogRootLineScriptTest
/// @notice `RootLineRecordScriptTest` for a 0G arm on `ZerogRootLineFixture`: before the onto, the line walked to the
/// migration before it; the onto landed as the fixture lands it.
abstract contract ZerogRootLineScriptTest is ZerogRootLineFixture, RootLineRecordScriptTest {
    function landBeforeOnto() internal virtual override {
        landZerogTokensBeforeRecord();
        if (declaredOnto() == LibStoxMigrations.CREATE_ZEROG_TOKENS) return;
        landZerogTokenRecord();
        landZerogLineBefore(declaredOnto());
    }

    function landOnto() internal virtual override {
        if (declaredOnto() == LibStoxMigrations.CREATE_ZEROG_TOKENS) {
            landZerogTokenRecord();
        } else {
            landZerogLineThrough(declaredOnto());
        }
    }

    function testZerogBundleIsTheRecordAlone() external view {
        assertEq(block.chainid, LibSafeInvariants.ZEROG_CHAIN_ID, "on 0G");
        assertEq(sScript.callAuthorBundle().length, 1, "record alone");
    }

    /// `run()`, as `run-script` dispatches it on 0G: the record alone through the Safe, the post-state, the 0G
    /// reversibility proof, and the record alone as the artifact.
    function testZerogRunWritesTheRecordAlone() external {
        IRunnableRecordScript script = IRunnableRecordScript(address(sScript));
        script.run();
        assertEq(LibStoxMigrations.head(), declaredId(), "recorded");
        (,, SafeTx[] memory txs) = LibSafeTxBuilderJson.fromJson(vm, vm.readFile(script.callArtifactPath()));
        assertEq(txs.length, 1, "record alone");
        SafeTx memory record = LibStoxMigrations.recordTx(declared());
        assertEq(txs[0].to, record.to, "registry");
        assertEq(txs[0].data, record.data, "record calldata");
    }

    /// The 0G Safe is at threshold 1 until #620's rollout raises it: the arm refuses it until then.
    function testZerogPreflightRefusesASafeOffPolicy() external {
        vm.mockCall(safeAddress(), abi.encodeCall(OwnerManager.getThreshold, ()), abi.encode(uint256(1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                LibSafe.SafeThresholdMismatch.selector,
                safeAddress(),
                LibSafeInvariants.STOX_TOKEN_OWNER_SAFE_THRESHOLD,
                1
            )
        );
        sScript.callPreflight();
    }
}
