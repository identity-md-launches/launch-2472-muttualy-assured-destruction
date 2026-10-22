// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

contract MADHandler is Test {
    MADToken public token;
    address[] public actors;
    uint256 public ghostBurned;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    constructor(MADToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 s) internal view returns (address) {
        return actors[s % actors.length];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = token.balanceOf(from);
        amount = bound(amount, 0, bal);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(from);
        token.transfer(to, amount);
        if (from != to) {
            assertEq(token.balanceOf(from), bal - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        } else {
            assertEq(token.balanceOf(from), bal);
        }
    }

    function transferTooMuch(uint256 fromSeed, uint256 toSeed, uint256 extra) external {
        address from = _actor(fromSeed);
        uint256 bal = token.balanceOf(from);
        extra = bound(extra, 1, type(uint256).max - bal);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, from, bal, bal + extra));
        token.transfer(_actor(toSeed), bal + extra);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (amount % 5 == 0) amount = type(uint256).max;
        vm.prank(owner);
        token.approve(spender, amount);
        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = token.allowance(from, spender);
        uint256 cap = token.balanceOf(from) < allowed ? token.balanceOf(from) : allowed;
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        token.transferFrom(from, to, amount);
        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        uint256 allowed = token.allowance(from, spender);
        if (allowed == type(uint256).max) return;
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, spender, allowed, allowed + 1));
        token.transferFrom(from, _actor(toSeed), allowed + 1);
    }

    function burn(uint256 seed, uint256 amount) external {
        address who = _actor(seed);
        amount = bound(amount, 0, token.balanceOf(who));
        vm.prank(who);
        token.burn(amount);
        ghostBurned += amount;
    }
}

contract MADTokenInvariantTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;
    MADToken token;
    MADHandler handler;
    address[] actors;

    function setUp() public {
        actors.push(address(0xFAC7));
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA7));
        vm.prank(actors[0]);
        token = new MADToken();
        handler = new MADHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 64
    function invariant_sumOfBalancesEqualsSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) sum += token.balanceOf(actors[i]);
        assertEq(sum, token.totalSupply());
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyOnlyShrinksByBurns() public view {
        assertEq(token.totalSupply() + handler.ghostBurned(), SUPPLY);
        assertLe(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchGhost() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.ghostAllowance(actors[i], actors[j]));
            }
        }
    }
}

contract MADTokenEdgeTest is Test {
    uint256 constant SUPPLY = 1_000_000_000e18;
    MADToken token;
    address deployer = address(0xFAC7);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new MADToken();
    }

    function test_constructorEmitsMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new MADToken();
    }

    function test_initialSupplyConstant() public view {
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function test_transferFullSupply() public {
        vm.prank(deployer);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferOneOverFullSupplyReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1));
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferMaxUintReverts() public {
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_zeroTransferFromEmptyAccount() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(deployer, 123);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferFromToZeroReverts() public {
        vm.prank(deployer);
        token.approve(alice, 10);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.allowance(deployer, alice), 10, "allowance consumed on revert");
    }

    function test_transferFromWithoutAllowanceReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_transferFromAllowanceOkButBalanceShort() public {
        vm.prank(alice);
        token.approve(bob, 100);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, alice, 0, 5));
        token.transferFrom(alice, bob, 5);
        assertEq(token.allowance(alice, bob), 100);
    }

    function test_transferFromExactAllowanceZeroes() public {
        vm.prank(deployer);
        token.approve(alice, 7);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 7);
        assertEq(token.allowance(deployer, alice), 0);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_approveOverwritesAndEmits() public {
        vm.startPrank(deployer);
        token.approve(alice, 100);
        vm.expectEmit(true, true, false, true);
        emit Approval(deployer, alice, 5);
        token.approve(alice, 5);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 5);
    }

    function test_burnFullSupplyAndZero() public {
        vm.startPrank(deployer);
        token.burn(0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectEmit(true, true, false, true);
        emit Transfer(deployer, address(0), SUPPLY);
        token.burn(SUPPLY);
        vm.stopPrank();
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_burnFromOthersNotPossible() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("burnFrom(address,uint256)", deployer, 1));
        assertFalse(ok);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_rejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromAccounting(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        token.transferFrom(deployer, bob, amount);
        assertEq(token.allowance(deployer, alice), allowed - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_burnRevertsAboveBalance(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(MADToken.InsufficientBalance.selector, deployer, SUPPLY, amount));
        token.burn(amount);
    }
}
