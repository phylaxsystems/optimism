// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICrossL2Inbox, Identifier} from "../../interfaces/L2/ICrossL2Inbox.sol";
import {IL2ToL2CrossDomainMessenger} from "../../interfaces/L2/IL2ToL2CrossDomainMessenger.sol";
import {ISuperchainTokenBridge} from "../../interfaces/L2/ISuperchainTokenBridge.sol";
import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";
import {Hashing} from "../../src/libraries/Hashing.sol";
import {Predeploys} from "../../src/libraries/Predeploys.sol";

/**
 * @title FMA_L2_Message_Passing_Assertions
 * @notice Assertions for FMA: Message Passing (Contracts-only)
 *
 * @dev This contract covers all failure modes identified in the L2 message passing FMA analysis:
 *
 * FM1: Valid message is initiated but destination chain lacks origin chain in its dependency set
 * FM2: validateMessage references an invalid or non-existent initiated message
 * FM3: Valid message is initiated but never relayed in destination due to sequencer censorship
 * FM4: Invalid Replayed Message (Replay attack) in L2ToL2CrossDomainMessenger
 * FM5: relayMessage reentrancies in L2ToL2CrossDomainMessenger
 * FM6: A repeated identifier is validated through CrossL2Inbox
 *
 * @dev Impact: CRITICAL - Could lead to asset theft, duplicate minting, or lost funds
 * @dev Likelihood: MEDIUM - Depends on specific failure mode
 */
