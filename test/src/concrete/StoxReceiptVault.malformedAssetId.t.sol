// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin-contracts-5.7.0/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxTokenConfigV1, STOX_TOKEN_CONFIG_V1_TAG} from "../../../src/interface/IStoxTokenConfigV1.sol";
import {MalformedAssetId} from "../../../src/error/ErrStoxTokenConfig.sol";
import {Region} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibUnderlying} from "../../../src/lib/LibUnderlying.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";

contract StoxReceiptVaultMalformedAssetIdTest is Test {
    UpgradeableBeacon internal beacon;

    function setUp() external {
        deployCodeTo(
            "src/concrete/StoxCorporateActionsFacet.sol:StoxCorporateActionsFacet",
            LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE
        );
        beacon = new UpgradeableBeacon(address(new StoxReceiptVault()), address(this));
    }

    function initData(string memory assetId) internal pure returns (bytes memory) {
        return abi.encode(
            STOX_TOKEN_CONFIG_V1_TAG,
            StoxTokenConfigV1({
                assetId: assetId,
                listingTicker: "AAPL",
                listingName: "Apple Inc.",
                region: Region.US,
                authority: address(0),
                rbacName: bytes32(0),
                receiptBeaconName: bytes32(0),
                metadata: ""
            })
        );
    }

    function assertInitializeRefuses(string memory assetId) internal {
        StoxReceiptVault vault = StoxReceiptVault(payable(address(new BeaconProxy(address(beacon), ""))));
        vm.expectRevert(abi.encodeWithSelector(MalformedAssetId.selector, assetId));
        vault.initialize(initData(assetId));
    }

    function testInitializeRefusesAMalformedAssetIdCarryingIt() external {
        assertInitializeRefuses("");
        assertInitializeRefuses("ST0XTESTUS");
        assertInitializeRefuses("US0378331006");
        assertInitializeRefuses("us0378331005");
        assertInitializeRefuses("US03783310051");
    }

    function testFuzzInitializeRefusesAMalformedAssetIdCarryingIt(string memory assetId) external {
        vm.assume(!LibUnderlying.isinWellFormed(assetId));
        assertInitializeRefuses(assetId);
    }
}
