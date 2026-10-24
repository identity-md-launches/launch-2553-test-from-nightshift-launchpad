// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NightshiftTestToken} from "../src/NightshiftTestToken.sol";

contract NightshiftDeploymentProbe {
    function deploy() external returns (NightshiftTestToken) {
        return new NightshiftTestToken();
    }
}

/// @notice Boundary and authorization regressions supplementing the original behavioral suite.
/// forge-config: default.fuzz.runs = 1000
contract NightshiftTestTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 100 ether;
    NightshiftTestToken internal token;
    address internal deployer = makeAddr("edge.deployer");
    address internal alice = makeAddr("edge.alice");
    address internal bob = makeAddr("edge.bob");
    address internal carol = makeAddr("edge.carol");

    function setUp() public {
        vm.prank(deployer);
        token = new NightshiftTestToken();
    }

    function test_contractDeploymentMintsToImmediateDeployerNotOrigin() public {
        NightshiftDeploymentProbe factory = new NightshiftDeploymentProbe();
        vm.prank(alice, bob);
        NightshiftTestToken fresh = factory.deploy();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(alice), 0);
        assertEq(fresh.balanceOf(bob), 0);
        assertEq(fresh.balanceOf(deployer), 0);
        assertEq(fresh.balanceOf(address(fresh)), 0);
    }

    function test_zeroTransferFromEmptyHolderEmitsTransfer() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(_stateDigest(), beforeState);
    }

    function test_zeroTransferFromNeedsNoBalanceOrAllowanceAndEmitsTransfer() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(carol);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(_stateDigest(), beforeState);
    }

    function test_oneWeiCanBeTransferredAndSpentWithoutRoundingOrFee() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(bob, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, carol, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 1));
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(carol), 1);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullSupplyCanBeSpentByApprovedThirdParty() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, SUPPLY));
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(deployer, alice), 0);
        vm.prank(bob);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_selfTransferOfWholeSupplyEmitsWithoutChangingState() public {
        bytes32 beforeState = _stateDigest();
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, deployer, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(_stateDigest(), beforeState);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, SUPPLY));
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, deployer, SUPPLY);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, deployer, 1);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        bytes32 beforeState = _stateDigest();
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transfer(deployer, SUPPLY + 1);
        assertEq(_stateDigest(), beforeState);

        vm.prank(deployer);
        assertTrue(token.approve(alice, type(uint256).max));
        beforeState = _stateDigest();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        token.transferFrom(deployer, deployer, SUPPLY + 1);
        assertEq(_stateDigest(), beforeState);
    }

    function test_transferFromByHolderDoesNotBypassAllowance() public {
        bytes32 beforeState = _stateDigest();
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(deployer, alice, 1);
        assertEq(_stateDigest(), beforeState);

        vm.prank(deployer);
        assertTrue(token.approve(deployer, 1));
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, type(uint256).max - 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertEq(token.allowance(deployer, alice), type(uint256).max - 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_infiniteAllowanceSurvivesRepeatedSpendsButCanBeRevoked() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, type(uint256).max));
        vm.startPrank(alice);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertTrue(token.transferFrom(deployer, bob, SUPPLY - 1));
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), type(uint256).max);

        vm.prank(bob);
        assertTrue(token.transfer(deployer, SUPPLY));
        vm.prank(deployer);
        assertTrue(token.approve(alice, 0));
        bytes32 beforeState = _stateDigest();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(_stateDigest(), beforeState);

        vm.prank(deployer);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 1));
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_approvalReplacementAndRevocationEmitExactValues() public {
        uint256[4] memory approvals = [type(uint256).max, uint256(7), uint256(3), uint256(0)];
        for (uint256 i; i < approvals.length; i++) {
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Approval(deployer, alice, approvals[i]);
            vm.prank(deployer);
            assertTrue(token.approve(alice, approvals[i]));
            assertEq(token.allowance(deployer, alice), approvals[i]);
            assertEq(token.balanceOf(deployer), SUPPLY);
        }
    }

    function test_zeroSpenderRejectedEvenForZeroApproval() public {
        uint256[3] memory amounts = [uint256(0), uint256(1), type(uint256).max];
        bytes32 beforeState = _stateDigest();
        for (uint256 i; i < amounts.length; i++) {
            vm.prank(deployer);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(deployer, address(0)), 0);
            assertEq(_stateDigest(), beforeState);
        }
    }

    function test_zeroRecipientRejectedEvenForZeroTransfer() public {
        uint256[3] memory amounts = [uint256(0), uint256(1), SUPPLY];
        bytes32 beforeState = _stateDigest();
        for (uint256 i; i < amounts.length; i++) {
            vm.prank(deployer);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transfer(address(0), amounts[i]);
            assertEq(_stateDigest(), beforeState);
        }
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_transferFromZeroRecipientRollsBackFiniteAllowanceAndCanRetry() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, SUPPLY));
        uint256[3] memory amounts = [uint256(0), uint256(1), SUPPLY];
        bytes32 beforeState = _stateDigest();
        for (uint256 i; i < amounts.length; i++) {
            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transferFrom(deployer, address(0), amounts[i]);
            assertEq(_stateDigest(), beforeState);
        }

        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, SUPPLY));
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.allowance(deployer, alice), 0);
    }

    function test_transferFromZeroRecipientPreservesInfiniteAllowance() public {
        vm.prank(deployer);
        assertTrue(token.approve(alice, type(uint256).max));
        bytes32 beforeState = _stateDigest();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(deployer, address(0), SUPPLY);
        assertEq(_stateDigest(), beforeState);
    }

    function test_transferFromZeroSourceCannotMintEvenWithZeroAmount() public {
        bytes32 beforeState = _stateDigest();
        vm.prank(alice);
        // Both the source and its approval are invalid; no particular validation order
        // is part of this property. Neither path may mint or succeed.
        vm.expectRevert();
        token.transferFrom(address(0), bob, 0);
        assertEq(_stateDigest(), beforeState);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_maxTransferAmountsRevertWithoutOverflowOrStateChanges() public {
        bytes32 beforeState = _stateDigest();
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transfer(bob, type(uint256).max);
        assertEq(_stateDigest(), beforeState);

        vm.prank(deployer);
        assertTrue(token.approve(alice, type(uint256).max));
        beforeState = _stateDigest();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        token.transferFrom(deployer, bob, type(uint256).max);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_approvalReplacementIsIsolated(uint256 initial, uint256 replacement) public {
        vm.startPrank(deployer);
        assertTrue(token.approve(alice, initial));
        assertTrue(token.approve(bob, 7));
        vm.stopPrank();
        vm.prank(carol);
        assertTrue(token.approve(alice, 11));
        vm.prank(deployer);
        assertTrue(token.approve(alice, replacement));

        assertEq(token.allowance(deployer, alice), replacement);
        assertEq(token.allowance(deployer, bob), 7);
        assertEq(token.allowance(carol, alice), 11);
        assertEq(token.allowance(alice, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_partitionedSpendsExhaustAllowanceAndCannotReplay(uint256 allowed, uint256 first) public {
        allowed = bound(allowed, 1, SUPPLY);
        first = bound(first, 0, allowed);
        vm.prank(deployer);
        assertTrue(token.approve(alice, allowed));
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, first));
        assertEq(token.allowance(deployer, alice), allowed - first);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, allowed - first));
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.balanceOf(bob), allowed);
        assertEq(token.balanceOf(deployer), SUPPLY - allowed);
        assertEq(token.totalSupply(), SUPPLY);

        bytes32 beforeState = _stateDigest();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(deployer, bob, 1);
        assertEq(_stateDigest(), beforeState);
    }

    function testFuzz_insufficientBalanceRollsBackAllowanceAndAllowsFundedRetry(uint256 held, uint256 requested)
        public
    {
        held = bound(held, 0, SUPPLY - 1);
        requested = bound(requested, held + 1, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.approve(bob, requested));
        bytes32 beforeState = _stateDigest();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        token.transferFrom(alice, carol, requested);
        assertEq(_stateDigest(), beforeState, "rejected transfer consumed allowance or changed balances");

        vm.prank(deployer);
        assertTrue(token.transfer(alice, requested - held));
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, requested));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), requested);
        assertEq(token.balanceOf(deployer), SUPPLY - requested);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_onlyApprovedSpenderCanPull(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.approve(alice, amount));
        bytes32 beforeState = _stateDigest();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        token.transferFrom(deployer, bob, amount);
        assertEq(_stateDigest(), beforeState);

        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, carol, amount));
        assertEq(token.allowance(deployer, alice), 0);
        assertEq(token.balanceOf(carol), amount);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
    }

    /// @dev Snapshot the complete tracked ledger, including unrelated allowances, for atomicity
    ///      assertions. It is never used to predict a successful call's expected balance.
    function _stateDigest() internal view returns (bytes32 digest) {
        address[4] memory accounts = [deployer, alice, bob, carol];
        digest =
            keccak256(abi.encode(token.totalSupply(), token.balanceOf(address(0)), token.balanceOf(address(token))));
        for (uint256 i; i < accounts.length; i++) {
            digest = keccak256(abi.encode(digest, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; j++) {
                digest = keccak256(abi.encode(digest, token.allowance(accounts[i], accounts[j])));
            }
        }
    }
}
