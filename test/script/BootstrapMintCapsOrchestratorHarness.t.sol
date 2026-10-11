// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Float, LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {EvaluableV4} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";
import {IInterpreterV4} from "rainlang-interface-0.2.9/src/interface/IInterpreterV4.sol";
import {IInterpreterStoreV3} from "rainlang-interface-0.2.9/src/interface/IInterpreterStoreV3.sol";

import {
    BootstrapMintCapsOrchestratorHarness,
    HarnessMinterZero,
    HarnessRecipientZero
} from "./BootstrapMintCapsOrchestratorHarness.sol";

/// @notice The bootstrap harness refuses a zero minter or recipient, so the
/// config it hands the script never names address zero.
contract BootstrapMintCapsOrchestratorHarnessConfigureTest is Test {
    function weighting() internal pure returns (EvaluableV4 memory) {
        return EvaluableV4({
            interpreter: IInterpreterV4(address(0x1)), store: IInterpreterStoreV3(address(0x2)), bytecode: hex"00"
        });
    }

    function testFuzzConfigureRefusesZeroMinter(address recipient) external {
        BootstrapMintCapsOrchestratorHarness harness = new BootstrapMintCapsOrchestratorHarness();
        Float one = LibDecimalFloat.packLossless(1, 0);
        EvaluableV4 memory w = weighting();
        vm.expectRevert(abi.encodeWithSelector(HarnessMinterZero.selector));
        harness.configure(w, address(0), recipient, one, one);
    }

    function testFuzzConfigureRefusesZeroRecipient(address minter) external {
        vm.assume(minter != address(0));
        BootstrapMintCapsOrchestratorHarness harness = new BootstrapMintCapsOrchestratorHarness();
        Float one = LibDecimalFloat.packLossless(1, 0);
        EvaluableV4 memory w = weighting();
        vm.expectRevert(abi.encodeWithSelector(HarnessRecipientZero.selector));
        harness.configure(w, minter, address(0), one, one);
    }

    function testFuzzConfigureAcceptsNonZeroAccounts(address minter, address recipient) external {
        vm.assume(minter != address(0) && recipient != address(0));
        BootstrapMintCapsOrchestratorHarness harness = new BootstrapMintCapsOrchestratorHarness();
        Float one = LibDecimalFloat.packLossless(1, 0);
        harness.configure(weighting(), minter, recipient, one, one);
    }
}
