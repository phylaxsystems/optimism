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

/// @title FMA_L2_Message_Passing_FM3_Test
/// @notice Tests for FMA3: L2ToL2CrossDomainMessenger.relayMessage() failure modes
/// @dev Tests various failure scenarios for the relayMessage function
contract FMA_L2_Message_Passing_FM3_Test is FMA_L2_Message_Passing_TestInit, CredibleTest {
    address alice = address(0x1234);
    IL2ToL2CrossDomainMessenger public assertionAdopter;
    FMA_L2_Message_Passing_Assertions public assertion;

    function setUp() public override {
        super.setUp();

        // Use L2ToL2CrossDomainMessenger as the assertion adopter for FM3 tests
        assertionAdopter = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        assertion = new FMA_L2_Message_Passing_Assertions();
    }

    /// @notice Tests FM3 assertion with valid message that gets properly recorded
    function test_FM3_MessageProperlyRecorded_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test parameters
        uint256 destination = block.chainid + 1; // Different chain
        address target = address(0x5678);
        bytes memory message = hex"12345678";

        // Test the assertion by calling sendMessage with valid parameters
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with multiple messages sent in sequence
    function test_FM3_MultipleMessagesProperlyRecorded_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Send multiple messages to test that each gets properly recorded
        uint256 destination = block.chainid + 1;
        address target1 = address(0x1111);
        address target2 = address(0x2222);
        bytes memory message1 = hex"1111";
        bytes memory message2 = hex"2222";

        // First message
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target1, message1)
        );

        // Second message
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target2, message2)
        );
    }

    /// @notice Tests FM3 assertion with different senders
    function test_FM3_DifferentSenders_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        address bob = address(0x9999);
        uint256 destination = block.chainid + 1;
        address target = address(0x8888);
        bytes memory message = hex"8888";

        // Send message from alice
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );

        // Send message from bob
        vm.prank(bob);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with different destinations
    function test_FM3_DifferentDestinations_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination1 = block.chainid + 1;
        uint256 destination2 = block.chainid + 2;
        address target = address(0x7777);
        bytes memory message = hex"7777";

        // Send message to destination1
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination1, target, message)
        );

        // Send message to destination2
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination2, target, message)
        );
    }

    /// @notice Tests FM3 assertion with empty message
    function test_FM3_EmptyMessage_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x6666);
        bytes memory message = ""; // Empty message

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with large message
    function test_FM3_LargeMessage_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x5555);
        bytes memory message = new bytes(1000); // Large message
        for (uint256 i = 0; i < 1000; i++) {
            message[i] = bytes1(uint8(i % 256));
        }

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with complex target address
    function test_FM3_ComplexTargetAddress_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0xDEADBEEF); // Complex address
        bytes memory message = hex"DEADBEEF";

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with high destination chain ID
    function test_FM3_HighDestinationChainId_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = type(uint256).max - 1; // High chain ID
        address target = address(0x4444);
        bytes memory message = hex"4444";

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with zero target address (edge case)
    function test_FM3_ZeroTargetAddress_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0); // Zero address
        bytes memory message = hex"0000";

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with message containing special characters
    function test_FM3_SpecialCharactersMessage_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x3333);
        bytes memory message = hex"ABCDEF0123456789"; // Special hex pattern

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with boundary destination chain ID
    function test_FM3_BoundaryDestinationChainId_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = 1; // Minimum valid chain ID
        address target = address(0x2222);
        bytes memory message = hex"2222";

        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with message that would normally fail but should still be recorded
    /// @dev This tests that even if the message would fail validation, it should still be recorded in sentMessages
    function test_FM3_MessageRecordedEvenIfValidationFails_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x1111);
        bytes memory message = hex"1111";

        // The assertion should pass even if the underlying contract would have validation issues
        // because we're testing that the message gets recorded, not that it gets relayed
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with rapid successive messages
    function test_FM3_RapidSuccessiveMessages_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x0001);
        bytes memory message = hex"0001";

        // Send multiple messages rapidly to test nonce handling and message recording
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            cl.validate(
                "FMA_L2_Message_Passing_Assertions",
                address(assertionAdopter),
                0,
                abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
            );
        }
    }

    /// @notice Tests FM3 assertion with very large message (stress test)
    function test_FM3_VeryLargeMessage_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x1111);
        bytes memory message = new bytes(10000); // Very large message
        for (uint256 i = 0; i < 10000; i++) {
            message[i] = bytes1(uint8(i % 256));
        }

        // The assertion should still validate that the message gets recorded
        // even with a very large message
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }

    /// @notice Tests FM3 assertion with mixed message content
    function test_FM3_MixedMessageContent_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 destination = block.chainid + 1;
        address target = address(0x1111);
        bytes memory message = abi.encodePacked(
            hex"0000000000000000000000000000000000000000000000000000000000000001", // uint256
            hex"0000000000000000000000001111111111111111111111111111111111111111", // address
            "Hello, World!", // string
            hex"ABCDEF0123456789" // mixed hex
        );

        // The assertion should still validate that the message gets recorded
        // even with complex mixed content
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.sendMessage.selector, destination, target, message)
        );
    }
}
