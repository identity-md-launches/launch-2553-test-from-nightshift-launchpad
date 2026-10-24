// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Test from Nightshift launchpad (TESTNS)
/// @notice A fixed-supply community coin launched with the NIGHTSHIFT Launchpad
///         (getnightshift.tech/launchpad). Plain ERC-20: no fee, tax, limit, pause,
///         blacklist or owner. The whole supply is minted once, in the constructor,
///         to the deployer, and nothing can ever mint more.
/// @dev The deployer is the launch factory, which distributes the supply (swarm share,
///      pool seed, requester remainder) after deployment. The contract keeps no admin
///      role of any kind, so there is nothing to transfer, renounce or configure.
contract NightshiftTestToken is ERC20 {
    /// @notice The token's full ERC-20 name.
    string public constant TOKEN_NAME = "Test from Nightshift launchpad";

    /// @notice The token's ticker.
    string public constant TOKEN_SYMBOL = "TESTNS";

    /// @notice Decimals, fixed at the ERC-20 default.
    uint8 public constant DECIMALS = 18;

    /// @notice The whole supply in minor units: 100 tokens with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 100 * 10 ** uint256(DECIMALS);

    /// @notice Mints the entire fixed supply to the deployer (`msg.sender`) exactly once.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
