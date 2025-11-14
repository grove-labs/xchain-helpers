// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm } from "forge-std/Vm.sol";

import { LZForwarder } from "src/forwarders/LZForwarder.sol";

import { Domain, DomainHelpers } from "src/testing/Domain.sol";

/**
 * @title MonadLZConfigHelpers
 * @notice TEMPORARY WORKAROUND for incomplete Monad LayerZero deployment
 * @dev This helper configures working DVNs for the Monad route,
 *      bypassing the placeholder "deadDVN" contracts that are currently deployed.
 *
 *      ISSUE: Monad's LayerZero endpoints have placeholder DVNs configured:
 *      - Ethereum > Monad: deadDVN at 0x747C741496a507E4B404b50463e691A8d692f6Ac
 *      - Monad > Ethereum: deadDVN at 0x6788f52439ACA6BFF597d3eeC2DC9a44B8FEE842
 *
 *      SOLUTION: This helper configures proper DVNs from the Monad deployment:
 *      - Ethereum: Uses Base/Plasma's working DVN
 *      - Monad: Uses LayerZero Labs DVN
 *
 *      TODO: Remove this helper once Monad's LayerZero integration is complete
 *      and real DVNs are configured as defaults.
 */

library MonadLZConfigHelpers {

    using DomainHelpers for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /**
     * @notice Configure working DVNs for Monad↔Ethereum route
     * @dev This function ONLY patches the Monad route's incomplete deployment.
     *      It configures bidirectional communication between Ethereum and Monad.
     *
     *      For each direction, we configure:
     *      - Send library + DVN for authority address and test contract
     *
     * @param ethereumFork The Ethereum fork/domain
     * @param monadFork The Monad fork/domain
     * @param sourceAuthority The authority address on Ethereum
     * @param destinationAuthority The authority address on Monad
     */
    function configureMonadDefaults(
        Domain memory ethereumFork,
        Domain memory monadFork,
        address sourceAuthority,
        address destinationAuthority
    ) internal {
        address testContract = address(this);

        // Configure Ethereum → Monad direction
        ethereumFork.selectFork();
        vm.startPrank(sourceAuthority);
        LZForwarder.configureSender(
            sourceAuthority,
            LZForwarder.ENDPOINT_ETHEREUM,
            LZForwarder.ENDPOINT_ID_MONAD,
            LZForwarder.DVN_ETHEREUM
        );
        vm.stopPrank();

        vm.startPrank(testContract);
        LZForwarder.configureSender(
            testContract,
            LZForwarder.ENDPOINT_ETHEREUM,
            LZForwarder.ENDPOINT_ID_MONAD,
            LZForwarder.DVN_ETHEREUM
        );
        vm.stopPrank();

        // Configure Monad → Ethereum direction (reverse)
        monadFork.selectFork();
        vm.startPrank(destinationAuthority);
        LZForwarder.configureSender(
            destinationAuthority,
            LZForwarder.ENDPOINT_MONAD,
            LZForwarder.ENDPOINT_ID_ETHEREUM,
            LZForwarder.DVN_MONAD
        );
        vm.stopPrank();

        vm.startPrank(testContract);
        LZForwarder.configureSender(
            testContract,
            LZForwarder.ENDPOINT_MONAD,
            LZForwarder.ENDPOINT_ID_ETHEREUM,
            LZForwarder.DVN_MONAD
        );
        vm.stopPrank();
    }

}

