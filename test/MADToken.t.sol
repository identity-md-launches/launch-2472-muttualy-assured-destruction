// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

contract MADTokenTest is Test {
    MADToken token;
    address deployer = address(0xFAC7);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.prank(deployer);
        token = new MADToken();
    }

    function test_metadataAndSupply() public view {
        assertEq(token.name(), "Muttualy Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(deployer), 1_000_000_000e18);
    }

    function test_transfer() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 100e18));
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(deployer), 1_000_000_000e18 - 100e18);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_transferToZeroReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        token.approve(alice, 50e18);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 20e18);
        assertEq(token.balanceOf(bob), 20e18);
        assertEq(token.allowance(deployer, alice), 30e18);
    }

    function test_infiniteAllowanceNotDecreased() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1e18);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_transferFromRevertsOverAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 1, 2));
        token.transferFrom(deployer, bob, 2);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_burnReducesSupply() public {
        vm.prank(deployer);
        token.burn(10e18);
        assertEq(token.totalSupply(), 1_000_000_000e18 - 10e18);
    }

    function test_burnRevertsOverBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, alice, 0, 1));
        token.burn(1);
    }

    function test_noMintEntryPoint() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1));
        assertFalse(ok);
        assertEq(token.totalSupply(), 1_000_000_000e18);
    }

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, token.balanceOf(deployer));
        vm.prank(deployer);
        token.transfer(to, amount);
        assertEq(token.totalSupply(), 1_000_000_000e18);
        if (to != deployer) assertEq(token.balanceOf(to), amount);
    }
}
