// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {BeaconProxy} from "@openzeppelin-contracts-5.7.0/proxy/beacon/BeaconProxy.sol";
import {TimelockController} from "@openzeppelin-contracts-5.7.0/governance/TimelockController.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {ECDSA} from "@openzeppelin-contracts-5.7.0/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin-contracts-5.7.0/utils/cryptography/MessageHashUtils.sol";
import {IAuthorizeV1} from "rain-vats-0.2.20/src/interface/IAuthorizeV1.sol";
import {CloneFactory} from "rain-factory-deploy-0.2.8/src/concrete/CloneFactory.sol";
import {LibRainDeploy} from "rain-deploy-0.1.30/src/lib/LibRainDeploy.sol";
import {LibConfigRegistry} from "rain-deploy-0.1.30/src/lib/LibConfigRegistry.sol";
import {LibRegistryAuthority} from "rain-deploy-0.1.30/src/lib/LibRegistryAuthority.sol";
import {IConfigRegistryV5} from "rain-deploy-0.1.30/src/interface/IConfigRegistryV5.sol";
import {IRegistryDelegatesV3} from "rain-deploy-0.1.30/src/interface/IRegistryDelegatesV3.sol";
import {DEPLOYED_ADDRESS as CONFIG_REGISTRY_ADDRESS} from "rain-deploy-0.1.30/src/generated/0_1_29/ConfigRegistry.sol";
import {LibConfigRegistryDeploy} from "rain-deploy-0.1.30/src/lib/LibConfigRegistryDeploy.sol";

import {StoxCorporateActionsFacet} from "../../../src/concrete/StoxCorporateActionsFacet.sol";
import {StoxReceiptVault} from "../../../src/concrete/StoxReceiptVault.sol";
import {StoxWrappedTokenVault} from "../../../src/concrete/StoxWrappedTokenVault.sol";
import {
    StoxOffchainAssetReceiptVaultAuthorizerV1
} from "../../../src/concrete/authorize/StoxOffchainAssetReceiptVaultAuthorizerV1.sol";
import {
    ListingAlreadyNamed,
    ListingAssetIdMismatch,
    ListingProofInvalid,
    ListingSignerBindingMalformed,
    ListingSignerMismatch,
    ListingTokenHasNoAssetId
} from "../../../src/error/ErrListing.sol";
import {EmptyUnderlyingName, EmptyUnderlyingSymbol} from "../../../src/error/ErrUnderlying.sol";
import {LibProdDeployCurrent} from "../../../src/generated/LibProdDeployCurrent.sol";
import {LibProdDeployV4} from "../../../src/generated/LibProdDeployV4.sol";
import {IStoxListingV1} from "../../../src/interface/IStoxListingV1.sol";
import {IStoxUnderlyingV1} from "../../../src/interface/IStoxUnderlyingV1.sol";
import {
    LibListing,
    LISTING_AUTHORITY,
    LISTING_DOMAIN_SEPARATOR,
    LISTING_SIGNER_NAME,
    LISTING_TYPEHASH
} from "../../../src/lib/LibListing.sol";
import {LibProdDeployV1} from "../../../src/lib/LibProdDeployV1.sol";
import {LibTimelockInvariants} from "../../../src/lib/LibTimelockInvariants.sol";
import {LibProdTokenConfig, TokenConfig} from "../../../src/lib/LibProdTokenConfig.sol";
import {LibProdTokenParams} from "../../../src/lib/LibProdTokenParams.sol";
import {LibStoxConfig} from "../../../src/lib/LibStoxConfig.sol";
import {RegistryBeaconProxyParams} from "rain-factory-0.2.11/src/lib/LibRainDeployRegistryBeaconProxy.sol";
import {
    OffchainAssetReceiptVaultRbacV1,
    OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE
} from "rain-vats-0.2.20/src/lib/LibOffchainAssetReceiptVaultRbac.sol";
import {LibListingTree, ListingRow} from "../../../src/lib/LibListingTree.sol";
import {LibTestDeploy} from "../../lib/LibTestDeploy.sol";
import {LibTestBeaconInitialOwnerBind} from "../../lib/LibTestBeaconInitialOwnerBind.sol";

