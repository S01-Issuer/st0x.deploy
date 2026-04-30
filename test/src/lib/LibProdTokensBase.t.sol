// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std/Test.sol";
import {LibProdTokensBase} from "../../../src/lib/LibProdTokensBase.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibTestProd} from "../../lib/LibTestProd.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IReceiptVaultV3} from "rain.vats/interface/IReceiptVaultV3.sol";
import {
    IOffchainAssetReceiptVaultBeaconSetDeployerV1
} from "rain.vats/interface/IOffchainAssetReceiptVaultBeaconSetDeployerV1.sol";
import {
    ERC1967_BEACON_SLOT,
    LibExtrospectERC1967BeaconProxy
} from "rain.extrospection/lib/LibExtrospectERC1967BeaconProxy.sol";

/// @title LibProdTokensBaseTest
/// @notice Fork tests verifying production token instances on Base.
contract LibProdTokensBaseTest is Test {
    /// Read the EIP-1967 beacon address from a proxy contract.
    function beaconOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_BEACON_SLOT))));
    }

    /// Verify a token set (receipt, receipt vault, wrapped vault) is deployed,
    /// wired correctly, and behind the expected beacons on the current fork.
    function checkTokenSet(
        address receipt,
        address receiptVault,
        address wrappedTokenVault,
        string memory expectedReceiptVaultSymbol,
        string memory expectedWrappedVaultSymbol
    ) internal view {
        assertTrue(receipt.code.length > 0, "receipt not deployed");
        assertTrue(receiptVault.code.length > 0, "receipt vault not deployed");
        assertTrue(wrappedTokenVault.code.length > 0, "wrapped vault not deployed");

        assertEq(IERC20Metadata(receiptVault).symbol(), expectedReceiptVaultSymbol);
        assertEq(IERC20Metadata(wrappedTokenVault).symbol(), expectedWrappedVaultSymbol);
        assertEq(IERC4626(wrappedTokenVault).asset(), receiptVault, "wrapped vault asset mismatch");
        assertEq(address(IReceiptVaultV3(payable(receiptVault)).receipt()), receipt, "receipt address mismatch");

        // All prod tokens on Base are behind the V1 OARV deployer's beacons.
        IOffchainAssetReceiptVaultBeaconSetDeployerV1 oarvDeployer = IOffchainAssetReceiptVaultBeaconSetDeployerV1(
            LibProdDeployV1.OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON_SET_DEPLOYER
        );
        address receiptBeacon = address(oarvDeployer.I_RECEIPT_BEACON());
        address receiptVaultBeacon = address(oarvDeployer.I_OFFCHAIN_ASSET_RECEIPT_VAULT_BEACON());
        // The wrapped vault beacon is not exposed by any deployer getter,
        // so read it from the proxy's slot. All wrapped proxies share the
        // same beacon, pinned via the MSTR check below.
        address wrappedVaultBeacon = beaconOf(LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT);

        assertEq(beaconOf(receipt), receiptBeacon, "receipt beacon mismatch");
        assertEq(beaconOf(receiptVault), receiptVaultBeacon, "receipt vault beacon mismatch");
        assertEq(beaconOf(wrappedTokenVault), wrappedVaultBeacon, "wrapped vault beacon mismatch");

        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                receiptBeacon, LibProdDeployV1.PROD_STOX_RECEIPT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            "receipt beacon impl codehash mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                receiptVaultBeacon, LibProdDeployV1.PROD_STOX_RECEIPT_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            "receipt vault beacon impl codehash mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconImplementationBytecode(
                wrappedVaultBeacon, LibProdDeployV1.PROD_STOX_WRAPPED_TOKEN_VAULT_IMPLEMENTATION_BASE_CODEHASH_V1
            ),
            "wrapped vault beacon impl codehash mismatch"
        );

        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(receiptBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            "receipt beacon owner mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(receiptVaultBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            "receipt vault beacon owner mismatch"
        );
        assertTrue(
            LibExtrospectERC1967BeaconProxy.isBeaconOwner(wrappedVaultBeacon, LibProdDeployV1.BEACON_INITIAL_OWNER),
            "wrapped vault beacon owner mismatch"
        );
    }

    function testMstrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.MSTR_RECEIPT,
            LibProdTokensBase.MSTR_RECEIPT_VAULT,
            LibProdTokensBase.MSTR_WRAPPED_TOKEN_VAULT,
            "tMSTR",
            "wtMSTR"
        );
    }

    function testTslaTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.TSLA_RECEIPT,
            LibProdTokensBase.TSLA_RECEIPT_VAULT,
            LibProdTokensBase.TSLA_WRAPPED_TOKEN_VAULT,
            "tTSLA",
            "wtTSLA"
        );
    }

    function testCoinTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.COIN_RECEIPT,
            LibProdTokensBase.COIN_RECEIPT_VAULT,
            LibProdTokensBase.COIN_WRAPPED_TOKEN_VAULT,
            "tCOIN",
            "wtCOIN"
        );
    }

    function testSpymTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.SPYM_RECEIPT,
            LibProdTokensBase.SPYM_RECEIPT_VAULT,
            LibProdTokensBase.SPYM_WRAPPED_TOKEN_VAULT,
            "tSPYM",
            "wtSPYM"
        );
    }

    function testSivrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.SIVR_RECEIPT,
            LibProdTokensBase.SIVR_RECEIPT_VAULT,
            LibProdTokensBase.SIVR_WRAPPED_TOKEN_VAULT,
            "tSIVR",
            "wtSIVR"
        );
    }

    function testCrclTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.CRCL_RECEIPT,
            LibProdTokensBase.CRCL_RECEIPT_VAULT,
            LibProdTokensBase.CRCL_WRAPPED_TOKEN_VAULT,
            "tCRCL",
            "wtCRCL"
        );
    }

    function testNvdaTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.NVDA_RECEIPT,
            LibProdTokensBase.NVDA_RECEIPT_VAULT,
            LibProdTokensBase.NVDA_WRAPPED_TOKEN_VAULT,
            "tNVDA",
            "wtNVDA"
        );
    }

    function testIauTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.IAU_RECEIPT,
            LibProdTokensBase.IAU_RECEIPT_VAULT,
            LibProdTokensBase.IAU_WRAPPED_TOKEN_VAULT,
            "tIAU",
            "wtIAU"
        );
    }

    function testPpltTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.PPLT_RECEIPT,
            LibProdTokensBase.PPLT_RECEIPT_VAULT,
            LibProdTokensBase.PPLT_WRAPPED_TOKEN_VAULT,
            "tPPLT",
            "wtPPLT"
        );
    }

    function testAmznTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.AMZN_RECEIPT,
            LibProdTokensBase.AMZN_RECEIPT_VAULT,
            LibProdTokensBase.AMZN_WRAPPED_TOKEN_VAULT,
            "tAMZN",
            "wtAMZN"
        );
    }

    function testBmnrTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.BMNR_RECEIPT,
            LibProdTokensBase.BMNR_RECEIPT_VAULT,
            LibProdTokensBase.BMNR_WRAPPED_TOKEN_VAULT,
            "tBMNR",
            "wtBMNR"
        );
    }

    function testIbhgTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.IBHG_RECEIPT,
            LibProdTokensBase.IBHG_RECEIPT_VAULT,
            LibProdTokensBase.IBHG_WRAPPED_TOKEN_VAULT,
            "tIBHG",
            "wtIBHG"
        );
    }

    function testSgovTokenSetOnBase() external {
        LibTestProd.createSelectForkBase(vm);
        checkTokenSet(
            LibProdTokensBase.SGOV_RECEIPT,
            LibProdTokensBase.SGOV_RECEIPT_VAULT,
            LibProdTokensBase.SGOV_WRAPPED_TOKEN_VAULT,
            "tSGOV",
            "wtSGOV"
        );
    }
}
