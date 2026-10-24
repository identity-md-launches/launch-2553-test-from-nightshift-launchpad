// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployNightshiftTestToken} from "../script/DeployNightshiftTestToken.s.sol";
import {NightshiftTestToken} from "../src/NightshiftTestToken.sol";

/// @notice The deploy script's `deploy()` is called directly, with no environment and no
///         broadcast, so this passes in any order and in parallel.
contract DeployNightshiftTestTokenTest is Test {
    function test_deployMintsSupplyToTheCaller() public {
        DeployNightshiftTestToken deployScript = new DeployNightshiftTestToken();
        NightshiftTestToken token = deployScript.deploy();

        assertEq(token.name(), "Test from Nightshift launchpad");
        assertEq(token.symbol(), "TESTNS");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 100 ether);
        // `deploy()` is an external call from this test, so the script contract is `msg.sender`
        // of the constructor and receives the supply, exactly as the factory does at launch.
        assertEq(token.balanceOf(address(deployScript)), 100 ether);
    }
}
