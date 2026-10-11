// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {console2} from "forge-std-1.16.2/src/console2.sol";
import {IAccessControl} from "@openzeppelin-contracts-5.6.1/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {LibRainDeploy} from "rain-deploy-0.1.11/src/lib/LibRainDeploy.sol";
import {LibDecimalFloat} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {EvaluableV4, SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";
import {IInterpreterV4} from "rainlang-interface-0.2.9/src/interface/IInterpreterV4.sol";
import {IInterpreterStoreV3} from "rainlang-interface-0.2.9/src/interface/IInterpreterStoreV3.sol";
import {IParserV2} from "rainlang-interface-0.2.9/src/interface/IParserV2.sol";
import {
    LibTestInterpreterDeploy,
    TEST_STORE_ADDRESS,
    TEST_INTERPRETER_ADDRESS,
    TEST_EXPRESSION_DEPLOYER_ADDRESS
} from "rainlang-0.2.12/test/lib/deploy/LibTestInterpreterDeploy.sol";
import {OffchainAssetReceiptVault} from "rain-vats-0.2.1/src/concrete/vault/OffchainAssetReceiptVault.sol";

import {ST0xOrchestrator} from "../../src/concrete/ST0xOrchestrator.sol";
import {St0xAttestSubParser} from "../../src/concrete/St0xAttestSubParser.sol";
import {MintAuthV1, Digest} from "../../src/interface/IST0xOrchestratorV1.sol";
import {LibOrchestratorInvariants} from "../../src/lib/LibOrchestratorInvariants.sol";
import {LibAuthoriserInvariants} from "../../src/lib/LibAuthoriserInvariants.sol";
import {LibSafeInvariants} from "../../src/lib/LibSafeInvariants.sol";
import {LibTimelockInvariants} from "../../src/lib/LibTimelockInvariants.sol";
import {LibTokenInvariants, TokenInstance} from "../../src/lib/LibTokenInvariants.sol";
import {LibStoxDeployNetworks} from "../../src/lib/LibStoxDeployNetworks.sol";
import {BootstrapMintCapsOrchestratorHarness} from "./BootstrapMintCapsOrchestratorHarness.sol";

/// @notice The mint-caps orchestrator rollout, per chain, on a fork of live
/// state: the Safe bundle deploys it and schedules its bootstrap, the batch
/// executes after the timelock delay, then a production token is minted
/// through the new orchestrator and through the live one, each delivering.
contract BootstrapMintCapsOrchestratorProdTest is Test {
    using Strings for address;

    uint256 internal constant AMOUNT = 1e18;

    /// @notice A production receipt vault on the active chain.
    function productionToken() internal view returns (address) {
        TokenInstance[] memory tokens;
        if (block.chainid == LibSafeInvariants.BASE_CHAIN_ID) {
            tokens = LibTokenInvariants.productionTokensBase();
        } else if (block.chainid == LibSafeInvariants.ETHEREUM_CHAIN_ID) {
            tokens = LibTokenInvariants.productionTokensEthereum();
        } else if (block.chainid == LibSafeInvariants.HYPEREVM_CHAIN_ID) {
            tokens = LibTokenInvariants.productionTokensHyperEvm();
        } else if (block.chainid == LibSafeInvariants.ROBINHOOD_CHAIN_ID) {
            tokens = LibTokenInvariants.productionTokensRobinhood();
        } else {
            tokens = LibTokenInvariants.productionTokensBsc();
        }
        return tokens[0].receiptVault;
    }

    /// @notice An identity weighting, `mint-amount`, parsed on the fork
    /// against a Rainlang and subparser placed there for the test.
    function identityWeighting() internal returns (EvaluableV4 memory) {
        LibTestInterpreterDeploy.etchTestRainlang(vm);
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        bytes memory rainlang =
            bytes(string.concat("using-words-from ", address(subParser).toHexString(), "\n_: mint-amount();"));
        return EvaluableV4({
            interpreter: IInterpreterV4(TEST_INTERPRETER_ADDRESS),
            store: IInterpreterStoreV3(TEST_STORE_ADDRESS),
            bytecode: IParserV2(TEST_EXPRESSION_DEPLOYER_ADDRESS).parse2(rainlang)
        });
    }

    /// @notice Grant `role` to `account` from whichever of the Safe and the
    /// timelock administers it, if `account` lacks it.
    function ensureRole(address target, bytes32 role, address account) internal {
        IAccessControl acl = IAccessControl(target);
        if (acl.hasRole(role, account)) return;
        bytes32 admin = acl.getRoleAdmin(role);
        address safe = LibSafeInvariants.safeForChainId(block.chainid);
        address holder = acl.hasRole(admin, safe) ? safe : LibTimelockInvariants.timelockForChainId(block.chainid);
        vm.prank(holder);
        acl.grantRole(role, account);
    }

    function signedAuth(address orchestrator, address token, address to, bytes32 nonce, uint256 pk)
        internal
        view
        returns (MintAuthV1 memory)
    {
        Digest digest = ST0xOrchestrator(payable(orchestrator)).mintAuthDigest(token, to, AMOUNT, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, Digest.unwrap(digest));
        return MintAuthV1({nonce: nonce, signature: abi.encodePacked(r, s, v)});
    }

    /// @notice Run the bootstrap script on the fork: deploy, schedule, wait
    /// out the delay, execute from a roleless address and assert the
    /// bootstrapped state. Returns the mint-caps instance.
    function bootstrap(address recipient) internal returns (address mintCaps) {
        BootstrapMintCapsOrchestratorHarness script = new BootstrapMintCapsOrchestratorHarness();
        script.configure(
            identityWeighting(),
            LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C,
            recipient,
            LibDecimalFloat.packLossless(1000, 0),
            LibDecimalFloat.packLossless(1, 0)
        );
        script.run();
        mintCaps = LibOrchestratorInvariants.mintCapsInstance();
    }

    /// @notice The first production token on the active chain, certified so
    /// it accepts mints.
    function certifiedProductionToken() internal returns (address token) {
        token = productionToken();
        if (OffchainAssetReceiptVault(payable(token)).isCertificationExpired()) {
            vm.prank(LibSafeInvariants.safeForChainId(block.chainid));
            OffchainAssetReceiptVault(payable(token)).certify(block.timestamp + 1 days, false, "");
        }
    }

    /// @notice Mint `AMOUNT` of `token` to `recipient` through the mint-caps
    /// orchestrator.
    function mintThroughMintCaps(address mintCaps, address token, address recipient, uint256 pk) internal {
        MintAuthV1 memory auth = signedAuth(mintCaps, token, recipient, keccak256("mint-caps"), pk);
        vm.prank(LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C);
        ST0xOrchestrator(payable(mintCaps)).mint(token, recipient, AMOUNT, auth, "", new SignedContextV1[](0));
    }

    /// @notice Mint `AMOUNT` of `token` to `recipient` through the live
    /// orchestrator, with its 0.1.30 `mint` selector. Where its path is not
    /// enabled on the chain yet, the test enables it as its rollout would.
    function mintThroughLive(address token, address recipient, uint256 pk) internal {
        address live = LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE;
        address minter = LibAuthoriserInvariants.GRANTEE_SERVICE_3D0C;
        address authoriser = LibAuthoriserInvariants.activeChainAuthoriser();
        ensureRole(authoriser, keccak256("DEPOSIT"), live);
        ensureRole(authoriser, keccak256("WITHDRAW"), live);
        ensureRole(live, keccak256("MINT"), minter);
        MintAuthV1 memory auth = signedAuth(live, token, recipient, keccak256("live"), pk);
        vm.prank(minter);
        (bool ok, bytes memory ret) = live.call(
            abi.encodeWithSignature(
                "mint(address,address,uint256,(bytes32,bytes),bytes)", token, recipient, AMOUNT, auth, bytes("")
            )
        );
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    function assertDeployBootstrapMint(string memory label, uint256 chainId) internal {
        assertEq(block.chainid, chainId, string.concat(label, ": fork"));
        (address recipient, uint256 pk) = makeAddrAndKey("mint-caps-recipient");

        address mintCaps = bootstrap(recipient);
        assertTrue(
            mintCaps != LibOrchestratorInvariants.ST0X_ORCHESTRATOR_INSTANCE, string.concat(label, ": a fresh instance")
        );

        address token = certifiedProductionToken();
        uint256 before = IERC20(token).balanceOf(recipient);

        mintThroughMintCaps(mintCaps, token, recipient, pk);
        assertEq(IERC20(token).balanceOf(recipient), before + AMOUNT, string.concat(label, ": mint-caps mint"));

        mintThroughLive(token, recipient, pk);
        assertEq(IERC20(token).balanceOf(recipient), before + 2 * AMOUNT, string.concat(label, ": live mint"));
        console2.log(string.concat("[", label, "] mint-caps orchestrator:"), mintCaps);
    }

    function testDeployBootstrapMintBase() external {
        vm.createSelectFork(LibRainDeploy.BASE);
        assertDeployBootstrapMint("base", LibSafeInvariants.BASE_CHAIN_ID);
    }

    function testDeployBootstrapMintEthereum() external {
        vm.createSelectFork(LibStoxDeployNetworks.ETHEREUM);
        assertDeployBootstrapMint("ethereum", LibSafeInvariants.ETHEREUM_CHAIN_ID);
    }

    function testDeployBootstrapMintHyperEvm() external {
        vm.createSelectFork(LibStoxDeployNetworks.HYPEREVM);
        assertDeployBootstrapMint("hyperevm", LibSafeInvariants.HYPEREVM_CHAIN_ID);
    }

    function testDeployBootstrapMintRobinhood() external {
        vm.createSelectFork(LibStoxDeployNetworks.ROBINHOOD);
        assertDeployBootstrapMint("robinhood", LibSafeInvariants.ROBINHOOD_CHAIN_ID);
    }

    function testDeployBootstrapMintBsc() external {
        vm.createSelectFork(LibStoxDeployNetworks.BSC);
        assertDeployBootstrapMint("bsc", LibSafeInvariants.BSC_CHAIN_ID);
    }
}
