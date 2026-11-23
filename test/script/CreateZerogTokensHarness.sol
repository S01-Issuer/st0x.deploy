// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {SafeTx} from "rain-deploy-0.1.38/src/lib/LibSafeTx.sol";

import {CreateZerogTokens} from "../../script/20261119-create-zerog-tokens.s.sol";
import {TokenConfig} from "../../src/lib/LibProdTokenConfig.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";

/// @dev 0G's token table as the bundles were authored against it, before the tokens existed: the shipped table's
/// underlyings in its order, with every leg a placeholder.
/// @return table The placeholder table.
function zerogPlaceholderTable() pure returns (TokenInstance[] memory table) {
    TokenInstance[] memory shipped = LibTokenInvariants.productionTokensZerog();
    table = new TokenInstance[](shipped.length);
    for (uint256 i = 0; i < shipped.length; i++) {
        table[i] = TokenInstance(shipped[i].underlying, address(0), address(0), address(0));
    }
}

/// @dev Exposes the script's hooks; tags the artifact path because `run()` rewrites it and tests run in parallel.
/// It overrides no address, so the tests run the Safe and timelock pins the script ships with. The tests rebuild 0G as
/// it was before the tokens existed, so by default the harness stands in `zerogPlaceholderTable` for the shipped
/// table, which holds the created tokens; `setTable` stands in any other table, and `callShippedTable` reads the
/// script's own.
contract CreateZerogTokensHarness is CreateZerogTokens {
    string internal sArtifactTag;
    TokenInstance[] internal sTable;
    bool internal sTableSet;

    constructor(string memory artifactTag) {
        sArtifactTag = artifactTag;
    }

    /// @inheritdoc CreateZerogTokens
    function artifactPath() internal view override returns (string memory) {
        return vm.replace(super.artifactPath(), ".json", string.concat("-", sArtifactTag, ".json"));
    }

    /// @dev Stands `table` in for 0G's token table.
    function setTable(TokenInstance[] memory table) external {
        delete sTable;
        for (uint256 i = 0; i < table.length; i++) {
            sTable.push(table[i]);
        }
        sTableSet = true;
    }

    /// @inheritdoc CreateZerogTokens
    function zerogTable() internal view override returns (TokenInstance[] memory) {
        return sTableSet ? sTable : zerogPlaceholderTable();
    }

    /// @dev The table the script itself reads, whatever the harness stands in.
    function callShippedTable() external view returns (TokenInstance[] memory) {
        return super.zerogTable();
    }

    function callPreflight() external view {
        preflight();
    }

    function callAuthorBundle() external view returns (SafeTx[] memory) {
        return authorBundle();
    }

    function callAssertPostState() external view {
        assertPostState();
    }

    function callCreatedCount() external view returns (uint256) {
        return createdCount(configs().length);
    }

    function callToken(uint256 i) external view returns (TokenInstance memory) {
        return token(configs()[i], i);
    }

    function callConfigs() external view returns (TokenConfig[] memory) {
        return configs();
    }

    function callRowToken(TokenConfig memory row, uint256 i) external pure returns (TokenInstance memory) {
        return token(row, i);
    }

    function callAuthoriserFor(TokenConfig memory row) external view returns (address) {
        return authoriserFor(row);
    }

    function callArtifactPath() external view returns (string memory) {
        return artifactPath();
    }
}
