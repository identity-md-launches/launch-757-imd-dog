// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IMDOG} from "../src/IMDOG.sol";

/// @dev Local deployment probe only; no production factory or launch economics are implemented here.
contract TokenDeployer {
    function deploy(bytes32 salt) external returns (IMDOG) {
        return new IMDOG{salt: salt}();
    }
}

/// forge-config: default.fuzz.runs = 1000
contract IMDOGTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    address private constant DEPLOYER = address(0xD3);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant SPENDER = address(0x5EED);

    IMDOG private token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new IMDOG();
    }

    function test_MetadataAndInitialAllocation() public view {
        assertEq(token.name(), "IMD DOG");
        assertEq(token.symbol(), "IMDOG");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
    }

    function test_ConstructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), DEPLOYER, SUPPLY);
        vm.prank(DEPLOYER);
        new IMDOG();
    }

    function test_Create2MintsToFactoryRatherThanItsCaller() public {
        TokenDeployer factory = new TokenDeployer();
        bytes32 salt = keccak256("IMDOG local deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(IMDOG).creationCode))
                    )
                )
            )
        );

        vm.prank(ALICE);
        IMDOG deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
    }

    function test_TransferReturnsTrueAndEmitsExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(DEPLOYER, ALICE, 7 ether);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 7 ether));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 7 ether);
        assertEq(token.balanceOf(ALICE), 7 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FullSupplyCanMoveAndReturn() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalanceAndSupply() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(DEPLOYER, SUPPLY));
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transfer(address(0), 0);
    }

    function test_ApproveEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(DEPLOYER, SPENDER, 25 ether);
        vm.startPrank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 25 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 25 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
        assertEq(token.allowance(DEPLOYER, address(0)), 0);
    }

    function test_TransferFromSpendsFiniteAllowanceAndEmitsTransfer() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(DEPLOYER, ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 4 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 6 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 4 ether);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, BOB, 6 ether));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(BOB), 6 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceIsNotDecremented() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, SUPPLY));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromToSelfSpendsAllowanceWithoutChangingBalance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, DEPLOYER, 7));
        assertEq(token.allowance(DEPLOYER, SPENDER), 3);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromZeroSenderRevertsEvenForZeroAmount() public {
        // Allowance validation rejects the zero owner before the transfer is reached.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_TransferFromWithoutApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ApprovalIsSpecificToSpender() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, BOB, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromInsufficientAllowanceRevertsWithoutMutation() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 9, 10));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 10);
        assertEq(token.allowance(DEPLOYER, SPENDER), 9);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10);
        assertEq(token.allowance(ALICE, SPENDER), 10);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroReceiverRollsBackAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, address(0), 10);
        assertEq(token.allowance(DEPLOYER, SPENDER), 10);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_DeployerCannotSpendHolderBalanceWithoutApproval() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_CommonMintAndAdministrativeCallsAreUnavailable() public {
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[4] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[5] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[6] = abi.encodeWithSignature("pause()");
        calls[7] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[8] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[9] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[10] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[11] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[12] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[14] = abi.encodeWithSignature("issue(uint256)", 1);

        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        address[2] memory callers = [DEPLOYER, BOB];
        for (uint256 i; i < callers.length; ++i) {
            for (uint256 j; j < calls.length; ++j) {
                vm.prank(callers[i]);
                (bool success,) = address(token).call(calls[j]);
                assertFalse(success);
                assertEq(token.totalSupply(), SUPPLY);
                assertEq(token.balanceOf(ALICE), 100);
                assertEq(token.balanceOf(BOB), 0);
            }
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
    }

    function test_LaunchDistributionAndClaimTransferExactAmounts() public {
        address distributor = address(0xD157);
        address pool = address(0x9001);
        uint256 swarmShare = SUPPLY / 10;
        uint256 examplePoolShare = SUPPLY / 2;

        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(distributor, swarmShare));
        assertTrue(token.transfer(pool, examplePoolShare));
        assertTrue(token.transfer(BOB, SUPPLY - swarmShare - examplePoolShare));
        vm.stopPrank();
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(pool), examplePoolShare);
        assertEq(token.balanceOf(BOB), SUPPLY - swarmShare - examplePoolShare);

        vm.prank(distributor);
        assertTrue(token.transfer(ALICE, swarmShare));
        assertEq(token.balanceOf(ALICE), swarmShare);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RuntimeContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff);
        }
    }

    function testFuzz_TransfersConserveSupply(address recipient, uint256 amount) public {
        recipient = address(uint160(bound(uint160(recipient), 1, type(uint160).max)));
        if (recipient == DEPLOYER) recipient = ALICE;
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, amount)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransfersPreserveAccounting(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        vm.prank(DEPLOYER);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, spent));
        assertEq(token.allowance(DEPLOYER, SPENDER), approved - spent);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - spent);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OneWeiCanBeTransferredAndReturned() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferOnePastSupplyReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithoutMutation() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_AlmostMaximumApprovalIsFinite() public {
        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeReplacedAndRevoked() public {
        vm.startPrank(DEPLOYER);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 1));
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);

        vm.startPrank(DEPLOYER);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(SPENDER, 0));
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EmptyAccountApprovalSurvivesFailureAndWorksAfterFunding() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);

        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 1);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedAllowanceCannotBeReusedAfterBalanceRestored() public {
        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(DEPLOYER, ALICE, 1));
        vm.prank(ALICE);
        assertTrue(token.transfer(DEPLOYER, 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, ALICE, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferCannotBypassBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1)
        );
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, SUPPLY + 1);

        vm.prank(DEPLOYER);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(DEPLOYER, DEPLOYER, type(uint256).max);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.allowance(DEPLOYER, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalIsSpecificToOwner() public {
        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(ALICE, 1));
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(DEPLOYER, SPENDER), SUPPLY);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailurePreservesFiniteApprovalForRetry(uint256 held, uint256 amount, uint256 approved)
        public
    {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        approved = bound(approved, amount, type(uint256).max - 1);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, held));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approved));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approved);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);

        // Retry the identical spend after funding; no replacement approval is given.
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount - held));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.allowance(ALICE, SPENDER), approved - amount);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersMatchSingleTransfer(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 0, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        vm.prank(DEPLOYER);
        IMDOG splitToken = new IMDOG();
        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        assertTrue(splitToken.transfer(ALICE, firstPart));
        assertTrue(splitToken.transfer(ALICE, amount - firstPart));
        vm.stopPrank();
        assertEq(splitToken.balanceOf(ALICE), token.balanceOf(ALICE));
        assertEq(splitToken.balanceOf(DEPLOYER), token.balanceOf(DEPLOYER));
        assertEq(splitToken.totalSupply(), SUPPLY);

        vm.prank(ALICE);
        assertTrue(splitToken.transfer(DEPLOYER, amount));
        assertEq(splitToken.balanceOf(DEPLOYER), SUPPLY);
        assertEq(splitToken.balanceOf(ALICE), 0);
        assertEq(splitToken.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(uint256 original, uint256 replacement) public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 13));
        vm.startPrank(DEPLOYER);
        assertTrue(token.approve(BOB, 42));
        assertTrue(token.approve(SPENDER, original));
        assertEq(token.allowance(DEPLOYER, SPENDER), original);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(DEPLOYER, SPENDER), replacement);
        assertTrue(token.approve(SPENDER, replacement));
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, SPENDER), replacement);
        assertEq(token.allowance(DEPLOYER, BOB), 42);
        assertEq(token.allowance(ALICE, SPENDER), 13);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