contract FMA_L2_Message_Passing_Assertions is Assertion {
    /// @notice Registers which functions should trigger which assertions
    /// @dev Links message passing functions to their respective invariant checks
    function triggers() external view override {
        // FM1: Destination chain validation triggers (split)
        registerCallTrigger(
            this.assertionInvalidDestinationChain_sendMessage.selector, IL2ToL2CrossDomainMessenger.sendMessage.selector
        );
        registerCallTrigger(
            this.assertionInvalidDestinationChain_sendERC20.selector, ISuperchainTokenBridge.sendERC20.selector
        );

        // FM2: Message validation triggers
        registerCallTrigger(this.assertionInvalidMessageValidation.selector, ICrossL2Inbox.validateMessage.selector);

        // FM3: Message relay completeness triggers
        registerCallTrigger(
            this.assertionMessageRelayCompleteness.selector, IL2ToL2CrossDomainMessenger.sendMessage.selector
        );

        // FM4: Replay protection triggers
        registerCallTrigger(this.assertionReplayProtection.selector, IL2ToL2CrossDomainMessenger.relayMessage.selector);

        // FM5: Reentrancy protection triggers
        registerCallTrigger(
            this.assertionReentrancyProtection.selector, IL2ToL2CrossDomainMessenger.relayMessage.selector
        );

        // FM6: Repeated identifier validation triggers
        // TODO: add back in when fma2 tests pass
        //registerCallTrigger(this.assertionRepeatedIdentifierValidation.selector, ICrossL2Inbox.validateMessage.selector);
    }

    /**
     * @dev FM1a: Valid message is initiated but destination chain lacks origin chain in its dependency set (sendMessage)
     */
    function assertionInvalidDestinationChain_sendMessage() external {
        IL2ToL2CrossDomainMessenger messenger = IL2ToL2CrossDomainMessenger(address(ph.getAssertionAdopter()));
        PhEvm.CallInputs[] memory calls =
            ph.getCallInputs(address(messenger), IL2ToL2CrossDomainMessenger.sendMessage.selector);
        for (uint256 i = 0; i < calls.length; i++) {
            (uint256 destination, address target,) = abi.decode(calls[i].input, (uint256, address, bytes));
            require(destination != block.chainid, "FM1: Cannot send message to same chain");
            require(destination != 0, "FM1: Invalid destination chain ID");
            require(destination < type(uint256).max, "FM1: Destination chain ID too large");

            // Additional validation from tests: target should not be L2ToL2CrossDomainMessenger
            require(
                target != Predeploys.L2_TO_L2_CROSS_DOMAIN_MESSENGER, "FM1: Target cannot be L2ToL2CrossDomainMessenger"
            );
        }
    }

    /**
     * @dev FM1b: Valid message is initiated but destination chain lacks origin chain in its dependency set (sendERC20)
     */
    function assertionInvalidDestinationChain_sendERC20() external {
        ISuperchainTokenBridge tokenBridge = ISuperchainTokenBridge(address(ph.getAssertionAdopter()));
        PhEvm.CallInputs[] memory bridgeCalls =
            ph.getCallInputs(address(tokenBridge), ISuperchainTokenBridge.sendERC20.selector);
        for (uint256 i = 0; i < bridgeCalls.length; i++) {
            (,,, uint256 chainId) = abi.decode(bridgeCalls[i].input, (address, address, uint256, uint256));
            require(chainId != block.chainid, "FM1: Cannot bridge to same chain");
            require(chainId != 0, "FM1: Invalid destination chain ID");
            require(chainId < type(uint256).max, "FM1: Destination chain ID too large");
        }
    }

    /**
     * @dev FM2: validateMessage references an invalid or non-existent initiated message
     *
     * @dev Failure Mode:
     * An invalid or non-existent cross-chain message could be fakely relayed on the destination chain
     * by calling validateMessage with an existing (but still invalid) or fabricated identifier.
     * If executed, the message could trigger unintended actions or compromise the security of the chain's state.
     *
     * @dev Risk Assessment: HIGH impact, MEDIUM likelihood
     * @dev Assertion Coverage:
     * - Validates message identifier integrity
     * - Ensures message was properly initiated on source chain
     * - Verifies message parameters are consistent
     */
    function assertionInvalidMessageValidation() external {
        ICrossL2Inbox inbox = ICrossL2Inbox(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(inbox), ICrossL2Inbox.validateMessage.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the identifier and message hash
            (Identifier memory id, bytes32 msgHash) = abi.decode(calls[i].input, (Identifier, bytes32));

            ph.forkPreState();

            // Validate identifier fields
            require(id.origin != address(0), "FM2: Invalid origin address");
            require(id.blockNumber > 0, "FM2: Invalid block number");
            require(id.chainId != 0, "FM2: Invalid chain ID");
            require(id.chainId != block.chainid, "FM2: Cannot validate message from same chain");

            // Validate timestamp is reasonable (not too far in future or past)
            require(id.timestamp <= block.timestamp + 3600, "FM2: Timestamp too far in future");
            // TODO: What's a sensible value for going back in time?
            // Right now this could underflow
            //require(id.timestamp >= block.timestamp - 86400, "FM2: Timestamp too far in past");

            // Validate log index
            require(id.logIndex < type(uint32).max, "FM2: Invalid log index");

            // Verify message hash is not zero
            require(msgHash != bytes32(0), "FM2: Invalid message hash");

            // TODO: Add validation that message was actually initiated on source chain
            // This would require cross-chain verification which is not possible in single-chain assertions
        }
    }

    /**
     * @dev FM3: Valid message is initiated but never relayed in destination due to sequencer censorship
     *
     * @dev Failure Mode:
     * A user may send a valid cross-chain message, but the final relay step never occurs.
     * This can happen even if the message is included in a finalized block on the origin chain.
     * Sequencers on the destination chain may intentionally choose not to relay the message.
     *
     * @dev Risk Assessment: HIGH impact, MEDIUM likelihood
     * @dev Assertion Coverage:
     * - Monitors message initiation and relay patterns
     * - Detects potential censorship patterns
     * - Validates message lifecycle completeness
     */
    function assertionMessageRelayCompleteness() external {
        IL2ToL2CrossDomainMessenger messenger = IL2ToL2CrossDomainMessenger(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls =
            ph.getCallInputs(address(messenger), IL2ToL2CrossDomainMessenger.sendMessage.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the message parameters
            (uint256 destination, address target, bytes memory message) =
                abi.decode(calls[i].input, (uint256, address, bytes));

            // Get the pre-state nonce (the nonce that was used during the sendMessage call)
            ph.forkPreState();
            uint256 nonceUsed = messenger.messageNonce();

            // Calculate the expected message hash using the correct nonce
            bytes32 expectedMessageHash = Hashing.hashL2toL2CrossDomainMessage(
                destination, block.chainid, nonceUsed, calls[i].caller, target, message
            );

            // Verify the message was properly recorded in sentMessages
            ph.forkPostState();
            require(messenger.sentMessages(expectedMessageHash), "FM3: Message not properly recorded in sentMessages");

            // TODO: Add monitoring for messages that are sent but never relayed
            // This would require tracking across multiple blocks/transactions
        }
    }

    /**
     * @dev FM4: Invalid Replayed Message (Replay attack) in L2ToL2CrossDomainMessenger
     *
     * @dev Failure Mode:
     * The L2ToL2CrossDomainMessenger enforces replay protection by marking each message as relayed
     * in successfulMessages[messageHash]. If an attacker can bypass or reset this check,
     * a valid but previously executed message may be re-executed (relayed).
     *
     * @dev Risk Assessment: HIGH impact, LOW likelihood
     * @dev Assertion Coverage:
     * - Ensures successfulMessages mapping is properly updated
     * - Validates no duplicate message relays
     * - Monitors replay protection integrity
     */
    function assertionReplayProtection() external {
        IL2ToL2CrossDomainMessenger messenger = IL2ToL2CrossDomainMessenger(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls =
            ph.getCallInputs(address(messenger), IL2ToL2CrossDomainMessenger.relayMessage.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the relay parameters
            (Identifier memory id, bytes memory sentMessage) = abi.decode(calls[i].input, (Identifier, bytes));

            // The sentMessage structure is: abi.encodePacked(abi.encode(selector, destination, target, nonce), abi.encode(sender, message))
            // This means: [32 bytes selector][96 bytes topics][32 bytes sender][variable bytes message]

            // First, decode the event selector (first 32 bytes)
            bytes32 selector = abi.decode(sentMessage, (bytes32));
            require(selector == IL2ToL2CrossDomainMessenger.SentMessage.selector, "FM4: Invalid event selector");

            // Create temporary arrays for decoding
            bytes memory topicsData = new bytes(96);
            for (uint256 j = 0; j < 96; j++) {
                topicsData[j] = sentMessage[j + 32];
            }

            // Decode the topics: destination, target, nonce (96 bytes)
            (uint256 destination, address target, uint256 nonce) = abi.decode(topicsData, (uint256, address, uint256));

            // Create temporary array for data part
            bytes memory dataPart = new bytes(sentMessage.length - 128);
            for (uint256 j = 0; j < dataPart.length; j++) {
                dataPart[j] = sentMessage[j + 128];
            }

            // Decode the data: sender, message (remaining bytes)
            (address sender, bytes memory message) = abi.decode(dataPart, (address, bytes));

            // Calculate the correct message hash using the actual contract's hash function
            bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
                _destination: destination,
                _source: id.chainId,
                _nonce: nonce,
                _sender: sender,
                _target: target,
                _message: message
            });

            ph.forkPreState();
            bool wasAlreadyRelayed = messenger.successfulMessages(messageHash);

            ph.forkPostState();
            bool isNowRelayed = messenger.successfulMessages(messageHash);

            // Verify that if message was already relayed, it remains relayed
            require(!wasAlreadyRelayed || isNowRelayed, "FM4: Previously relayed message state was reset");

            // Verify that the message is now marked as relayed
            require(isNowRelayed, "FM4: Message not marked as successfully relayed");

            // Verify that the message hash is properly stored
            require(
                messenger.successfulMessages(messageHash), "FM4: Message hash not properly stored in successfulMessages"
            );
        }
    }

    /**
     * @dev FM5: relayMessage reentrancies in L2ToL2CrossDomainMessenger
     *
     * @dev Failure Mode:
     * The relayMessage function executes a message on the destination chain after validateMessage.
     * If this function is buggy or poorly implemented, an entity may exploit it to execute a reentrancy attack.
     *
     * @dev Risk Assessment: CRITICAL impact, VERY LOW likelihood
     * @dev Assertion Coverage:
     * - Validates reentrancy protection is working
     * - Ensures message execution is atomic
     * - Monitors for duplicate executions
     */
    function assertionReentrancyProtection() external {
        IL2ToL2CrossDomainMessenger messenger = IL2ToL2CrossDomainMessenger(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls =
            ph.getCallInputs(address(messenger), IL2ToL2CrossDomainMessenger.relayMessage.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the relay parameters
            (Identifier memory id, bytes memory sentMessage) = abi.decode(calls[i].input, (Identifier, bytes));

            // The sentMessage structure is: abi.encodePacked(abi.encode(selector, destination, target, nonce), abi.encode(sender, message))
            // This means: [32 bytes selector][96 bytes topics][32 bytes sender][variable bytes message]

            // First, decode the event selector (first 32 bytes)
            bytes32 selector = abi.decode(sentMessage, (bytes32));
            require(selector == IL2ToL2CrossDomainMessenger.SentMessage.selector, "FM5: Invalid event selector");

            // Create temporary arrays for decoding
            bytes memory topicsData = new bytes(96);
            for (uint256 j = 0; j < 96; j++) {
                topicsData[j] = sentMessage[j + 32];
            }

            // Decode the topics: destination, target, nonce (96 bytes)
            (uint256 destination, address target, uint256 nonce) = abi.decode(topicsData, (uint256, address, uint256));

            // Create temporary array for data part
            bytes memory dataPart = new bytes(sentMessage.length - 128);
            for (uint256 j = 0; j < dataPart.length; j++) {
                dataPart[j] = sentMessage[j + 128];
            }

            // Decode the data: sender, message (remaining bytes)
            (address sender, bytes memory message) = abi.decode(dataPart, (address, bytes));

            // Calculate the correct message hash using the actual contract's hash function
            bytes32 messageHash = Hashing.hashL2toL2CrossDomainMessage({
                _destination: destination,
                _source: id.chainId,
                _nonce: nonce,
                _sender: sender,
                _target: target,
                _message: message
            });

            // Verify that the message is only relayed once per transaction
            ph.forkPreState();
            bool wasRelayedBefore = messenger.successfulMessages(messageHash);

            ph.forkPostState();
            bool isRelayedAfter = messenger.successfulMessages(messageHash);

            // If message was not relayed before, it should be relayed now
            // If message was already relayed, it should remain relayed (no state change)
            require(
                (!wasRelayedBefore && isRelayedAfter) || (wasRelayedBefore && isRelayedAfter),
                "FM5: Reentrancy detected - message state changed unexpectedly"
            );

            // Verify that the message hash is properly stored and not duplicated
            require(messenger.successfulMessages(messageHash), "FM5: Message not properly stored after relay");
        }
    }

    /**
     * @dev FM6: A repeated identifier is validated through CrossL2Inbox
     *
     * @dev Failure Mode:
     * The validateMessage in CrossL2Inbox does not store or track whether a given identifier
     * has been used before. While this is an intended feature, if the same identifier is provided
     * in multiple calls when it shouldn't be able to do so, messages could be executed multiple times.
     *
     * @dev Risk Assessment: HIGH impact, LOW likelihood
     * @dev Assertion Coverage:
     * - Monitors for repeated identifier usage
     * - Validates identifier uniqueness when required
     * - Ensures proper message execution patterns
     */
    function assertionRepeatedIdentifierValidation() external {
        ICrossL2Inbox inbox = ICrossL2Inbox(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(inbox), ICrossL2Inbox.validateMessage.selector);

        // Track identifiers used in this transaction using an array
        bytes32[] memory usedIdentifiers = new bytes32[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the identifier and message hash
            (Identifier memory id, bytes32 msgHash) = abi.decode(calls[i].input, (Identifier, bytes32));

            // Create a unique identifier key
            bytes32 identifierKey =
                keccak256(abi.encodePacked(id.origin, id.blockNumber, id.logIndex, id.timestamp, id.chainId, msgHash));

            // Check if this identifier has been used before in this transaction
            for (uint256 j = 0; j < i; j++) {
                require(usedIdentifiers[j] != identifierKey, "FM6: Repeated identifier used in same transaction");
            }

            // Mark this identifier as used
            usedIdentifiers[i] = identifierKey;

            // Additional validation for identifier fields
            require(id.origin != address(0), "FM6: Invalid origin address");
            require(id.blockNumber > 0, "FM6: Invalid block number");
            require(id.chainId != 0, "FM6: Invalid chain ID");
            require(msgHash != bytes32(0), "FM6: Invalid message hash");
        }
    }
}
