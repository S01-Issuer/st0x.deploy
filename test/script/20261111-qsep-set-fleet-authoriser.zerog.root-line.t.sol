// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {QsepSetFleetAuthoriserRecorded} from "../../script/20261111-qsep-set-fleet-authoriser.s.sol";
import {LibStoxMigrations} from "../../src/lib/LibStoxMigrations.sol";
import {IRecordScriptHooks} from "../lib/RootLineRecordScriptTest.sol";
import {QsepSetFleetAuthoriserHarness} from "./QsepSetFleetAuthoriserHarness.sol";
import {ZerogRootLineScriptTest} from "./ZerogRootLineScriptTest.sol";

/// @title QsepSetFleetAuthoriserZerogRootLineTest
/// @notice The tQSEP migration on 0G, onto the revoke's execution record: 0G has no tQSEP vault, so the bundle is the
/// record alone, as on every chain but Base.
contract QsepSetFleetAuthoriserZerogRootLineTest is ZerogRootLineScriptTest {
    function newScript() internal override returns (IRecordScriptHooks) {
        return IRecordScriptHooks(address(new QsepSetFleetAuthoriserHarness("zerog-root-line")));
    }

    function declaredId() internal pure override returns (bytes32) {
        return LibStoxMigrations.QSEP_SET_FLEET_AUTHORISER;
    }

    function declaredOnto() internal pure override returns (bytes32) {
        return LibStoxMigrations.EXECUTE_REVOKE_SERVICE_SIGNER;
    }

    function ownRecordPreflightRefusal() internal pure override returns (bytes memory) {
        return abi.encodeWithSelector(QsepSetFleetAuthoriserRecorded.selector, declaredId());
    }
}
