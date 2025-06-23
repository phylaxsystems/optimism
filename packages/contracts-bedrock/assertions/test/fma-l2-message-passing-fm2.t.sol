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

/// ============ FM2 Tests ============
///         Currently all tests are failing with "Transaction reverted": Unknown Revert Reason
///         This makes it very hard to debug the issue.
///         The issue could be related to how isWarm is checking gas and the CL always using 0 gas a base fee

/// @title FMA_L2_Message_Passing_FM2_Test
/// @notice Tests for FMA2: CrossL2Inbox.validateMessage() failure modes
/// @dev Tests various failure scenarios for the validateMessage function
contract FMA_L2_Message_Passing_FM2_Test is FMA_L2_Message_Passing_TestInit, CredibleTest {
    address alice = address(0x1234);
    ICrossL2Inbox public assertionAdopter;
    FMA_L2_Message_Passing_Assertions public assertion;

    function setUp() public override {
        super.setUp();

        // Use CrossL2Inbox as the assertion adopter for FM2 tests
        assertionAdopter = ICrossL2Inbox(Predeploys.CROSS_L2_INBOX);
        assertion = new FMA_L2_Message_Passing_Assertions();
    }

    /// @notice Tests FM2 assertion with valid identifier fields
    function test_FM2_validIdentifier_succeeds() external {
        Identifier memory id;
        bytes32 msgHash = keccak256("valid message");

        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Set up valid identifier values
        id.origin = alice;
        id.blockNumber = 1000;
        id.logIndex = 5;
        id.timestamp = 1700000000; // Safe absolute timestamp value
        id.chainId = block.chainid + 1; // Different chain

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);

        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Optionally, read to ensure it's warm
        bytes32 value = vm.load(address(assertionAdopter), checksum);
        assertEq(value, bytes32(uint256(1)));

        // Test the assertion by calling validateMessage with valid identifier
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    // Test to make sure the validateMessage function is working and the setup is correct
    function test_validateMessage_succeeds() public {
        Identifier memory _id;
        bytes32 _messageHash = keccak256("valid message");

        // Set up valid identifier values
        _id.origin = alice;
        _id.blockNumber = 1000;
        _id.logIndex = 5;
        _id.timestamp = 1700000000; // Safe absolute timestamp value
        _id.chainId = block.chainid + 1; // Different chain

        // Calculate the checksum
        bytes32 checksum = assertionAdopter.calculateChecksum(_id, _messageHash);

        // First, write to the storage slot to make it warm
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Then read from it to ensure it's warm
        bytes32 value = vm.load(address(assertionAdopter), checksum);
        assertEq(value, bytes32(uint256(1)));

        vm.prank(alice);
        // Now call validateMessage - the slot should be warm
        assertionAdopter.validateMessage(_id, _messageHash);
    }

    /// @notice Tests FM2 assertion with invalid origin address (zero address)
    function test_FM2_invalidOrigin_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with invalid origin
        Identifier memory id = Identifier({
            origin: address(0), // Invalid: zero address
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 1700000000, // Safe absolute timestamp value
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to invalid origin validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with invalid block number (zero)
    function test_FM2_invalidBlockNumber_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with invalid block number
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 0, // Invalid: zero block number
            logIndex: 5,
            timestamp: 1700000000, // Safe absolute timestamp value
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to invalid block number validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with invalid chain ID (zero)
    function test_FM2_invalidChainId_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with invalid chain ID
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 1700000000, // Safe absolute timestamp value
            chainId: 0 // Invalid: zero chain ID
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to invalid chain ID validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with same chain ID (should revert)
    function test_FM2_sameChainId_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with same chain ID
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 1700000000, // Safe absolute timestamp value
            chainId: block.chainid // Invalid: same chain
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to same chain validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with invalid timestamp (too far in future)
    function test_FM2_timestampTooFarInFuture_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with timestamp too far in future
        // Since block.timestamp is 1, we need to use a value that's more than 1 hour ahead
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 4000, // More than 1 hour ahead of block.timestamp (1)
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to timestamp validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with invalid timestamp (too far in past)
    function test_FM2_timestampTooFarInPast_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with timestamp too far in past
        // Since block.timestamp is 1, we need to use a value that's more than 1 day behind
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 0, // More than 1 day behind block.timestamp (1)
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to timestamp validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with invalid log index (max value)
    function test_FM2_invalidLogIndex_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with invalid log index (use a value that won't cause calculateChecksum to fail)
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 1000000, // Large but valid value (less than 2^32)
            timestamp: 1700000000, // Safe absolute timestamp value
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to log index validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with invalid message hash (zero)
    function test_FM2_invalidMessageHash_reverts() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with valid fields
        Identifier memory id =
            Identifier({origin: alice, blockNumber: 1000, logIndex: 5, timestamp: 1700000000, chainId: 100});
        bytes32 msgHash = bytes32(0); // Invalid: zero message hash

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should revert due to message hash validation
        vm.prank(alice);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with valid timestamp at boundary (exactly 1 hour in future)
    function test_FM2_timestampBoundaryFuture_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with timestamp at the boundary
        // Since block.timestamp is 1, exactly 1 hour in future would be 3601
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 3601, // Exactly 1 hour in future (boundary)
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should pass boundary validation
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }

    /// @notice Tests FM2 assertion with valid timestamp at boundary (exactly 1 day in past)
    function test_FM2_timestampBoundaryPast_succeeds() external {
        cl.addAssertion(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            type(FMA_L2_Message_Passing_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create identifier with timestamp at the boundary
        // Since block.timestamp is 1, exactly 1 day in past would be -86399, but we can't use negative values
        // So we'll use a timestamp that's within the valid range
        Identifier memory id = Identifier({
            origin: alice,
            blockNumber: 1000,
            logIndex: 5,
            timestamp: 1, // Exactly at block.timestamp (boundary case)
            chainId: 100
        });
        bytes32 msgHash = keccak256("test message");

        // Warm the storage slot for CrossL2Inbox
        bytes32 checksum = assertionAdopter.calculateChecksum(id, msgHash);
        vm.store(address(assertionAdopter), checksum, bytes32(uint256(1)));

        // Test the assertion - should pass boundary validation
        vm.prank(alice);
        cl.validate(
            "FMA_L2_Message_Passing_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.validateMessage.selector, id, msgHash)
        );
    }
}
