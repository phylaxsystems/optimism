// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// Testing
import {CommonTest} from "../../test/setup/CommonTest.sol";

// Contracts
import {Proxy} from "../../src/universal/Proxy.sol";

// Libraries
import {Constants} from "../../src/libraries/Constants.sol";
import {EIP1967Helper} from "../../test/mocks/EIP1967Helper.sol";
import {ForgeArtifacts, StorageSlot} from "../../scripts/libraries/ForgeArtifacts.sol";

// Interfaces
import {IAnchorStateRegistry} from "../../interfaces/dispute/IAnchorStateRegistry.sol";
import {IETHLockbox} from "../../interfaces/L1/IETHLockbox.sol";
import {IOptimismPortal2} from "../../interfaces/L1/IOptimismPortal2.sol";
import {IDisputeGame} from "../../interfaces/dispute/IDisputeGame.sol";
import {GameStatus, Hash, GameType, Timestamp} from "../../src/dispute/lib/Types.sol";

// Assertions
import {FMA_Interop_Portal_Assertions} from "../src/fma-interop-portal.a.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";

contract FMA_Interop_Portal_TestInit is CommonTest {
    error InvalidInitialization();

    function setUp() public virtual override {
        super.setUp();

        // If not on the last upgrade network, we skip the test since the contracts won't be yet deployed
        if (isForkTest() && !deploy.cfg().useUpgradedFork()) vm.skip(true);
    }
}

contract FMA_Interop_Portal_Assertions_Test is CredibleTest, FMA_Interop_Portal_TestInit {
    IOptimismPortal2 public assertionAdopter;
    FMA_Interop_Portal_Assertions public assertion;

    function setUp() public override {
        super.setUp();

        // OP test setup sets the fee to 1 gwei, which we currently don't handle
        // So we set it back to 0 for the assertions
        vm.fee(0);

        assertionAdopter = optimismPortal2;
        assertion = new FMA_Interop_Portal_Assertions();
    }

    // ============ FM1 Tests ============

    function test_FM1_SetAnchorState_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create a mock dispute game
        address mockGame = address(0x123);

        // Mock the anchor state registry to return proper values
        vm.mockCall(address(anchorStateRegistry), abi.encodeWithSignature("anchorGame()"), abi.encode(mockGame));

        vm.mockCall(
            address(anchorStateRegistry),
            abi.encodeWithSignature("getAnchorRoot()"),
            abi.encode(Hash.wrap(bytes32(0)), uint256(100))
        );

        // Test the assertion by calling setAnchorState
        vm.prank(proxyAdminOwner);
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(anchorStateRegistry.setAnchorState.selector, IDisputeGame(mockGame))
        );
    }

    function test_FM1_SetRespectedGameType_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Mock storage changes for respected game type
        vm.store(
            address(anchorStateRegistry),
            bytes32(uint256(6)), // slot 6 for respectedGameType
            bytes32(uint256(2)) // game type 2
        );

        // Test the assertion
        vm.prank(superchainConfig.guardian());
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(anchorStateRegistry.setRespectedGameType.selector, GameType.wrap(2))
        );
    }

    function test_FM1_BlacklistDisputeGame_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        address gameToBlacklist = address(0x456);

        // Mock the blacklist function
        vm.mockCall(
            address(anchorStateRegistry),
            abi.encodeWithSignature("isGameBlacklisted(address)", gameToBlacklist),
            abi.encode(true)
        );

        // Test the assertion
        vm.prank(superchainConfig.guardian());
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(anchorStateRegistry.blacklistDisputeGame.selector, IDisputeGame(gameToBlacklist))
        );
    }

    // ============ FM2 Tests ============

    function test_FM2_ETHLockboxMigration_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create a destination lockbox
        address destinationLockbox = address(0x789);

        // Fund the origin lockbox
        vm.deal(address(ethLockbox), 100 ether);

        // Mock authorization
        vm.mockCall(
            address(ethLockbox),
            abi.encodeWithSignature("authorizedLockboxes(address)", destinationLockbox),
            abi.encode(true)
        );

        // Test the assertion
        vm.prank(proxyAdminOwner);
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(ethLockbox.migrateLiquidity.selector, IETHLockbox(destinationLockbox))
        );
    }

    function test_FM2_PortalMigration_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Fund the portal
        vm.deal(address(optimismPortal2), 10 ether);

        // Test the assertion
        vm.prank(proxyAdminOwner);
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(optimismPortal2.migrateLiquidity.selector)
        );
    }

    // ============ FM4 Tests ============

    function test_FM4_SuperRootsToggle_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create new contracts for migration
        address newLockbox = address(0xABC);
        address newRegistry = address(0xDEF);

        // Mock the system to not be paused
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(false));

        // Mock current registry to be different from new one
        vm.mockCall(
            address(optimismPortal2),
            abi.encodeWithSignature("anchorStateRegistry()"),
            abi.encode(address(0x123)) // different from newRegistry
        );

        // Test the assertion
        vm.prank(proxyAdminOwner);
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(
                optimismPortal2.migrateToSuperRoots.selector, IETHLockbox(newLockbox), IAnchorStateRegistry(newRegistry)
            )
        );
    }

    function test_FM4_SuperRootsToggle_Unauthorized_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create new contracts for migration
        address newLockbox = address(0xABC);
        address newRegistry = address(0xDEF);

        // Test with unauthorized caller (should fail)
        vm.prank(address(0x999)); // not proxy admin owner
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(
                optimismPortal2.migrateToSuperRoots.selector, IETHLockbox(newLockbox), IAnchorStateRegistry(newRegistry)
            )
        );
    }

    function test_FM4_SuperRootsToggle_Paused_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create new contracts for migration
        address newLockbox = address(0xABC);
        address newRegistry = address(0xDEF);

        // Mock the system to be paused
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(true));

        // Test with paused system (should fail)
        vm.prank(proxyAdminOwner);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(
                optimismPortal2.migrateToSuperRoots.selector, IETHLockbox(newLockbox), IAnchorStateRegistry(newRegistry)
            )
        );
    }

    function test_FM4_SuperRootsToggle_SameRegistry_Assertion() public {
        cl.addAssertion(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            type(FMA_Interop_Portal_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        // Create new lockbox but reuse current registry
        address newLockbox = address(0xABC);
        address currentRegistry = address(0x123);

        // Mock current registry
        vm.mockCall(
            address(optimismPortal2), abi.encodeWithSignature("anchorStateRegistry()"), abi.encode(currentRegistry)
        );

        // Mock the system to not be paused
        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused()"), abi.encode(false));

        // Test with same registry (should fail)
        vm.prank(proxyAdminOwner);
        vm.expectRevert("Assertions Reverted");
        cl.validate(
            "FMA_Interop_Portal_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(
                optimismPortal2.migrateToSuperRoots.selector,
                IETHLockbox(newLockbox),
                IAnchorStateRegistry(currentRegistry)
            )
        );
    }
}
