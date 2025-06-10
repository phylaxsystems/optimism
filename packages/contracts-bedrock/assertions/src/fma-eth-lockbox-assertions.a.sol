// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IETHLockbox} from "../../interfaces/L1/IETHLockbox.sol";
import {IOptimismPortal2} from "../../interfaces/L1/IOptimismPortal2.sol";
import {Assertion} from "credible-std/Assertion.sol";
import {PhEvm} from "credible-std/PhEvm.sol";

contract FMA_ETH_Lockbox_Assertions is Assertion {
    IETHLockbox lockbox;

    /// @notice Registers which functions should trigger which assertions
    /// @dev Links deposit and withdraw functions to their respective invariant checks
    function triggers() external view override {
        registerCallTrigger(this.assertionLockETH.selector, lockbox.lockETH.selector);
        // ideally trigger on the ETHUnlocked event, but event triggers are not supported yet
        registerCallTrigger(this.assertionUnlockETH.selector, lockbox.unlockETH.selector);
        registerCallTrigger(this.assertionDrain.selector, lockbox.unlockETH.selector);
        // todo: find correct storage slot for the proxy
        // registerStorageChangeTrigger(this.assertionBuggyUpgrade.selector, 0x0);
    }

    function assertionLockETH() external {
        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(lockbox), lockbox.lockETH.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            address payable caller = payable(calls[i].caller);
            require(
                lockbox.authorizedPortals(IOptimismPortal2(caller)),
                "FM1: Unauthorized access to lockETH - caller is not an authorized portal"
            );
        }
    }

    /// @notice Asserts that unlockETH can only be called by authorized portals
    /// @dev This assertion verifies the access control mechanism for unlockETH
    function assertionUnlockETH() external {
        // Don't allow unlocking when the lockbox is paused
        // return as early as possible if paused, since unlockETH is not allowed when paused
        require(!lockbox.paused(), "FM1: Lockbox is paused");

        PhEvm.CallInputs[] memory calls = ph.getCallInputs(address(lockbox), lockbox.unlockETH.selector);

        for (uint256 i = 0; i < calls.length; i++) {
            address payable caller = payable(calls[i].caller);
            require(
                lockbox.authorizedPortals(IOptimismPortal2(caller)),
                "FM1: Unauthorized access to unlockETH - caller is not an authorized portal"
            );
        }
    }

    /// @notice Asserts that the lockbox cannot be drained in a single transaction
    /// @dev This assertion verifies that the lockbox cannot be drained in a single transaction
    function assertionDrain() external {
        // Don't allow draining when the lockbox is paused
        // return as early as possible if paused, since drain is not allowed when paused
        require(!lockbox.paused(), "FM1: Lockbox is paused");

        ph.forkPreState();

        // Get the current ETH balance of the lockbox
        uint256 balanceBefore = address(lockbox).balance;
        // if the balance is 0, there is nothing to drain
        if (balanceBefore == 0) return;

        ph.forkPostState();

        // Get the current ETH balance of the lockbox
        uint256 balanceAfter = address(lockbox).balance;

        // Don't allow balance to go to in one transaction
        // This is a primitive way to check this, and percentage based checks could be used for granularity
        require(balanceAfter > 0, "FM1: Lockbox balance is drained to 0");
    }

    // FM3: Buggy upgrade over the `ETHLockbox`
    // Impossible to check up front if a proxy upgrade is buggy
    // We can however check if for some reason the proxy is upgraded unexpectedly
    // function assertionBuggyUpgrade() external {
    //     ph.forkPreState();
    //     address preImplementationAddress = address(uint160(uint256(ph.load(address(lockbox), bytes32(0x0)))));

    //     address[] memory addresses = getStateChangesAddress(address(lockbox), bytes32(0x0));
    //     for (uint256 i = 0; i < addresses.length; i++) {
    //         if (addresses[i] != preImplementationAddress) {
    //             revert("FM3: Proxy implementation address has changed within transaction");
    //         }
    //     }
    // }
}
