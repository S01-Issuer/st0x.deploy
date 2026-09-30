// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2026 S01 Issuer GmbH
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {
    LibTestDotrain,
    DotrainBinding,
    NoFrontMatterSplitter,
    DuplicateBinding,
    NoEntrypoint,
    NotElided,
    Unbound
} from "test/lib/LibTestDotrain.sol";

/// @title LibTestDotrainTest
/// @notice The composer the mint weighting tests read `.rain` sources with
/// does what `rain dotrain compose` does for the files in this repo, and
/// refuses a file and a binding set that do not fit each other.
contract LibTestDotrainTest is Test {
    /// A file with an elided binding, a defaulted one, a body and a trailing
    /// binding, and every place a name may appear.
    string internal constant FILE = "# front matter\n" "---\n" "#a !What a is.\n" "#b 2\n" "\n" "#main\n"
        "/* a b in a comment */\n" "_: add(a b \"a b\" a-b ab ba);\n" "#tail 1\n";

    function compose(string memory dotrain, string memory entrypoint, DotrainBinding[] memory bindings)
        external
        pure
        returns (string memory)
    {
        return LibTestDotrain.compose(dotrain, entrypoint, bindings);
    }

    function _bind(string memory name, string memory value) internal pure returns (DotrainBinding[] memory bindings) {
        bindings = new DotrainBinding[](1);
        bindings[0] = DotrainBinding(name, value);
    }

    /// Whole words are replaced, from the caller's bindings and the file's
    /// defaults, and nothing inside a comment, a string or a longer word is.
    function testComposeSubstitutesWholeWords() external pure {
        assertEq(
            LibTestDotrain.compose(FILE, "main", _bind("a", "1")),
            "/* a b in a comment */\n" "_: add(1 2 \"a b\" a-b ab ba);\n"
        );
    }

    /// The body runs to the end of the file when nothing follows it.
    function testComposeLastBinding() external pure {
        string memory file = "---\n" "#x !\n" "#main\n" "_: x;\n";
        assertEq(LibTestDotrain.compose(file, "main", _bind("x", "5")), "_: 5;\n");
    }

    /// Every elided binding has to be bound.
    function testComposeUnbound() external {
        vm.expectRevert(abi.encodeWithSelector(Unbound.selector, "a"));
        this.compose(FILE, "main", new DotrainBinding[](0));
    }

    /// A binding the file gives a value is not the caller's to bind, and
    /// neither is one the file does not declare.
    function testComposeNotElided() external {
        DotrainBinding[] memory bindings = new DotrainBinding[](2);
        bindings[0] = DotrainBinding("a", "1");
        bindings[1] = DotrainBinding("b", "3");
        vm.expectRevert(abi.encodeWithSelector(NotElided.selector, "b"));
        this.compose(FILE, "main", bindings);

        bindings[1] = DotrainBinding("c", "3");
        vm.expectRevert(abi.encodeWithSelector(NotElided.selector, "c"));
        this.compose(FILE, "main", bindings);
    }

    function testComposeNoEntrypoint() external {
        vm.expectRevert(abi.encodeWithSelector(NoEntrypoint.selector, "other"));
        this.compose(FILE, "other", _bind("a", "1"));
    }

    function testComposeNoFrontMatter() external {
        vm.expectRevert(NoFrontMatterSplitter.selector);
        this.compose("#main\n_: 1;\n", "main", new DotrainBinding[](0));
    }

    function testComposeDuplicate() external {
        vm.expectRevert(abi.encodeWithSelector(DuplicateBinding.selector, "main"));
        this.compose("---\n#main\n_: 1;\n#main\n_: 2;\n", "main", new DotrainBinding[](0));
    }
}
