// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Testing
import {CommonTest} from "../../test/setup/CommonTest.sol";

// Contracts
import {Proxy} from "../../src/universal/Proxy.sol";

// Libraries
import {Constants} from "../../src/libraries/Constants.sol";
import {EIP1967Helper} from "../../test/mocks/EIP1967Helper.sol";
import {ForgeArtifacts, StorageSlot} from "../../scripts/libraries/ForgeArtifacts.sol";

// Interfaces
import {IETHLockbox} from "../../interfaces/L1/IETHLockbox.sol";
import {IProxyAdminOwnedBase} from "../../interfaces/L1/IProxyAdminOwnedBase.sol";
import {IOptimismPortal2} from "../../interfaces/L1/IOptimismPortal2.sol";

// Assertions
import {FMA_ETH_Lockbox_Assertions} from "../src/fma-eth-lockbox-assertions.a.sol";
import {CredibleTest} from "credible-std/CredibleTest.sol";

contract ETHLockbox_TestInit is CommonTest {
    error InvalidInitialization();

    event ETHLocked(IOptimismPortal2 indexed portal, uint256 amount);
    event ETHUnlocked(IOptimismPortal2 indexed portal, uint256 amount);
    event PortalAuthorized(IOptimismPortal2 indexed portal);
    event LockboxAuthorized(IETHLockbox indexed lockbox);
    event LiquidityMigrated(IETHLockbox indexed lockbox, uint256 amount);
    event LiquidityReceived(IETHLockbox indexed lockbox, uint256 amount);

    function setUp() public virtual override {
        super.setUp();

        // If not on the last upgrade network, we skip the test since the `ETHLockbox` won't be yet
        // deployed
        // TODO(#14691): Remove this check once Upgrade 15 is deployed on Mainnet.
        if (isForkTest() && !deploy.cfg().useUpgradedFork()) vm.skip(true);
    }
}

contract FMA_ETH_Lockbox_Assertions_Test is CredibleTest, ETHLockbox_TestInit {
    IETHLockbox public assertionAdopter;
    FMA_ETH_Lockbox_Assertions public assertion;

    function setUp() public override {
        super.setUp();

        assertionAdopter = ethLockbox;
        assertion = new FMA_ETH_Lockbox_Assertions();
    }

    function test_FMA_ETH_Lockbox_Paused_Assertion() public {
        cl.addAssertion(
            "FMA_ETH_Lockbox_Assertions",
            address(assertionAdopter),
            type(FMA_ETH_Lockbox_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        vm.mockCall(address(superchainConfig), abi.encodeWithSignature("paused(address)", address(0)), abi.encode(true));

        vm.prank(address(optimismPortal2));
        cl.validate(
            "FMA_ETH_Lockbox_Assertions",
            address(assertionAdopter),
            0,
            abi.encodeWithSelector(assertionAdopter.unlockETH.selector, 1 ether)
        );
    }

    function test_FMA_ETH_Lockbox_LockETH_Assertion() public {
        cl.addAssertion(
            "FMA_ETH_Lockbox_Assertions",
            address(assertionAdopter),
            type(FMA_ETH_Lockbox_Assertions).creationCode,
            abi.encode(address(assertionAdopter))
        );

        uint256 amountToLock = 10 ether;

        vm.deal(address(optimismPortal2), amountToLock + 1 ether);

        // vm.prank(proxyAdminOwner);
        // ethLockbox.authorizePortal(optimismPortal2);

        vm.prank(address(optimismPortal2));
        cl.validate(
            "FMA_ETH_Lockbox_Assertions",
            address(assertionAdopter),
            amountToLock,
            abi.encodeWithSelector(assertionAdopter.lockETH.selector)
        );
    }

    // Check if test works without cl.validate()
    function test_lockETH_succeeds() public {
        // Amount of ETH to lock
        uint256 amountToLock = 10 ether;

        vm.deal(address(optimismPortal2), amountToLock + 1 ether);

        // Get the balance of the portal and lockbox before the lock to compare later on the assertions
        uint256 portalBalanceBefore = address(optimismPortal2).balance;
        uint256 lockboxBalanceBefore = address(ethLockbox).balance;

        // Look for the emit of the `ETHLocked` event
        vm.expectEmit(address(ethLockbox));
        emit ETHLocked(optimismPortal2, amountToLock);

        // Call the `lockETH` function with the portal
        vm.prank(address(optimismPortal2));
        ethLockbox.lockETH{value: amountToLock}();

        // Assert the portal's balance decreased and the lockbox's balance increased by the
        // amount locked
        assertEq(address(optimismPortal2).balance, portalBalanceBefore - amountToLock);
        assertEq(address(ethLockbox).balance, lockboxBalanceBefore + amountToLock);
    }
}
