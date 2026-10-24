// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {NightshiftTestToken} from "../src/NightshiftTestToken.sol";

/// @title Deploy script for Test from Nightshift launchpad (TESTNS)
/// @notice Review aid only. The production launch is performed by IMD's deployer through the
///         ProjectFactory, which deploys the token from its built bytecode; this script is for
///         local forks and dry runs. It reads no environment variables and takes no parameters:
///         the token has no constructor arguments, so there is nothing to configure.
contract DeployNightshiftTestToken is Script {
    /// @notice Deploys the token. The caller of this function receives the whole supply.
    /// @dev Tests call this directly; `run()` wraps it in a broadcast.
    function deploy() public returns (NightshiftTestToken token) {
        token = new NightshiftTestToken();
    }

    /// @notice Broadcast entry point: `forge script script/DeployNightshiftTestToken.s.sol --broadcast`.
    function run() external returns (NightshiftTestToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
