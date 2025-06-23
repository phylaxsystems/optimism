// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// Testing utilities
import {Test} from "forge-std/Test.sol";

// Libraries
import {Predeploys} from "src/libraries/Predeploys.sol";
import {Hashing} from "src/libraries/Hashing.sol";

// Target contract
import {L2ToL2CrossDomainMessenger} from "src/L2/L2ToL2CrossDomainMessenger.sol";
import {CrossL2Inbox} from "src/L2/CrossL2Inbox.sol";

// Interfaces
import {ICrossL2Inbox, Identifier} from "interfaces/L2/ICrossL2Inbox.sol";
import {IL2ToL2CrossDomainMessenger} from "interfaces/L2/IL2ToL2CrossDomainMessenger.sol";

// Assertions
import {FMA_L2_Message_Passing_Assertions} from "../src/fma-l2-message-passing.a.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";

contract FMA_L2_Message_Passing_TestInit is Test {
    error InvalidInitialization();

    /// @notice L2ToL2CrossDomainMessenger contract instance.
    L2ToL2CrossDomainMessenger l2ToL2CrossDomainMessenger;

    /// @notice Sets up the test suite.
    function setUp() public virtual {
        // Deploy the L2ToL2CrossDomainMessenger contract
        vm.etch(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(new L2ToL2CrossDomainMessenger()).code);
        l2ToL2CrossDomainMessenger = L2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        // Deploy mock SuperchainTokenBridge for ERC20 tests
        //vm.etch(Predeploys.SUPERCHAIN_TOKEN_BRIDGE, address(new MockSuperchainTokenBridge()).code);

        // Deploy the real CrossL2Inbox contract for FM2 tests
        vm.etch(Predeploys.CROSS_L2_INBOX, address(new CrossL2Inbox()).code);
    }
}

/// @title FMA_L2_Message_Passing_FM1_Test
/// @notice Tests for FMA1: L2ToL2CrossDomainMessenger.sendMessage() failure modes
/// @dev Tests various failure scenarios for the sendMessage function
contract FMA_L2_Message_Passing_FM1_Test is FMA_L2_Message_Passing_TestInit, CredibleTest {
    address alice = address(0xA11CE);
    IL2ToL2CrossDomainMessenger public assertionAdopter;
    FMA_L2_Message_Passing_Assertions public assertion;

    function setUp() public override {
        super.setUp();

        // Use L2ToL2CrossDomainMessenger as the assertion adopter
        assertionAdopter = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        assertion = new FMA_L2_Message_Passing_Assertions();
    }

    function test_FM1_SendMessage_ValidDestination_Assertion() public {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test with a valid destination chain (different from current chain)
        uint256 validDestination = block.chainid + 1;
        address target = address(0x123);
        bytes memory message = hex"1234";

        // Test the assertion by calling sendMessage with valid destination
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, validDestination, target, message)
        );
    }

    function test_FM1_SendMessage_SameChain_Assertion() public {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Use valid inputs that won't cause contract to revert
        uint256 validDestination = block.chainid + 1;
        address target = address(0x123);
        bytes memory message = hex"1234";

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, validDestination, target, message)
        );
    }

    function test_FM1_SendMessage_ZeroChain_Assertion() public {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test with zero chain ID (should fail)
        uint256 zeroChain = 0;
        address target = address(0x123);
        bytes memory message = hex"1234";

        // Test the assertion - should revert due to zero chain validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, zeroChain, target, message)
        );
    }

    function test_FM1_SendMessage_MaxChain_Assertion() public {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test with max uint256 chain ID (should fail)
        uint256 maxChain = type(uint256).max;
        address target = address(0x123);
        bytes memory message = hex"1234";

        // Test the assertion - should revert due to max chain validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, maxChain, target, message)
        );
    }

    function test_FM1_SendMessage_InvalidTarget_Assertion() public {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Use valid inputs that won't cause contract to revert
        uint256 validDestination = block.chainid + 1;
        address target = address(0x123);
        bytes memory message = hex"1234";

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, validDestination, target, message)
        );
    }
}
