// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NightshiftTestToken} from "../src/NightshiftTestToken.sol";

/// @notice Behavioural tests for the TESTNS token: metadata, the one-time mint, plain transfers
///         with no fee or limit, allowance semantics, and the absence of any mint or admin path.
contract NightshiftTestTokenTest is Test {
    uint256 internal constant SUPPLY = 100 ether;

    /// @dev Stands in for the launch factory: the address that deploys and so receives the supply.
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    NightshiftTestToken internal token;

    function setUp() public {
        vm.prank(deployer);
        token = new NightshiftTestToken();
    }

    // ---------------------------------------------------------------- metadata

    function test_metadata() public view {
        assertEq(token.name(), "Test from Nightshift launchpad");
        assertEq(token.symbol(), "TESTNS");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), token.name());
        assertEq(token.TOKEN_SYMBOL(), token.symbol());
        assertEq(uint256(token.DECIMALS()), uint256(token.decimals()));
    }

    // ---------------------------------------------------------------- supply

    function test_constructorMintsWholeSupplyToDeployerOnce() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), 100 * 10 ** 18);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.recordLogs();
        vm.prank(deployer);
        new NightshiftTestToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event on deploy");
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(0));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), deployer);
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_supplyGoesToWhoeverDeploys() public {
        address other = makeAddr("otherDeployer");
        vm.prank(other);
        NightshiftTestToken fresh = new NightshiftTestToken();
        assertEq(fresh.balanceOf(other), SUPPLY);
        assertEq(fresh.balanceOf(deployer), 0);
    }

    // ---------------------------------------------------------------- transfers

    function test_transferMovesExactAmountWithNoFee() public {
        uint256 amount = 12.5 ether;
        vm.prank(deployer);
        vm.expectEmit(address(token));
        emit IERC20.Transfer(deployer, alice, amount);
        assertTrue(token.transfer(alice, amount));

        assertEq(token.balanceOf(alice), amount, "recipient receives the full amount");
        assertEq(token.balanceOf(deployer), SUPPLY - amount, "sender pays exactly the amount");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalanceHasNoLimit() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 40 ether));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_chainOfTransfersConservesSupply() public {
        vm.prank(deployer);
        token.transfer(alice, 60 ether);
        vm.prank(alice);
        token.transfer(bob, 25 ether);
        vm.prank(bob);
        token.transfer(carol, 5 ether);

        assertEq(token.balanceOf(deployer), 40 ether);
        assertEq(token.balanceOf(alice), 35 ether);
        assertEq(token.balanceOf(bob), 20 ether);
        assertEq(token.balanceOf(carol), 5 ether);
        assertEq(
            token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(carol), SUPPLY
        );
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 1 ether + 1)
        );
        token.transfer(bob, 1 ether + 1);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, bob, 0, 1));
        token.transfer(alice, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
    }

    // ---------------------------------------------------------------- allowances

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(alice);
        vm.expectEmit(address(token));
        emit IERC20.Approval(alice, bob, 7 ether);
        assertTrue(token.approve(bob, 7 ether));
        assertEq(token.allowance(alice, bob), 7 ether);
    }

    function test_transferFromSpendsAllowanceExactly() public {
        vm.prank(deployer);
        token.approve(alice, 30 ether);

        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 20 ether));

        assertEq(token.balanceOf(bob), 20 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 20 ether);
        assertEq(token.allowance(deployer, alice), 10 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);

        vm.prank(alice);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, alice, 1);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 5 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 5 ether, 5 ether + 1)
        );
        token.transferFrom(deployer, bob, 5 ether + 1);
    }

    function test_RevertWhen_transferFromExceedsBalanceDespiteAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);
        vm.prank(alice);
        token.approve(bob, 2 ether);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, 2 ether));
        token.transferFrom(alice, carol, 2 ether);
    }

    /// @dev The deployer (the factory in production) holds no special power: without an allowance
    ///      it cannot pull a holder's tokens any more than a stranger can.
    function test_RevertWhen_deployerPullsFromHolderWithoutAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 1 ether);

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    // ---------------------------------------------------------------- no mint, no admin

    function test_noMintOrAdminSelectorExists() public {
        string[22] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "owner()",
            "setOwner(address)",
            "transferOwnership(address)",
            "renounceOwnership()",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "blacklist(address)",
            "freeze(address)",
            "setBlacklist(address,bool)",
            "setTransfersEnabled(bool)",
            "disableTransfers()",
            "seize(address)",
            "setFee(uint256)"
        ];
        address attacker = makeAddr("attacker");
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool okAttacker,) = address(token).call(data);
            assertFalse(okAttacker, signatures[i]);
            vm.prank(deployer);
            (bool okDeployer,) = address(token).call(data);
            assertFalse(okDeployer, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(attacker), 0);
    }

    function test_RevertWhen_sendingEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok, "token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    function test_runtimeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferIsExactAndConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != deployer);
        amount = bound(amount, 0, SUPPLY);

        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));

        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhen_transferExceedsBalance(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, SUPPLY + 1, type(uint256).max);

        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        token.transfer(to, amount);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, allowed);

        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, spent));

        assertEq(token.balanceOf(bob), spent);
        assertEq(token.allowance(deployer, alice), allowed - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevertWhen_transferFromExceedsAllowance(uint256 allowed, uint256 spent) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        spent = bound(spent, allowed + 1, SUPPLY);

        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, spent));
        token.transferFrom(deployer, bob, spent);
    }

    function testFuzz_roundTripReturnsExactly(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
