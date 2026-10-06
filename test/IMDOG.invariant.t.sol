// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDOG} from "../src/IMDOG.sol";

/// @dev Every token stays within this closed set of actors, so their sum checks conservation.
contract IMDOGHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    IMDOG public immutable token;
    address[4] public actors = [address(0x1001), address(0x1002), address(0x1003), address(0x1004)];
    // These ledgers follow requested operations, never values returned by the token.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(IMDOG token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = SUPPLY / actors.length;
        }
    }

    function transfer(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[sender]);
        vm.prank(sender);
        assertTrue(token.transfer(recipient, amount));
        expectedBalance[sender] -= amount;
        expectedBalance[recipient] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        _approve(
            actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], infinite ? type(uint256).max : 0
        );
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner];
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        expectedAllowance[owner][spender] = allowed == type(uint256).max ? allowed : allowed - amount;
        assertEq(token.allowance(owner, spender), allowed == type(uint256).max ? allowed : allowed - amount);
    }

    // Rejected operations leave the ledgers unchanged. The invariants therefore
    // also check rollback of every actor's balances and every allowance pair.
    function transferOverBalance(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address sender = actors[senderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[sender];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, sender, balance, amount));
        vm.prank(sender);
        token.transfer(recipient, amount);
    }

    function transferFromOverBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amount,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        // Keep the finite branch below the infinite-approval sentinel.
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, recipient, amount);
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 approved) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Include revocation and one-past-allowance attempts without overflow.
        approved = bound(approved, 0, type(uint256).max - 1);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, approved + 1);
    }

    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract IMDOGInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    IMDOG private token;
    IMDOGHandler private handler;

    function setUp() public {
        token = new IMDOG();
        handler = new IMDOGHandler(token);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(handler.actors(i), SUPPLY / 4));
            handler.approve(i, (i + 1) % 4, SUPPLY / 4);
        }

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = IMDOGHandler.transfer.selector;
        selectors[1] = IMDOGHandler.approve.selector;
        selectors[2] = IMDOGHandler.transferFrom.selector;
        selectors[3] = IMDOGHandler.approveBoundary.selector;
        selectors[4] = IMDOGHandler.transferOverBalance.selector;
        selectors[5] = IMDOGHandler.transferFromOverBalance.selector;
        selectors[6] = IMDOGHandler.transferFromOverAllowance.selector;
        selectors[7] = IMDOGHandler.transferToZero.selector;
        selectors[8] = IMDOGHandler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_SupplyAndAggregateBalancesStayFixed() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_EachBalanceAndAllowanceMatchesRequestedOperations() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner), "wrong holder balance");
            assertEq(token.allowance(owner, address(0)), 0, "zero spender gained approval");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "wrong spending authority"
                );
            }
        }
    }

    function invariant_MetadataRemainsUnchanged() public view {
        assertEq(token.name(), "IMD DOG");
        assertEq(token.symbol(), "IMDOG");
        assertEq(token.decimals(), 18);
    }
}
