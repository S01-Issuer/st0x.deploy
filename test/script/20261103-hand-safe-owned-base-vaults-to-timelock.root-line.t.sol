// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Enum} from "safe-global-safe-smart-account-1.4.1-3/contracts/common/Enum.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {SafeTx} from "rain-deploy-0.1.30/src/lib/LibSafeTx.sol";

import {HandSafeOwnedBaseVaultsToTimelockRootLineTest} from "./HandSafeOwnedBaseVaultsToTimelockRootLineTest.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants} from "../../src/lib/LibTokenInvariants.sol";

/// @title HandSafeOwnedBaseVaultsToTimelockBaseRootLineTest
/// @notice On Base the six Safe-owned vaults move before the record.
contract HandSafeOwnedBaseVaultsToTimelockBaseRootLineTest is HandSafeOwnedBaseVaultsToTimelockRootLineTest {
    function network() internal pure override returns (string memory) {
        return LibRainDeploy.BASE;
    }

    function testBundleIsTheSixTransfersThenTheRecord() external view {
        address[6] memory vaults = [
            LibTokenInvariants.WMT_RECEIPT_VAULT,
            LibTokenInvariants.MC_RECEIPT_VAULT,
            LibTokenInvariants.DIS_RECEIPT_VAULT,
            LibTokenInvariants.IFX_RECEIPT_VAULT,
            LibTokenInvariants.SOI_RECEIPT_VAULT,
            LibTokenInvariants.TPRO_RECEIPT_VAULT
        ];
        SafeTx[] memory txs = sScript.callAuthorBundle();
        assertEq(txs.length, vaults.length + 1, "six transfers then the record");
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(txs[i].to, vaults[i], "transfer target");
            assertEq(txs[i].value, 0, "transfer value");
            assertEq(
                txs[i].data,
                abi.encodeCall(Ownable.transferOwnership, (LibTimelockInvariants.timelockForChainId(block.chainid))),
                "transfer calldata"
            );
            assertEq(uint8(txs[i].operation), uint8(Enum.Operation.Call), "transfer operation");
        }
    }
}
