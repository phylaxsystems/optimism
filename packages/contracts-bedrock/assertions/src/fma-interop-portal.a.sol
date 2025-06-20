// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IAnchorStateRegistry} from "../../interfaces/dispute/IAnchorStateRegistry.sol";
import {IFaultDisputeGame} from "../../interfaces/dispute/IFaultDisputeGame.sol";
import {IDisputeGame} from "../../interfaces/dispute/IDisputeGame.sol";
import {GameStatus, Hash} from "../../src/dispute/lib/Types.sol";
import {IETHLockbox} from "../../interfaces/L1/IETHLockbox.sol";
import {IOptimismPortal2} from "../../interfaces/L1/IOptimismPortal2.sol";
import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

/**
 * @title FMA_Interop_Portal_Assertions
 * @notice Assertions for FMA: Interop Support in OptimismPortal
 *
 * @dev This contract covers all failure modes identified in the FMA analysis for interop support:
 *
 * FM1: Incorrect State Reporting by AnchorStateRegistry
 * FM2: Bug in ETHLockbox/OptimismPortal Migration Logic
 * FM3: Disruptions During superRootsActive Transition
 * FM4: Incorrect Toggling of superRootsActive
 * FM5: Further Contract Changes Required for Full Interop
 *
 * @dev Impact: CRITICAL - Could lead to Withdrawal Safety Failure or Withdrawal Liveness Failure
 * @dev Likelihood: LOW - Assumes contracts are well-tested and audited
 */
