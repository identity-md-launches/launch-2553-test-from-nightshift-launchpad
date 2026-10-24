// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {NightshiftTestToken} from "../src/NightshiftTestToken.sol";

/// @notice Drives successful and rejected calls among a closed set of actors.
/// @dev The expected ledger starts from the specified mint, and changes only from authorized
///      call inputs. Never copy observed token balances or allowances into the model: doing so
///      would hide a fee, a misdirected transfer, or an incorrect allowance update.
contract TokenHandler is Test {
    NightshiftTestToken public immutable token;
    address[] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(NightshiftTestToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 100 ether;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Exercise revocation, infinite approvals, practical finite limits, and the full
        // uint256 domain. Purely unrestricted approvals rarely reach small finite limits.
        uint256 mode = amount % 4;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = bound(amount, 0, 100 ether);
        _approve(owner, spender, amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 cap = expectedAllowance[owner][spender];
        uint256 bal = expectedBalance[owner];
        if (bal < cap) cap = bal;
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "transferFrom returned false");
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _move(owner, to, amount);
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        token.transfer(to, amount);
    }

    function transferFromOverLimit(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        // Exceed the tighter limit by one. This always makes a failing call, including
        // when the allowance is infinite, without overflow or a discarded fuzz input.
        if (allowed <= balance) {
            vm.prank(spender);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
            );
            token.transferFrom(owner, to, allowed + 1);
        } else {
            vm.prank(spender);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, balance + 1)
            );
            token.transferFrom(owner, to, balance + 1);
        }
        // No model update: the allowance deduction must also roll back on failure.
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 cap = expectedAllowance[owner][spender];
        if (expectedBalance[owner] < cap) cap = expectedBalance[owner];
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        assertEq(token.allowance(owner, address(0)), 0);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], 0);
    }

    /// @dev Try valid ABI encodings from the deployer as well as ordinary holders, interleaved
    ///      with transfers so any hidden administrative path cannot escape the ledger checks.
    function forbiddenCall(uint256 callerSeed, uint256 actionSeed, uint256 amount) external {
        address caller = actors[callerSeed % actors.length];
        address holder = actors[(callerSeed % actors.length + 1) % actors.length];
        bytes memory data;
        uint256 action = actionSeed % 8;
        if (action == 0) data = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        else if (action == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        else if (action == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        else if (action == 3) data = abi.encodeWithSignature("pause()");
        else if (action == 4) data = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        else if (action == 5) data = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        else if (action == 6) data = abi.encodeWithSignature("transferOwnership(address)", holder);
        else data = abi.encodeWithSignature("initialize(address)", holder);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        assertFalse(ok, "unexpected administrative entry point");
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "approve returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// @dev Every unexpected revert is a failure; expected reverts are consumed in the handler.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
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
        // Give every actor spendable funds through real transfers, maintaining the model.
        // No balances or approvals are installed through storage cheats.
        for (uint256 i = 1; i < actors.length; i++) {
            handler.transfer(0, i, 10 ether);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferOverBalance.selector;
        selectors[4] = TokenHandler.transferFromOverLimit.selector;
        selectors[5] = TokenHandler.transferToZero.selector;
        selectors[6] = TokenHandler.transferFromToZero.selector;
        selectors[7] = TokenHandler.approveZeroSpender.selector;
        selectors[8] = TokenHandler.revoke.selector;
        selectors[9] = TokenHandler.forbiddenCall.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
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

    function invariant_balancesMatchAuthorizedTransfers() public view {
        for (uint256 i; i < actors.length; i++) {
            assertEq(token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "incorrect holder balance");
        }
    }

    function invariant_allowancesMatchApprovalsAndSpends() public view {
        for (uint256 i; i < actors.length; i++) {
            for (uint256 j; j < actors.length; j++) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "incorrect allowance or failed-call rollback"
                );
            }
        }
    }

    function invariant_zeroAddressHasNoTokensOrApprovals() public view {
        assertEq(token.balanceOf(address(0)), 0);
        for (uint256 i; i < actors.length; i++) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }
}
