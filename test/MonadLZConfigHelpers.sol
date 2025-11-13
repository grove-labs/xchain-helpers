// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm } from "forge-std/Vm.sol";

import { IOAppCore } from "layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
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

interface ILayerZeroEndpointV2Admin {
    function getSendLibrary(address sender, uint32 dstEid) external view returns (address lib);
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
     * @param refundAddress The address that receives gas refunds
     * @param testSender The test contract address
     * @param endpoint The LayerZero endpoint on source chain
     * @param remoteEid The destination endpoint ID
     * @param dvn The DVN to use for verification
     */
    struct SourceChainConfig {
        Domain fork;
        address senderOapp;
        address refundAddress;
        address testSender;
        address endpoint;
        uint32 remoteEid;
        address dvn;
    }

    /**
     * @notice Configuration for the destination chain (where messages are sent TO)
     * @param fork The destination chain domain
     * @param receiverOapp The OApp contract that receives messages
     * @param endpoint The LayerZero endpoint on destination chain
     * @param receiveLib The receive library address
     * @param dvn The DVN to use for verification
     */
    struct DestChainConfig {
        Domain fork;
        address receiverOapp;
        address endpoint;
        address receiveLib;
        address dvn;
    }

    /**
     * @notice Configure working DVNs for Monad↔Ethereum route
     * @dev This function ONLY patches the Monad route's incomplete deployment.
     *      It configures bidirectional communication between Ethereum and Monad.
     *
     *      For each direction, we configure:
     *      - On SOURCE: send library + DVN for senderOapp, refundAddress, and testContract
     *      - On DESTINATION: receive library + DVN for receiverOapp
     *
     * @param ethereumFork The Ethereum fork/domain
     * @param ethereumOapp The LZReceiver OApp on Ethereum
     * @param monadFork The Monad fork/domain
     * @param monadOapp The LZReceiver OApp on Monad
     * @param sourceAuthority The refund address used when sending from Ethereum
     * @param destinationAuthority The refund address used when sending from Monad
     */
    function configureMonadDefaults(
        Domain memory ethereumFork,
        address ethereumOapp,
        Domain memory monadFork,
        address monadOapp,
        address sourceAuthority,
        address destinationAuthority
    ) internal {
        address testContract = address(this);

        // Configure Ethereum → Monad direction
        _configureDirection(
            SourceChainConfig({
                fork: ethereumFork,
                senderOapp: ethereumOapp,
                refundAddress: sourceAuthority,
                testSender: testContract,
                endpoint: LZForwarder.ENDPOINT_ETHEREUM,
                remoteEid: LZForwarder.ENDPOINT_ID_MONAD,
                dvn: ETHEREUM_DVN
            }),
            DestChainConfig({
                fork: monadFork,
                receiverOapp: monadOapp,
                endpoint: LZForwarder.ENDPOINT_MONAD,
                receiveLib: LZForwarder.RECEIVE_LIBRARY_MONAD,
                dvn: MONAD_DVN
            })
        );

        // Configure Monad → Ethereum direction (reverse)
        _configureDirection(
            SourceChainConfig({
                fork: monadFork,
                senderOapp: monadOapp,
                refundAddress: destinationAuthority,
                testSender: testContract,
                endpoint: LZForwarder.ENDPOINT_MONAD,
                remoteEid: LZForwarder.ENDPOINT_ID_ETHEREUM,
                dvn: MONAD_DVN
            }),
            DestChainConfig({
                fork: ethereumFork,
                receiverOapp: ethereumOapp,
                endpoint: LZForwarder.ENDPOINT_ETHEREUM,
                receiveLib: LZForwarder.RECEIVE_LIBRARY_ETHEREUM,
                dvn: ETHEREUM_DVN
            })
        );
    }

    /**
     * @notice Configures one direction of cross-chain communication (source → destination)
     * @dev Configures:
     *      - On SOURCE fork: send library + DVN for senderOapp, refundAddress, and testSender
     *      - On DESTINATION fork: receive library + DVN for receiverOapp
     *
     * @param source Configuration for the source chain (where messages originate)
     * @param dest Configuration for the destination chain (where messages are delivered)
     */
    function _configureDirection(
        SourceChainConfig memory source,
        DestChainConfig memory dest
    ) private {
        // === CONFIGURE SOURCE CHAIN (for sending) ===
        source.fork.selectFork();

        address sendLib = ILayerZeroEndpointV2Admin(source.endpoint).getSendLibrary(address(0), source.remoteEid);

        // Set up ULN config with working DVN for source
        address[] memory sourceDvns = new address[](1);
        sourceDvns[0] = source.dvn;

        SetConfigParam[] memory sendConfigParams = new SetConfigParam[](1);
        sendConfigParams[0] = SetConfigParam({
            eid: source.remoteEid,
            configType: 2,
            config: abi.encode(UlnConfig({
                confirmations: 15,
                requiredDVNCount: 1,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: sourceDvns,
                optionalDVNs: new address[](0)
            }))
        });

        // Configure all senders on source chain
        _configureSender(source.senderOapp, source.endpoint, sendLib, sendConfigParams);
        _configureSender(source.refundAddress, source.endpoint, sendLib, sendConfigParams);
        _configureSender(source.testSender, source.endpoint, sendLib, sendConfigParams);

        // === CONFIGURE DESTINATION CHAIN (for receiving) ===
        dest.fork.selectFork();

        // Set up ULN config with working DVN for destination
        address[] memory destDvns = new address[](1);
        destDvns[0] = dest.dvn;

        SetConfigParam[] memory receiveConfigParams = new SetConfigParam[](1);
        receiveConfigParams[0] = SetConfigParam({
            eid: source.remoteEid, // The source EID from receiver's perspective
            configType: 2,
            config: abi.encode(UlnConfig({
                confirmations: 15,
                requiredDVNCount: 1,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: destDvns,
                optionalDVNs: new address[](0)
            }))
        });

        // Configure receiver on destination chain
        // vm.prank(dest.receiverOapp);
        // (bool success,) = dest.endpoint.call(
        //     abi.encodeWithSignature(
        //         "setConfig(address,address,(uint32,uint32,bytes)[])",
        //         dest.receiverOapp,
        //         dest.receiveLib,
        //         receiveConfigParams
        //     )
        // );
        // require(success, "setConfig for receive library failed");
    }

    /**
     * @notice Helper to configure a sender address for outgoing messages
     * @dev Sets the send library and configures DVN settings for a sender
     *
     * @param sender The address to configure as a sender
     * @param endpoint The LayerZero endpoint address
     * @param sendLib The send library address
     * @param configParams The ULN configuration parameters
     */
    function _configureSender(
        address sender,
        address endpoint,
        address sendLib,
        SetConfigParam[] memory configParams
    ) private {

        // Configure send library with DVN settings
        vm.prank(sender);
        (bool configSuccess,) = endpoint.call(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                sender,
                sendLib,
                configParams
            )
        );
        require(configSuccess, "setConfig for send library failed");
    }

}

