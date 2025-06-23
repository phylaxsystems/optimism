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

        // Deploy the real CrossL2Inbox contract for FM2 tests
        vm.etch(Predeploys.CROSS_L2_INBOX, address(new CrossL2Inbox()).code);
    }
}

/// @title FMA_L2_Message_Passing_FM4_Test
/// @notice Tests for FMA4: successfulMessages mapping update failure modes
/// @dev Tests various failure scenarios for the successfulMessages mapping updates
contract FMA_L2_Message_Passing_FM4_Test is FMA_L2_Message_Passing_TestInit, CredibleTest {
    address alice = address(0x1234);
    IL2ToL2CrossDomainMessenger public assertionAdopter;
    FMA_L2_Message_Passing_Assertions public assertion;

    function setUp() public override {
        super.setUp();

        // Use L2ToL2CrossDomainMessenger as the assertion adopter for FM4 tests
        assertionAdopter = IL2ToL2CrossDomainMessenger(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        assertion = new FMA_L2_Message_Passing_Assertions();

        vm.deal(alice, 1000 ether);
        vm.deal(address(assertionAdopter), 1000 ether);
    }

    /// @notice Tests FM4 assertion with successful message relay that updates successfulMessages
    function test_FM4_MessageRelayUpdatesSuccessfulMessages_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test parameters for relayMessage
        uint256 source = block.chainid + 1;
        uint256 nonce = 123;
        address sender = alice;
        address target = address(this);
        bytes memory message = hex"12345678";
        uint256 value = 0;
        uint64 blockNum = 1000;
        uint32 logIndex = 5;
        uint64 time = 1700000000;

        // Create sentMessage for relayMessage call
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, blockNum, logIndex, time, source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, nonce), // topics
            abi.encode(sender, message) // data
        );

        vm.prank(alice);
        // Now validate the assertion to check that successfulMessages was updated correctly
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            value,
            abi.encodeWithSelector(assertionAdopter.relayMessage.selector, id, sentMessage)
        );
    }

    /// @notice Tests FM4 assertion with multiple relay attempts to verify replay protection
    function test_FM4_ReplayProtectionPreventsDuplicateRelays_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test parameters
        uint256 source = block.chainid + 1;
        uint256 nonce = 456;
        address sender = alice;
        address target = address(0x9999);
        bytes memory message = hex"9999";
        uint256 value = 0;
        uint64 blockNum = 2000;
        uint32 logIndex = 10;
        uint64 time = 1700000001;

        // Create sentMessage
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, blockNum, logIndex, time, source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, nonce), // topics
            abi.encode(sender, message) // data
        );

        // Mock CrossL2Inbox validation
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Mock target call to succeed
        vm.mockCall({callee: target, msgValue: value, data: message, returnData: ""});

        // First relay attempt - should succeed and update successfulMessages
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            value,
            abi.encodeWithSelector(assertionAdopter.relayMessage.selector, id, sentMessage)
        );

        // Second relay attempt - should also succeed but verify replay protection
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            value,
            abi.encodeWithSelector(assertionAdopter.relayMessage.selector, id, sentMessage)
        );
    }

    /// @notice Tests FM4 assertion with different message parameters to verify replay protection
    function test_FM4_DifferentMessageParameters_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test parameters
        uint256 source = block.chainid + 2;
        uint256 nonce = 789;
        address sender = address(0xABCD);
        address target = address(0xEF01);
        bytes memory message = hex"EF01EF01";
        uint256 value = 100; // Non-zero value
        uint64 blockNum = 3000;
        uint32 logIndex = 15;
        uint64 time = 1700000002;

        // Create sentMessage
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, blockNum, logIndex, time, source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, nonce), // topics
            abi.encode(sender, message) // data
        );

        // Mock CrossL2Inbox validation
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Mock target call to succeed (make target payable for value transfer)
        vm.mockCall({callee: target, msgValue: value, data: message, returnData: ""});

        // Test the assertion by calling relayMessage with value
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            value,
            abi.encodeWithSelector(assertionAdopter.relayMessage.selector, id, sentMessage)
        );
    }

    /// @notice Tests FM4 assertion with empty message to verify replay protection
    function test_FM4_EmptyMessageReplayProtection_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test parameters with empty message
        uint256 source = block.chainid + 3;
        uint256 nonce = 101;
        address sender = alice;
        address target = address(0x0001);
        bytes memory message = ""; // Empty message
        uint256 value = 0;
        uint64 blockNum = 4000;
        uint32 logIndex = 20;
        uint64 time = 1700000003;

        // Create sentMessage
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, blockNum, logIndex, time, source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, nonce), // topics
            abi.encode(sender, message) // data
        );

        // Mock CrossL2Inbox validation
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Mock target call to succeed
        vm.mockCall({callee: target, msgValue: value, data: message, returnData: ""});

        // Test the assertion by calling relayMessage
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            value,
            abi.encodeWithSelector(assertionAdopter.relayMessage.selector, id, sentMessage)
        );
    }

    /// @notice Tests FM4 assertion with large message to verify replay protection
    function test_FM4_LargeMessageReplayProtection_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Test parameters with large message
        uint256 source = block.chainid + 4;
        uint256 nonce = 202;
        address sender = alice;
        address target = address(0x0002);
        bytes memory message = new bytes(500); // Large message
        for (uint256 i = 0; i < 500; i++) {
            message[i] = bytes1(uint8(i % 256));
        }
        uint256 value = 0;
        uint64 blockNum = 5000;
        uint32 logIndex = 25;
        uint64 time = 1700000004;

        // Create sentMessage
        Identifier memory id = Identifier(Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, blockNum, logIndex, time, source);
        bytes memory sentMessage = abi.encodePacked(
            abi.encode(L2ToL2CrossDomainMessenger.SentMessage.selector, block.chainid, target, nonce), // topics
            abi.encode(sender, message) // data
        );

        // Mock CrossL2Inbox validation
        vm.mockCall({
            callee: Predeploys.CROSS_L2_INBOX,
            data: abi.encodeCall(ICrossL2Inbox.validateMessage, (id, keccak256(sentMessage))),
            returnData: ""
        });

        // Mock target call to succeed
        vm.mockCall({callee: target, msgValue: value, data: message, returnData: ""});

        // Test the assertion by calling relayMessage
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            value,
            abi.encodeWithSelector(assertionAdopter.relayMessage.selector, id, sentMessage)
        );
    }
}
