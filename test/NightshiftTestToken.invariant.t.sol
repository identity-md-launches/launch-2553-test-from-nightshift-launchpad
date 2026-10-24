// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NightshiftTestToken} from "../src/NightshiftTestToken.sol";

/// @notice Drives transfers, approvals and transferFrom among a fixed set of actors so the
///         invariant runner can check that supply is conserved and never grows.
contract TokenHandler is Test {
    NightshiftTestToken public immutable token;
    address[] public actors;

    constructor(NightshiftTestToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        token.approve(spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 cap = token.allowance(owner, spender);
        uint256 bal = token.balanceOf(owner);
        if (bal < cap) cap = bal;
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }
}

contract NightshiftTestTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 100 ether;

    NightshiftTestToken internal token;
    TokenHandler internal handler;
    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new NightshiftTestToken();

        actors.push(deployer);
        for (uint256 i = 0; i < 5; i++) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
        }
        handler = new TokenHandler(token, actors);
        targetContract(address(handler));
    }

    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY);
    }
}
