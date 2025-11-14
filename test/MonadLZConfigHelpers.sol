// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm } from "forge-std/Vm.sol";

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

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

/**
 * @notice Minimal interface for LayerZero endpoint configuration
 * @dev Defines only the methods needed for DVN configuration
 */
interface IEndpointConfig {
    function getSendLibrary(address sender, uint32 dstEid) external view returns (address lib);
    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external;
}

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
        configureSender(
            sourceAuthority,
            LZForwarder.ENDPOINT_ETHEREUM,
            LZForwarder.ENDPOINT_ID_MONAD,
            LZForwarder.DVN_ETHEREUM
        );
        configureSender(
            testContract,
            LZForwarder.ENDPOINT_ETHEREUM,
            LZForwarder.ENDPOINT_ID_MONAD,
            LZForwarder.DVN_ETHEREUM
        );

        // Configure Monad → Ethereum direction (reverse)
        monadFork.selectFork();
        configureSender(
            destinationAuthority,
            LZForwarder.ENDPOINT_MONAD,
            LZForwarder.ENDPOINT_ID_ETHEREUM,
            LZForwarder.DVN_MONAD
        );
        configureSender(
            testContract,
            LZForwarder.ENDPOINT_MONAD,
            LZForwarder.ENDPOINT_ID_ETHEREUM,
            LZForwarder.DVN_MONAD
        );
    }

    /**
     * @notice Configures a single sender for cross-chain communication
     * @dev Assumes the correct fork is already selected
     *
     * @param sender The address to configure as a sender
     * @param endpoint The LayerZero endpoint address
     * @param remoteEid The destination endpoint ID
     * @param dvn The DVN to use for verification
     */
    function configureSender(
        address sender,
        address endpoint,
        uint32 remoteEid,
        address dvn
    ) internal {
        address sendLib = IEndpointConfig(endpoint).getSendLibrary(address(0), remoteEid);

        address[] memory dvns = new address[](1);
        dvns[0] = dvn;

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations        : 15,
            requiredDVNCount     : 1,
            optionalDVNCount     : 0,
            optionalDVNThreshold : 0,
            requiredDVNs         : dvns,
            optionalDVNs         : new address[](0)
        });

        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = SetConfigParam({
            eid        : remoteEid,
            configType : 2,
            config     : abi.encode(ulnConfig)
        });

        vm.prank(sender);
        IEndpointConfig(endpoint).setConfig(sender, sendLib, configParams);
    }

}

