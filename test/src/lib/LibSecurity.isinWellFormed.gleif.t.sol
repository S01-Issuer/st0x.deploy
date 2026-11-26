// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test, console} from "forge-std-1.17.0/src/Test.sol";
import {LibBytes} from "rain-solmem-0.1.28/src/lib/LibBytes.sol";
import {LibMemCpy} from "rain-solmem-0.1.28/src/lib/LibMemCpy.sol";
import {LibPointer, Pointer} from "rain-solmem-0.1.28/src/lib/LibPointer.sol";
import {LibSecurity} from "../../../src/lib/LibSecurity.sol";

contract LibSecurityIsinWellFormedGleifTest is Test {
    using LibPointer for Pointer;

    /// Every 100th ISIN, as all ~9.5M overflow forge's 128 MiB EVM memory limit.
    function testIsinAcceptsEveryHundredthGleifIsin() external view {
        bytes memory isins = vm.readFileBinary("test/fixture/gleif/every-100th-isin.txt");
        uint256 checked = 0;
        uint256 rejected = 0;
        for (uint256 start = 0; start < isins.length; checked++) {
            uint256 end = start;
            while (end < isins.length && isins[end] != "\n") end++;
            Pointer freeMemory = LibPointer.allocatedMemoryPointer();
            bytes memory isin = new bytes(end - start);
            LibMemCpy.unsafeCopyBytesTo(
                LibBytes.dataPointer(isins).unsafeAddBytes(start), LibBytes.dataPointer(isin), isin.length
            );
            if (!LibSecurity.isinWellFormed(string(isin))) {
                console.log("rejected", string(isin));
                rejected++;
            }
            assembly ("memory-safe") {
                mstore(0x40, freeMemory)
            }
            start = end + 1;
        }
        console.log("checked", checked, "rejected", rejected);
        assertGt(checked, 50_000);
        assertEq(rejected, 0);
    }
}