/// @title StoxCorporateActionsFacetNameListingTest
/// @notice Anyone first-names an unnamed token from a listing leaf whose root the bound listing signer signed, on any
/// chain; every other call is refused with a typed error.
contract StoxCorporateActionsFacetNameListingTest is Test {
    address internal constant AUTHORITY = address(uint160(uint256(keccak256("AUTHORITY"))));
    address internal constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    address internal constant SAFE = address(uint160(uint256(keccak256("SAFE"))));
    address internal constant STRANGER = address(uint160(uint256(keccak256("STRANGER"))));
    bytes32 internal constant RBAC_NAME = keccak256("st0x.rbac.test.v1");
    string internal constant ASSET_ID = "US67066G1040";
    string internal constant OTHER_ASSET_ID = "US0378331005";
    uint256 internal constant SIGNER_KEY = uint256(keccak256("st0x.test.listing-signer"));
    uint256 internal constant OTHER_KEY = uint256(keccak256("st0x.test.other-signer"));

    StoxReceiptVault internal vault;
    StoxReceiptVault internal otherVault;
    ListingRow[] internal listed;

    function setUp() external {
        LibTestDeploy.deployAll(vm);
        address facet = LibRainDeploy.deployZoltu(type(StoxCorporateActionsFacet).creationCode);
        require(facet == LibProdDeployV4.STOX_CORPORATE_ACTIONS_FACET_CANDIDATE, "facet address mismatch");
        StoxOffchainAssetReceiptVaultAuthorizerV1 impl = new StoxOffchainAssetReceiptVaultAuthorizerV1();
        IAuthorizeV1 authorizer = IAuthorizeV1(
            new CloneFactory()
                .cloneDeterministic(
                    address(impl), LibTestDeploy.authorizerData(vm, OWNER), bytes32(uint256(uint160(address(impl))))
                )
        );
        LibTestDeploy.bindRbac(vm, AUTHORITY, RBAC_NAME, OWNER, authorizer);
        vault = LibTestDeploy.newVault(AUTHORITY, LibTestDeploy.vaultData(ASSET_ID, AUTHORITY, RBAC_NAME));
        otherVault = LibTestDeploy.newVault(AUTHORITY, LibTestDeploy.vaultData(OTHER_ASSET_ID, AUTHORITY, RBAC_NAME));
        listed.push(ListingRow({token: address(vault), assetId: ASSET_ID, ticker: "NVDA", name: "NVIDIA Corporation"}));
        listed.push(
            ListingRow({token: address(otherVault), assetId: OTHER_ASSET_ID, ticker: "AAPL", name: "Apple Inc."})
        );
        listed.push(
            ListingRow({
                token: address(uint160(uint256(keccak256("THIRD")))),
                assetId: "US5949181045",
                ticker: "MSFT",
                name: "Microsoft Corporation"
            })
        );
    }

    function rows() internal view returns (ListingRow[] memory) {
        ListingRow[] memory copied = new ListingRow[](listed.length);
        for (uint256 i = 0; i < listed.length; i++) {
            copied[i] = listed[i];
        }
        return copied;
    }

    function bindSigner(bytes memory value) internal {
        vm.warp(block.timestamp + 1);
        vm.prank(LISTING_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
            .registerV5(LISTING_AUTHORITY, LISTING_SIGNER_NAME, "address", value, "");
    }

    function sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function nameRow(address caller, uint256 index, bytes memory signature) internal {
        ListingRow[] memory all = rows();
        bytes32 root = LibListingTree.root(all);
        bytes32[] memory proof = LibListingTree.proof(all, index);
        vm.prank(caller);
        IStoxListingV1(all[index].token)
            .nameListing(all[index].assetId, all[index].ticker, all[index].name, proof, root, signature);
    }

    function signedRoot() internal view returns (bytes memory) {
        return sign(SIGNER_KEY, LibListing.digest(LibListingTree.root(rows())));
    }

    /// A stranger names the token from its leaf: ticker, name, ERC-20 metadata and the wrapper's follow, with
    /// `UnderlyingSet` and `ListingNamed`.
    function testAnyoneNamesAnUnnamedToken() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        StoxWrappedTokenVault wrapper = LibTestDeploy.newWrapper(AUTHORITY, address(vault));
        bytes32 root = LibListingTree.root(rows());
        vm.expectEmit(address(vault));
        emit IStoxUnderlyingV1.UnderlyingSet(STRANGER, "", "", "NVDA", "NVIDIA Corporation");
        vm.expectEmit(address(vault));
        emit IStoxListingV1.ListingNamed(STRANGER, root);
        nameRow(STRANGER, 0, signedRoot());
        assertEq(IStoxUnderlyingV1(address(vault)).underlyingSymbol(), "NVDA", "ticker");
        assertEq(IStoxUnderlyingV1(address(vault)).underlyingName(), "NVIDIA Corporation", "underlying name");
        assertEq(vault.symbol(), "tNVDA", "symbol");
        assertEq(vault.name(), "NVIDIA Corporation (ST0x)", "name");
        assertEq(wrapper.symbol(), "NVDAs", "wrapper symbol");
        assertEq(wrapper.name(), "NVIDIA Corporation (ST0x)", "wrapper name");
    }

    /// The test-token rows deploy through the production token params at the addresses their listing rows name, and
    /// each is named from that listing.
    function testTheTestTokenRowsDeployAtTheirListedAddressesAndAreNamed() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        address root = LibRegistryAuthority.ROOT_AUTHORITY;
        IAuthorizeV1 authorizer = StoxReceiptVault(payable(address(vault))).authorizer();
        LibTestDeploy.bindRbac(vm, root, LibStoxConfig.RBAC_US_NAME, OWNER, authorizer);
        LibTestDeploy.bind(
            vm,
            root,
            LibStoxConfig.RBAC_EU_NAME,
            OFFCHAIN_ASSET_RECEIPT_VAULT_RBAC_V1_VALUE_TYPE,
            abi.encode(OffchainAssetReceiptVaultRbacV1({owner: OWNER, authorizer: authorizer}))
        );
        TokenConfig[] memory configs = LibProdTokenConfig.testTokenConfigs();
        ListingRow[] memory listing = LibListingTree.rows(configs);
        bytes32 listingRoot = LibListingTree.root(listing);
        bytes memory signature = sign(SIGNER_KEY, LibListing.digest(listingRoot));
        for (uint256 i = 0; i < configs.length; i++) {
            RegistryBeaconProxyParams memory params = LibProdTokenParams.tokenParam(configs[i]);
            address token = LibTestDeploy.factory()
                .registryBeaconProxy(params.registry, params.authority, params.beaconName, params.data, params.salt);
            assertEq(token, listing[i].token, configs[i].underlying);
            vm.prank(STRANGER);
            IStoxListingV1(token)
                .nameListing(
                    configs[i].assetId,
                    configs[i].underlying,
                    configs[i].underlyingName,
                    LibListingTree.proof(listing, i),
                    listingRoot,
                    signature
                );
            assertEq(StoxReceiptVault(payable(token)).symbol(), configs[i].symbol, configs[i].underlying);
        }
    }

    /// The same signature names tokens under two chain ids, and the digest depends on neither the chain nor the
    /// contract.
    function testOneSignatureHoldsOnEveryChain(uint64 firstChainId, uint64 secondChainId) external {
        vm.assume(firstChainId != 0 && secondChainId != 0 && firstChainId != secondChainId);
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        bytes memory signature = signedRoot();
        bytes32 root = LibListingTree.root(rows());
        vm.chainId(firstChainId);
        bytes32 firstDigest = LibListing.digest(root);
        nameRow(STRANGER, 0, signature);
        vm.chainId(secondChainId);
        assertEq(LibListing.digest(root), firstDigest, "digest");
        nameRow(STRANGER, 1, signature);
        assertEq(vault.symbol(), "tNVDA", "first chain");
        assertEq(otherVault.symbol(), "tAAPL", "second chain");
    }

    /// The digest of a fixed root equals one computed outside `LibListing` (with `cast`).
    function testDigestVector() external pure {
        bytes32 root = keccak256("st0x.test.listing.root");
        assertEq(root, 0xb23c400cf7c4294b56a4a0fc5a33f1270786700652a5a81ce76c2b2c6123c12c, "root");
        assertEq(LISTING_DOMAIN_SEPARATOR, 0xa3bd0f52729b93c68ff4431aaa8c591b31df7a03f044c80bcd8857ae1121ae74, "domain");
        assertEq(LibListing.digest(root), 0x77f3958edc5774249442f85010bf4546c789155245758d432a512d0ec4fd3439, "digest");
        assertEq(
            LibListing.digest(root),
            MessageHashUtils.toTypedDataHash(
                MessageHashUtils.toDomainSeparator(
                    bytes1(0x03), keccak256("ST0x Listing"), keccak256("1"), 0, address(0), bytes32(0)
                ),
                keccak256(abi.encode(LISTING_TYPEHASH, root))
            ),
            "OpenZeppelin domain without chain id and verifying contract"
        );
    }

    /// A token initialized without an asset id is never listed.
    function testRefusesATokenWithoutAssetId() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        address legacy = address(new BeaconProxy(LibProdDeployV1.STOX_RECEIPT_VAULT_BEACON_V1, ""));
        vm.expectRevert(ListingTokenHasNoAssetId.selector);
        IStoxListingV1(legacy).nameListing("", "NVDA", "NVIDIA Corporation", new bytes32[](0), bytes32(0), "");
    }

    /// The listed asset id must be the token's own.
    function testRefusesAnotherAssetId() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        ListingRow[] memory all = rows();
        bytes32 root = LibListingTree.root(all);
        bytes32[] memory proof = LibListingTree.proof(all, 1);
        bytes memory signature = signedRoot();
        vm.expectRevert(abi.encodeWithSelector(ListingAssetIdMismatch.selector, ASSET_ID, OTHER_ASSET_ID));
        IStoxListingV1(address(vault)).nameListing(OTHER_ASSET_ID, "AAPL", "Apple Inc.", proof, root, signature);
    }

    /// A listed token refuses a second listing, with its own leaf or another.
    function testRefusesASecondListing() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        bytes memory signature = signedRoot();
        nameRow(STRANGER, 0, signature);
        vm.expectRevert(ListingAlreadyNamed.selector);
        nameRow(STRANGER, 0, signature);

        listed[0].name = "NVIDIA Corp";
        bytes memory renamedSignature = signedRoot();
        vm.expectRevert(ListingAlreadyNamed.selector);
        nameRow(STRANGER, 0, renamedSignature);
    }

    /// A token its owner named with `setUnderlying` refuses a listing.
    function testRefusesATokenTheOwnerNamed() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        vm.prank(OWNER);
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corporation");
        bytes memory signature = signedRoot();
        vm.expectRevert(ListingAlreadyNamed.selector);
        nameRow(STRANGER, 0, signature);
    }

    /// After a listing only the owner renames, with `setUnderlying`.
    function testOnlyTheOwnerRenamesAfterAListing() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        nameRow(STRANGER, 0, signedRoot());
        vm.prank(STRANGER);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, STRANGER));
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corp");
        vm.prank(OWNER);
        IStoxUnderlyingV1(address(vault)).setUnderlying("NVDA", "NVIDIA Corp");
        assertEq(vault.name(), "NVIDIA Corp (ST0x)", "renamed");
    }

    function expectProofInvalid(
        address token,
        string memory assetId,
        string memory ticker,
        string memory name,
        bytes32 root
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(ListingProofInvalid.selector, LibListing.leaf(token, assetId, ticker, name), root)
        );
    }

    /// A leaf that differs from the signed one in its ticker, its name or its proof is refused.
    function testRefusesALeafNotInTheRoot() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        ListingRow[] memory all = rows();
        bytes32 root = LibListingTree.root(all);
        bytes32[] memory proof = LibListingTree.proof(all, 0);
        bytes memory signature = signedRoot();

        expectProofInvalid(address(vault), ASSET_ID, "NVDX", "NVIDIA Corporation", root);
        IStoxListingV1(address(vault)).nameListing(ASSET_ID, "NVDX", "NVIDIA Corporation", proof, root, signature);

        expectProofInvalid(address(vault), ASSET_ID, "NVDA", "NVIDIA Corp", root);
        IStoxListingV1(address(vault)).nameListing(ASSET_ID, "NVDA", "NVIDIA Corp", proof, root, signature);

        bytes32[] memory tampered = LibListingTree.proof(all, 0);
        tampered[0] = bytes32(uint256(tampered[0]) ^ 1);
        expectProofInvalid(address(vault), ASSET_ID, "NVDA", "NVIDIA Corporation", root);
        IStoxListingV1(address(vault)).nameListing(ASSET_ID, "NVDA", "NVIDIA Corporation", tampered, root, signature);

        bytes32[] memory otherProof = LibListingTree.proof(all, 2);
        expectProofInvalid(address(vault), ASSET_ID, "NVDA", "NVIDIA Corporation", root);
        IStoxListingV1(address(vault)).nameListing(ASSET_ID, "NVDA", "NVIDIA Corporation", otherProof, root, signature);
    }

    /// A look-alike vault with the same asset id at another address does not match the signed leaf.
    function testRefusesALookAlikeToken() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        StoxReceiptVault lookAlike = StoxReceiptVault(
            payable(LibTestDeploy.factory()
                    .registryBeaconProxy(
                        CONFIG_REGISTRY_ADDRESS,
                        AUTHORITY,
                        keccak256("st0x.vault-beacon.v1"),
                        LibTestDeploy.vaultData(ASSET_ID, AUTHORITY, RBAC_NAME),
                        keccak256("another salt")
                    ))
        );
        ListingRow[] memory all = rows();
        bytes32 root = LibListingTree.root(all);
        bytes32[] memory proof = LibListingTree.proof(all, 0);
        bytes memory signature = signedRoot();
        expectProofInvalid(address(lookAlike), ASSET_ID, "NVDA", "NVIDIA Corporation", root);
        IStoxListingV1(address(lookAlike)).nameListing(ASSET_ID, "NVDA", "NVIDIA Corporation", proof, root, signature);
    }

    /// With no signer bound under the timelock, the registry refuses: binding it under the root authority does not
    /// count.
    function testRefusesAnUnboundSigner() external {
        vm.prank(LibRegistryAuthority.ROOT_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
            .registerV5(
                LibRegistryAuthority.ROOT_AUTHORITY, LISTING_SIGNER_NAME, "address", abi.encode(vm.addr(SIGNER_KEY)), ""
            );
        bytes memory signature = signedRoot();
        vm.expectRevert(
            abi.encodeWithSelector(IConfigRegistryV5.NameNotRegistered.selector, LISTING_AUTHORITY, LISTING_SIGNER_NAME)
        );
        nameRow(STRANGER, 0, signature);
    }

    /// A binding of another type is refused.
    function testRefusesAMistypedBinding() external {
        vm.prank(LISTING_AUTHORITY);
        IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
            .registerV5(LISTING_AUTHORITY, LISTING_SIGNER_NAME, "uint256", abi.encode(vm.addr(SIGNER_KEY)), "");
        bytes memory signature = signedRoot();
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.ValueTypeMismatch.selector,
                LISTING_AUTHORITY,
                LISTING_SIGNER_NAME,
                keccak256("address"),
                keccak256("uint256")
            )
        );
        nameRow(STRANGER, 0, signature);
    }

    /// An `address` binding that is not one canonical word is refused.
    function testRefusesAMalformedBinding() external {
        bytes memory signature = signedRoot();
        bytes[] memory values = new bytes[](3);
        values[0] = hex"01";
        values[1] = abi.encode(vm.addr(SIGNER_KEY), uint256(0));
        values[2] = abi.encode(uint256(uint160(vm.addr(SIGNER_KEY))) | (uint256(1) << 160));
        for (uint256 i = 0; i < values.length; i++) {
            bindSigner(values[i]);
            vm.expectRevert(abi.encodeWithSelector(ListingSignerBindingMalformed.selector, values[i]));
            nameRow(STRANGER, 0, signature);
        }
    }

    /// Without the pinned registry the listing is refused.
    function testRefusesWithoutTheRegistry() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        bytes memory signature = signedRoot();
        vm.etch(CONFIG_REGISTRY_ADDRESS, hex"00");
        vm.expectRevert(
            abi.encodeWithSelector(
                LibConfigRegistry.UnexpectedConfigRegistryCodeHash.selector,
                LibConfigRegistryDeploy.CONFIG_REGISTRY_DEPLOYED_CODEHASH,
                keccak256(hex"00")
            )
        );
        nameRow(STRANGER, 0, signature);
    }

    /// A signature by another key is refused.
    function testRefusesAnotherSigner() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        vm.expectRevert(abi.encodeWithSelector(ListingSignerMismatch.selector, vm.addr(OTHER_KEY), vm.addr(SIGNER_KEY)));
        nameRow(STRANGER, 0, sign(OTHER_KEY, LibListing.digest(LibListingTree.root(rows()))));
    }

    /// A signature over another root, or over the root in another domain or struct type, is refused.
    function testRefusesASignatureOverAnythingElse() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        bytes32 root = LibListingTree.root(rows());
        bytes32 structHash = keccak256(abi.encode(LISTING_TYPEHASH, root));
        bytes32[] memory digests = new bytes32[](4);
        digests[0] = LibListing.digest(keccak256("another root"));
        digests[1] = MessageHashUtils.toTypedDataHash(
            MessageHashUtils.toDomainSeparator(
                bytes1(0x0f), keccak256("ST0x Listing"), keccak256("1"), block.chainid, address(vault), bytes32(0)
            ),
            structHash
        );
        digests[2] = MessageHashUtils.toTypedDataHash(
            MessageHashUtils.toDomainSeparator(
                bytes1(0x03), keccak256("ST0x Listing"), keccak256("2"), 0, address(0), bytes32(0)
            ),
            structHash
        );
        digests[3] = MessageHashUtils.toTypedDataHash(
            LISTING_DOMAIN_SEPARATOR, keccak256(abi.encode(keccak256("Listing(bytes32 merkleRoot)"), root))
        );
        for (uint256 i = 0; i < digests.length; i++) {
            bytes memory signature = sign(SIGNER_KEY, digests[i]);
            address recovered = ECDSA.recover(LibListing.digest(root), signature);
            vm.expectRevert(abi.encodeWithSelector(ListingSignerMismatch.selector, recovered, vm.addr(SIGNER_KEY)));
            nameRow(STRANGER, 0, signature);
        }
    }

    /// A malformed, high-s or invalid signature is refused by OpenZeppelin's ECDSA.
    function testRefusesAMalformedSignature() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        bytes32 digest = LibListing.digest(LibListingTree.root(rows()));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, digest);

        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 64));
        nameRow(STRANGER, 0, abi.encodePacked(r, s));

        bytes32 highS = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, highS));
        nameRow(STRANGER, 0, abi.encodePacked(r, highS, v == 27 ? uint8(28) : uint8(27)));

        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        nameRow(STRANGER, 0, abi.encodePacked(r, s, v - 27));
    }

    /// A signed leaf with an empty ticker or name is refused as `setUnderlying` refuses it.
    function testRefusesAnEmptyTickerOrName() external {
        bindSigner(abi.encode(vm.addr(SIGNER_KEY)));
        listed[0].ticker = "";
        vm.expectRevert(EmptyUnderlyingSymbol.selector);
        nameRow(STRANGER, 0, signedRoot());
        listed[0].ticker = "NVDA";
        listed[0].name = "";
        vm.expectRevert(EmptyUnderlyingName.selector);
        nameRow(STRANGER, 0, signedRoot());
    }

    /// The standalone facet refuses a direct call.
    function testRefusesADirectCallOnTheFacet() external {
        vm.expectRevert(StoxCorporateActionsFacet.FacetMustBeDelegatecalled.selector);
        IStoxListingV1(LibProdDeployCurrent.STOX_CORPORATE_ACTIONS_FACET)
            .nameListing(ASSET_ID, "NVDA", "NVIDIA Corporation", new bytes32[](0), bytes32(0), "");
    }

    /// Only the governance timelock binds the signer, through a scheduled operation after its delay: the Safe and the
    /// root authority cannot write under it. A rebind retires every signature of the old signer.
    function testOnlyTheTimelockBindsTheSigner() external {
        address timelock = LibTestBeaconInitialOwnerBind.deployTimelock(vm, SAFE);
        assertEq(timelock, LISTING_AUTHORITY, "timelock is the listing authority");
        address[2] memory writers = [SAFE, LibRegistryAuthority.ROOT_AUTHORITY];
        for (uint256 i = 0; i < writers.length; i++) {
            vm.prank(writers[i]);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IRegistryDelegatesV3.NotApproved.selector, LISTING_AUTHORITY, LISTING_SIGNER_NAME, writers[i]
                )
            );
            IConfigRegistryV5(CONFIG_REGISTRY_ADDRESS)
                .registerV5(LISTING_AUTHORITY, LISTING_SIGNER_NAME, "address", abi.encode(writers[i]), "");
        }

        bindThroughTimelock(TimelockController(payable(timelock)), vm.addr(SIGNER_KEY), bytes32(uint256(1)));
        bytes memory oldSignature = signedRoot();
        nameRow(STRANGER, 0, oldSignature);

        bindThroughTimelock(TimelockController(payable(timelock)), vm.addr(OTHER_KEY), bytes32(uint256(2)));
        vm.expectRevert(abi.encodeWithSelector(ListingSignerMismatch.selector, vm.addr(SIGNER_KEY), vm.addr(OTHER_KEY)));
        nameRow(STRANGER, 1, oldSignature);
        nameRow(STRANGER, 1, sign(OTHER_KEY, LibListing.digest(LibListingTree.root(rows()))));
        assertEq(otherVault.symbol(), "tAAPL", "named by the new signer");
    }

    function bindThroughTimelock(TimelockController timelock, address signer, bytes32 salt) internal {
        bytes memory payload = abi.encodeCall(
            IConfigRegistryV5.registerV5, (LISTING_AUTHORITY, LISTING_SIGNER_NAME, "address", abi.encode(signer), "")
        );
        vm.prank(SAFE);
        timelock.schedule(
            CONFIG_REGISTRY_ADDRESS, 0, payload, bytes32(0), salt, LibTimelockInvariants.TIMELOCK_MIN_DELAY
        );
        vm.warp(block.timestamp + LibTimelockInvariants.TIMELOCK_MIN_DELAY - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                TimelockController.TimelockUnexpectedOperationState.selector,
                timelock.hashOperation(CONFIG_REGISTRY_ADDRESS, 0, payload, bytes32(0), salt),
                bytes32(uint256(1) << uint8(TimelockController.OperationState.Ready))
            )
        );
        timelock.execute(CONFIG_REGISTRY_ADDRESS, 0, payload, bytes32(0), salt);
        vm.warp(block.timestamp + 1);
        vm.prank(STRANGER);
        timelock.execute(CONFIG_REGISTRY_ADDRESS, 0, payload, bytes32(0), salt);
        assertEq(LibListing.signer(), signer, "bound signer");
    }
}
