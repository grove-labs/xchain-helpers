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

    // Working DVN Addresses (NOT the placeholder deadDVNs)
    address private constant ETHEREUM_DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;  // Base/Plasma DVN
    address private constant MONAD_DVN    = 0x282b3386571f7f794450d5789911a9804FA346b4;  // LayerZero Labs DVN


    /**
     * @notice Configuration for the source chain (where messages are sent FROM)
     * @param fork The source chain domain
     * @param senderOapp The OApp contract that sends messages
     * @param refundAddress The authority address used for gas refunds
     * @param testSender The test contract (needs DVN config as it calls endpoint)
     * @param endpoint The LayerZero endpoint on source chain
     * @param remoteEid The destination endpoint ID
     * @param dvn The DVN to use for verification
     */
    struct SourceChainConfig {
        Domain fork;
        address refundAddress;
        address testSender;
        address endpoint;
        uint32 remoteEid;
        address dvn;
    }
    /**
     * @notice Configure working DVNs for Monad↔Ethereum route
     * @dev This function ONLY patches the Monad route's incomplete deployment.
     *      It configures bidirectional communication between Ethereum and Monad.
     *
     *      For each direction, we configure:
     *      - Send library + DVN for OApp, authority address, and test contract
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
        _configureDirection(
            SourceChainConfig({
                fork: ethereumFork,
                refundAddress: sourceAuthority,
                testSender: testContract,
                endpoint: LZForwarder.ENDPOINT_ETHEREUM,
                remoteEid: LZForwarder.ENDPOINT_ID_MONAD,
                dvn: ETHEREUM_DVN
            })
        );

        // Configure Monad → Ethereum direction (reverse)
        _configureDirection(
            SourceChainConfig({
                fork: monadFork,
                refundAddress: destinationAuthority,
                testSender: testContract,
                endpoint: LZForwarder.ENDPOINT_MONAD,
                remoteEid: LZForwarder.ENDPOINT_ID_ETHEREUM,
                dvn: MONAD_DVN
            })
        );
    }

    /**
     * @notice Configures one direction of cross-chain communication (source → destination)
     * @dev Configures send library + DVN for all addresses that need to send messages
     *
     * @param source Configuration for the source chain (where messages originate)
     */
    function _configureDirection(
        SourceChainConfig memory source
    ) private {
        // === CONFIGURE SOURCE CHAIN (for sending) ===
        source.fork.selectFork();

        address sendLib = IEndpointConfig(source.endpoint).getSendLibrary(address(0), source.remoteEid);

        // Set up ULN config with working DVN for source
        address[] memory sourceDvns = new address[](1);
        sourceDvns[0] = source.dvn;

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 15,
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: sourceDvns,
            optionalDVNs: new address[](0)
        });

        // Create config params array (same for all senders)
        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = SetConfigParam({
            eid: source.remoteEid,
            configType: 2,
            config: abi.encode(ulnConfig)
        });

        // Configure all addresses that interact with the endpoint
        vm.prank(source.refundAddress);
        IEndpointConfig(source.endpoint).setConfig(source.refundAddress, sendLib, configParams);

        vm.prank(source.testSender);
        IEndpointConfig(source.endpoint).setConfig(source.testSender, sendLib, configParams);
    }

}