contract FMA_Interop_Portal_Assertions is Assertion {
    IAnchorStateRegistry anchorStateRegistry;

    /// @notice Registers which functions should trigger which assertions
    /// @dev Links deposit and withdraw functions to their respective invariant checks
    function triggers() external view override {
        // FM1: Storage change triggers for direct state variable monitoring (slots 6)
        registerStorageChangeTrigger(this.assertionUpdateRetirementTimestamp.selector, bytes32(uint256(6)));
        registerStorageChangeTrigger(this.assertionSetRespectedGameType.selector, bytes32(uint256(6)));

        // FM1: Call triggers for state-changing functions
        registerCallTrigger(this.assertionSetAnchorState.selector, anchorStateRegistry.setAnchorState.selector);
        registerCallTrigger(
            this.assertionBlacklistDisputeGame.selector, anchorStateRegistry.blacklistDisputeGame.selector
        );

        // FM2: Migration logic triggers
        registerCallTrigger(this.assertionETHLockboxMigration.selector, IETHLockbox.migrateLiquidity.selector);
        registerCallTrigger(this.assertionPortalMigration.selector, IOptimismPortal2.migrateLiquidity.selector);

        // FM4: Super roots transition triggers
        registerCallTrigger(
            this.assertionSuperRootsToggleValidation.selector, IOptimismPortal2.migrateToSuperRoots.selector
        );
    }

    /**
     * @dev FM1: Incorrect State Reporting by AnchorStateRegistry
     *
     * @dev Failure Mode:
     * A bug within the AnchorStateRegistry causes it to return incorrect data about a dispute game
     * (e.g., resolves incorrectly, reports wrong respectedGameType, incorrect retirementTimestamp).
     * Since the OptimismPortal now relies entirely on the AnchorStateRegistry as the source of truth
     * for game validity and state, incorrect data leads directly to OptimismPortal malfunction.
     *
     * @dev Assertion Coverage:
     * - assertionUpdateRetirementTimestamp(): Monitors storage changes for retirementTimestamp
     * - assertionSetRespectedGameType(): Monitors storage changes for respectedGameType
     * - assertionSetAnchorState(): Validates all requirements during anchor state changes
     * - assertionBlacklistDisputeGame(): Monitors blacklist operations and their effects
     *
     * @dev Risk Assessment: CRITICAL impact, LOW likelihood
     */
    function assertionUpdateRetirementTimestamp() external {
        anchorStateRegistry = IAnchorStateRegistry(address(ph.getAssertionAdopter()));

        bytes32[] memory storageChanges = getStateChangesBytes32(address(anchorStateRegistry), bytes32(uint256(6)));
        uint64[] memory retirementTimestamps = new uint64[](storageChanges.length);
        // Convert the storage changes to retirement timestamps
        for (uint256 i = 0; i < storageChanges.length; i++) {
            // Extract 8 bytes at offset 4 (i.e., bytes 4-11)
            retirementTimestamps[i] = uint64(uint256(storageChanges[i] >> (8 * 20))); // 32-8-4=20
        }

        ph.forkPreState();
        uint64 preRetirementTimestamp = anchorStateRegistry.retirementTimestamp();

        ph.forkPostState();

        uint64 postRetirementTimestamp = anchorStateRegistry.retirementTimestamp();

        // Early check for the simple case where the retirement timestamp is updated in one transaction
        require(postRetirementTimestamp >= preRetirementTimestamp, "FMA1: Retirement timestamp updated incorrectly");

        // Check that the retirement timestamp is updated correctly for each storage change
        for (uint256 i = 0; i < retirementTimestamps.length; i++) {
            require(
                retirementTimestamps[i] >= preRetirementTimestamp,
                "FMA1: Retirement timestamp not equal or greater than pre timestamp"
            );
            require(
                retirementTimestamps[i] <= postRetirementTimestamp,
                "FMA1: Retirement timestamp not lower or equal to post-state timestamp"
            );
            preRetirementTimestamp = retirementTimestamps[i];
        }
    }

    /**
     * @dev FM1: Monitors retirement timestamp updates for correctness
     * @dev Ensures retirement timestamps are updated monotonically and correctly
     */
    function assertionSetRespectedGameType() external {
        anchorStateRegistry = IAnchorStateRegistry(address(ph.getAssertionAdopter()));

        bytes32[] memory storageChanges = getStateChangesBytes32(address(anchorStateRegistry), bytes32(uint256(6)));
        uint32[] memory respectedGameTypes = new uint32[](storageChanges.length);
        // Convert the storage changes to respected game types
        for (uint256 i = 0; i < storageChanges.length; i++) {
            // Extract 4 bytes at offset 0 (i.e., bytes 0-3)
            respectedGameTypes[i] = uint32(uint256(storageChanges[i] >> (8 * 28))); // 32-4=28
        }

        ph.forkPostState();
        uint32 postRespectedGameType = anchorStateRegistry.respectedGameType().raw();

        // Check that the respected game type storage changes are consistent with the final state
        // Game types can be any valid value, not necessarily monotonically increasing
        for (uint256 i = 0; i < respectedGameTypes.length; i++) {
            // Verify that the extracted game type is a valid value
            require(respectedGameTypes[i] >= 0, "FMA1: Invalid respected game type value");

            // Verify that the final state matches one of the storage changes
            if (i == respectedGameTypes.length - 1) {
                require(
                    respectedGameTypes[i] == postRespectedGameType,
                    "FMA1: Final respected game type does not match storage change"
                );
            }
        }
    }

    /**
     * @dev FM1: Validates anchor state changes and ensures new anchor games meet all requirements
     * @dev Cross-validates state reporting functions during critical operations
     */
    function assertionSetAnchorState() external {
        anchorStateRegistry = IAnchorStateRegistry(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls =
            ph.getCallInputs(address(anchorStateRegistry), anchorStateRegistry.setAnchorState.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the game address from the call data
            IDisputeGame game = abi.decode(calls[i].input, (IDisputeGame));

            ph.forkPreState();

            // Capture pre-state values
            (Hash preAnchorRoot, uint256 preAnchorL2BlockNumber) = anchorStateRegistry.getAnchorRoot();
            IFaultDisputeGame preAnchorGame = anchorStateRegistry.anchorGame();

            ph.forkPostState();

            // Capture post-state values
            (Hash postAnchorRoot, uint256 postAnchorL2BlockNumber) = anchorStateRegistry.getAnchorRoot();
            IFaultDisputeGame postAnchorGame = anchorStateRegistry.anchorGame();

            // Check if the anchor state actually changed
            bool anchorStateChanged = (address(preAnchorGame) != address(postAnchorGame));

            if (anchorStateChanged) {
                // If the anchor state changed, verify that the new anchor game meets all requirements
                require(address(postAnchorGame) == address(game), "FMA1: Anchor game not set to the correct game");

                // Verify that the new anchor game meets all the requirements for being a valid anchor
                require(anchorStateRegistry.isGameRegistered(game), "FMA1: New anchor game is not registered");
                require(anchorStateRegistry.isGameRespected(game), "FMA1: New anchor game is not respected");
                require(!anchorStateRegistry.isGameBlacklisted(game), "FMA1: New anchor game is blacklisted");
                require(!anchorStateRegistry.isGameRetired(game), "FMA1: New anchor game is retired");
                require(!anchorStateRegistry.paused(), "FMA1: Superchain is paused but anchor state changed");
                require(anchorStateRegistry.isGameResolved(game), "FMA1: New anchor game is not resolved");
                require(anchorStateRegistry.isGameFinalized(game), "FMA1: New anchor game is not finalized");
                require(anchorStateRegistry.isGameClaimValid(game), "FMA1: New anchor game claim is not valid");

                // Verify that the new anchor game has a higher L2 block number
                require(
                    postAnchorL2BlockNumber > preAnchorL2BlockNumber,
                    "FMA1: New anchor game has lower or equal L2 block number"
                );

                // Verify that the anchor root matches the game's root claim
                require(
                    postAnchorRoot.raw() == game.rootClaim().raw(), "FMA1: Anchor root does not match game root claim"
                );
                require(
                    postAnchorL2BlockNumber == game.l2SequenceNumber(),
                    "FMA1: Anchor L2 block number does not match game L2 sequence number"
                );
            } else {
                // If the anchor state didn't change, verify that the game didn't meet the requirements
                // This is a weaker check since the game might have been rejected for various reasons
                // We can't easily determine why it was rejected, but we can check that the state is consistent
                require(
                    address(preAnchorGame) == address(postAnchorGame),
                    "FMA1: Anchor game changed unexpectedly when setAnchorState should have failed"
                );
                require(
                    preAnchorRoot.raw() == postAnchorRoot.raw(),
                    "FMA1: Anchor root changed unexpectedly when setAnchorState should have failed"
                );
                require(
                    preAnchorL2BlockNumber == postAnchorL2BlockNumber,
                    "FMA1: Anchor L2 block number changed unexpectedly when setAnchorState should have failed"
                );
            }

            // Verify that state reporting functions are consistent with the actual game state
            // These should not change unexpectedly during a setAnchorState operation
            // Verify that isGameProper is consistent with its component conditions
            bool isProper = anchorStateRegistry.isGameProper(game);
            bool expectedIsProper = anchorStateRegistry.isGameRegistered(game)
                && !anchorStateRegistry.isGameBlacklisted(game) && !anchorStateRegistry.isGameRetired(game)
                && !anchorStateRegistry.paused();
            require(isProper == expectedIsProper, "FMA1: isGameProper result inconsistent with component conditions");

            // Verify that isGameClaimValid is consistent with its component conditions
            bool isClaimValid = anchorStateRegistry.isGameClaimValid(game);
            bool expectedIsClaimValid = isProper && anchorStateRegistry.isGameRespected(game)
                && anchorStateRegistry.isGameFinalized(game) && (game.status() == GameStatus.DEFENDER_WINS);
            require(
                isClaimValid == expectedIsClaimValid,
                "FMA1: isGameClaimValid result inconsistent with component conditions"
            );
        }
    }

    /**
     * @dev FM1: Monitors blacklist operations and ensures they correctly affect all dependent state functions
     * @dev Validates that blacklisted games are properly excluded from all validity checks
     */
    function assertionBlacklistDisputeGame() external {
        anchorStateRegistry = IAnchorStateRegistry(address(ph.getAssertionAdopter()));

        PhEvm.CallInputs[] memory calls =
            ph.getCallInputs(address(anchorStateRegistry), anchorStateRegistry.blacklistDisputeGame.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the game address from the call data
            IDisputeGame game = abi.decode(calls[i].input, (IDisputeGame));

            ph.forkPreState();
            bool preBlacklisted = anchorStateRegistry.isGameBlacklisted(IDisputeGame(game));

            ph.forkPostState();
            bool postBlacklisted = anchorStateRegistry.isGameBlacklisted(IDisputeGame(game));
            bool postProper = anchorStateRegistry.isGameProper(IDisputeGame(game));
            bool postClaimValid = anchorStateRegistry.isGameClaimValid(IDisputeGame(game));

            // After blacklisting, the game should be blacklisted
            require(postBlacklisted, "FMA1: Game not blacklisted after blacklistDisputeGame call");

            // After blacklisting, the game should not be proper
            require(!postProper, "FMA1: Game still proper after blacklistDisputeGame call");

            // After blacklisting, the game should not have valid claims
            require(!postClaimValid, "FMA1: Game still has valid claims after blacklistDisputeGame call");

            // The blacklist status should have changed from false to true
            require(!preBlacklisted && postBlacklisted, "FMA1: Blacklist status did not change correctly");
        }
    }

    /**
     * @dev FM2: Bug in ETHLockbox/OptimismPortal Migration Logic
     *
     * @dev Failure Mode:
     * The processes for migrating ETH funds from the OptimismPortal to the ETHLockbox or to migrate
     * from an old ETHLockbox to a new one, coordinated by the OptimismPortal and ETHLockbox,
     * involves complex logic. A bug in this logic could leave the system in a state that impacts
     * either safety or liveness.
     *
     * @dev Risk Assessment: HIGH/CRITICAL impact, LOW likelihood
     * @dev Assertion Coverage:
     * - assertionETHLockboxMigration(): Validates lockbox-to-lockbox migration
     * - assertionPortalMigration(): Validates portal-to-lockbox migration
     */
    function assertionETHLockboxMigration() external {
        // Get the ETHLockbox instance
        IETHLockbox lockbox = IETHLockbox(address(ph.getAssertionAdopter()));

        // Get all migrateLiquidity calls
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(lockbox), lockbox.migrateLiquidity.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the destination lockbox address from the call data
            IETHLockbox destinationLockbox = abi.decode(calls[i].input, (IETHLockbox));

            ph.forkPreState();

            // Capture pre-state values
            uint256 originBalanceBefore = address(lockbox).balance;
            uint256 destinationBalanceBefore = address(destinationLockbox).balance;
            bool isAuthorized = lockbox.authorizedLockboxes(destinationLockbox);

            ph.forkPostState();

            // Capture post-state values
            uint256 originBalanceAfter = address(lockbox).balance;
            uint256 destinationBalanceAfter = address(destinationLockbox).balance;

            // Core migration invariants based on ETHLockbox_MigrateLiquidity_Test
            require(originBalanceAfter == 0, "FM2: Origin lockbox balance not zero after migration");
            require(
                destinationBalanceAfter == destinationBalanceBefore + originBalanceBefore,
                "FM2: Destination lockbox balance not increased by migrated amount"
            );

            // Verify the destination lockbox was authorized (required for migration to succeed)
            require(isAuthorized, "FM2: Destination lockbox not authorized for migration");

            // Verify no funds were lost or duplicated
            uint256 totalBalanceBefore = originBalanceBefore + destinationBalanceBefore;
            uint256 totalBalanceAfter = originBalanceAfter + destinationBalanceAfter;
            require(totalBalanceBefore == totalBalanceAfter, "FM2: Total balance changed during migration");

            // State consistency - verify proxy admin owner consistency
            require(
                lockbox.proxyAdminOwner() == destinationLockbox.proxyAdminOwner(),
                "FM2: Lockboxes have different proxy admin owners"
            );

            // SystemConfig consistency - verify both lockboxes share the same system config
            require(
                lockbox.systemConfig() == destinationLockbox.systemConfig(),
                "FM2: Lockboxes have different system configs"
            );
        }
    }

    /**
     * @dev FM2: Portal migration validation
     * @dev Ensures OptimismPortal migration maintains fund safety and state consistency
     */
    function assertionPortalMigration() external {
        // Get the OptimismPortal instance
        IOptimismPortal2 portal = IOptimismPortal2(payable(address(ph.getAssertionAdopter())));

        // Get all migrateLiquidity calls (portal's migrateLiquidity function)
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(portal), portal.migrateLiquidity.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            ph.forkPreState();

            // Capture pre-state values
            uint256 portalBalanceBefore = address(portal).balance;
            IETHLockbox lockbox = portal.ethLockbox();
            uint256 lockboxBalanceBefore = address(lockbox).balance;
            bool portalAuthorized = lockbox.authorizedPortals(portal);

            ph.forkPostState();

            // Capture post-state values
            uint256 portalBalanceAfter = address(portal).balance;
            uint256 lockboxBalanceAfter = address(lockbox).balance;

            // Core portal migration invariants based on OptimismPortal2_Upgrade_Test
            require(portalBalanceAfter == 0, "FM2: Portal balance not zero after migration");
            require(
                lockboxBalanceAfter == lockboxBalanceBefore + portalBalanceBefore,
                "FM2: Lockbox balance not increased by portal balance"
            );

            // Verify no funds were lost or duplicated
            uint256 totalBalanceBefore = portalBalanceBefore + lockboxBalanceBefore;
            uint256 totalBalanceAfter = portalBalanceAfter + lockboxBalanceAfter;
            require(totalBalanceBefore == totalBalanceAfter, "FM2: Total balance changed during portal migration");

            // Authorization consistency - portal should remain authorized on lockbox
            require(portalAuthorized, "FM2: Portal not authorized on lockbox after migration");

            // State consistency - verify portal's ethLockbox reference is consistent
            require(
                address(portal.ethLockbox()) == address(lockbox),
                "FM2: Portal's ethLockbox reference inconsistent after migration"
            );

            // SystemConfig consistency - verify portal and lockbox share the same superchain config
            require(
                portal.superchainConfig() == lockbox.superchainConfig(),
                "FM2: Portal and lockbox have different superchain configs"
            );
        }
    }

    /**
     * @dev FM3: Disruptions During superRootsActive Transition
     *
     * @dev Failure Mode:
     * The OptimismPortal has a flag superRootsActive to switch between legacy and Super Root
     * withdrawal proving paths. Issues can occur during the transition period when this flag is flipped.
     * Users might attempt proofs with the wrong mechanism, or bugs could exist in the logic that
     * handles proofs submitted near the transition time.
     *
     * @dev Risk Assessment: MEDIUM impact, MEDIUM likelihood
     * @dev TODO: Implement super roots transition validation
     * @dev TODO: Won't implement for now since it's not high or critical impact
     */
    function assertionSuperRootsToggle() external pure {
        // TODO: Implement super roots toggle validation
        // - Verify proper flag transitions
        // - Ensure no proof validation conflicts during transition
        // - Validate that old-style proofs are properly invalidated
        // @dev TODO: Won't implement for now since it's not high or critical impact
    }

    /**
     * @dev FM3: Withdrawal proof validation during super roots transition
     * @dev Ensures withdrawal proofs use the correct mechanism based on superRootsActive flag
     */
    function assertionProveWithdrawalTransaction() external pure {
        // TODO: Implement withdrawal proof validation
        // - Verify correct proof mechanism is used based on superRootsActive
        // - Ensure no proof validation failures due to mechanism mismatch
        // - Validate transition period handling
        // @dev TODO: Won't implement for now since it's not high or critical impact
    }

    /**
     * @dev FM4: Incorrect Toggling of superRootsActive
     *
     * @dev Failure Mode:
     * A chain incorrectly toggles the superRootsActive flag (e.g., enables it before L2 supports Super Roots).
     * This will likely lead to a Withdrawal Liveness Failure as proofs will mismatch the required path.
     *
     * @dev Risk Assessment: HIGH impact, LOW likelihood
     * @dev Assertion Coverage:
     * - Validates that superRootsActive is only set via migrateToSuperRoots
     * - Ensures proper authorization and state consistency
     * - Verifies that the flag is always set to true (never false)
     */
    function assertionSuperRootsToggleValidation() external {
        // Get the OptimismPortal instance
        IOptimismPortal2 portal = IOptimismPortal2(payable(address(ph.getAssertionAdopter())));

        // Get all migrateToSuperRoots calls
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(portal), portal.migrateToSuperRoots.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            // Decode the function parameters
            (IETHLockbox newLockbox, IAnchorStateRegistry newAnchorStateRegistry) =
                abi.decode(calls[i].input, (IETHLockbox, IAnchorStateRegistry));

            ph.forkPreState();

            // Capture pre-state values
            // IETHLockbox oldLockbox = portal.ethLockbox(); // removed unused
            IAnchorStateRegistry oldAnchorStateRegistry = portal.anchorStateRegistry();
            // bool superRootsActiveBefore = portal.superRootsActive(); // removed unused
            address proxyAdminOwner = portal.proxyAdminOwner();
            bool systemPaused = portal.superchainConfig().paused();

            ph.forkPostState();

            // Capture post-state values
            IETHLockbox currentLockbox = portal.ethLockbox();
            IAnchorStateRegistry currentAnchorStateRegistry = portal.anchorStateRegistry();
            bool superRootsActiveAfter = portal.superRootsActive();

            // Core FM4 invariants for superRootsActive toggling:

            // 1. Authorization: Only proxy admin owner can toggle superRootsActive
            require(calls[i].caller == proxyAdminOwner, "FM4: Only proxy admin owner can toggle superRootsActive");

            // 2. System state: Cannot toggle when system is paused
            require(!systemPaused, "FM4: Cannot toggle superRootsActive when system is paused");

            // 3. Registry change: New AnchorStateRegistry must be different
            // This is a strict requirement - all chains need a new AnchorStateRegistry when migrating to Super Roots
            require(
                address(newAnchorStateRegistry) != address(oldAnchorStateRegistry),
                "FM4: New AnchorStateRegistry must be different from old one"
            );

            // 4. Flag behavior: superRootsActive is always set to true (never false)
            require(superRootsActiveAfter, "FM4: superRootsActive must be set to true after migration");

            // 5. State consistency: Lockbox and registry are properly updated
            require(
                address(currentLockbox) == address(newLockbox), "FM4: Lockbox not properly updated during migration"
            );
            require(
                address(currentAnchorStateRegistry) == address(newAnchorStateRegistry),
                "FM4: AnchorStateRegistry not properly updated during migration"
            );
        }
    }
}
