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
     * @notice Configure working DVNs for Monad↔Ethereum route
     * @dev This function ONLY patches the Monad route's incomplete deployment.
     *      It sets default configurations that all OApps will inherit.
     *
     *      In the test environment, we configure both:
     *      1. The LZReceiver OApp contracts (for receiving messages)
     *      2. The test contract itself (for sending messages via LZForwarder)
     *
     * @param ethereumFork The Ethereum fork/domain
     * @param monadFork The Monad fork/domain
     */
    function configureMonadDefaults(
        Domain memory ethereumFork,
        address ethereumOapp,
        Domain memory monadFork,
        address monadOapp,
        address sourceAuthority,
        address destinationAuthority
    ) internal {
        // Get the test contract address (the caller of this library function)
        address testContract = address(this);

        // Configure the OApp on Ethereum to send to Monad and receive from Monad
        _configureDirection({
            fork      : ethereumFork,
            oapp      : ethereumOapp,
            endpoint  : LZForwarder.ENDPOINT_ETHEREUM,
            remoteEid : LZForwarder.ENDPOINT_ID_MONAD,
            receiveLib: LZForwarder.RECEIVE_LIBRARY_ETHEREUM,
            dvn       : ETHEREUM_DVN
        });

        // Configure the OApp on Monad to send to Ethereum and receive from Ethereum
        _configureDirection({
            fork      : monadFork,
            oapp      : monadOapp,
            endpoint  : LZForwarder.ENDPOINT_MONAD,
            remoteEid : LZForwarder.ENDPOINT_ID_ETHEREUM,
            receiveLib: LZForwarder.RECEIVE_LIBRARY_MONAD,
            dvn       : MONAD_DVN
        });

        // ALSO configure the test contract itself as a sender on BOTH chains
        // because in tests, LZForwarder.sendMessage is called from the test contract
        _configureDirection({
            fork      : ethereumFork,
            oapp      : testContract,
            endpoint  : LZForwarder.ENDPOINT_ETHEREUM,
            remoteEid : LZForwarder.ENDPOINT_ID_MONAD,
            receiveLib: LZForwarder.RECEIVE_LIBRARY_ETHEREUM,
            dvn       : ETHEREUM_DVN
        });

        _configureDirection({
            fork      : monadFork,
            oapp      : testContract,
            endpoint  : LZForwarder.ENDPOINT_MONAD,
            remoteEid : LZForwarder.ENDPOINT_ID_ETHEREUM,
            receiveLib: LZForwarder.RECEIVE_LIBRARY_MONAD,
            dvn       : MONAD_DVN
        });

        // ALSO configure the authority addresses (the refund addresses used in sendMessage)
        _configureDirection({
            fork      : ethereumFork,
            oapp      : sourceAuthority,
            endpoint  : LZForwarder.ENDPOINT_ETHEREUM,
            remoteEid : LZForwarder.ENDPOINT_ID_MONAD,
            receiveLib: LZForwarder.RECEIVE_LIBRARY_ETHEREUM,
            dvn       : ETHEREUM_DVN
        });

        _configureDirection({
            fork      : monadFork,
            oapp      : destinationAuthority,
            endpoint  : LZForwarder.ENDPOINT_MONAD,
            remoteEid : LZForwarder.ENDPOINT_ID_ETHEREUM,
            receiveLib: LZForwarder.RECEIVE_LIBRARY_MONAD,
            dvn       : MONAD_DVN
        });
    }

    /**
     * @notice Configures default DVNs for a given source/target direction.
     * @param fork Domain of the network to operate on (source side)
     * @param endpoint Address of the LayerZero endpoint whose send library will be mutated (on 'fork')
     * @param remoteEid The remote endpoint id this config will target
     * @param dvn Address of the working DVN for this direction
     */
    function _configureDirection(
        Domain  memory fork,
        address oapp,
        address endpoint,
        uint32  remoteEid,
        address receiveLib,
        address dvn
    ) private {
        fork.selectFork();

        address sendLib = ILayerZeroEndpointV2Admin(endpoint).getSendLibrary(address(0), remoteEid);

        // Set default ULN config with working DVN
        address[] memory dvns = new address[](1);
        dvns[0] = dvn;

        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = SetConfigParam({
            eid: remoteEid, configType: 2, config: abi.encode(UlnConfig({
                confirmations        : 15,
                requiredDVNCount     : 1,
                optionalDVNCount     : 0,
                optionalDVNThreshold : 0,
                requiredDVNs         : dvns,
                optionalDVNs         : new address[](0)
            }))});

        // Use the provided endpoint address directly
        address endpointAddr = endpoint;

        // First, explicitly set the send library for this OApp
        vm.prank(oapp);
        (bool libSuccess,) = endpointAddr.call(
            abi.encodeWithSignature(
                "setSendLibrary(address,uint32,address)",
                oapp,
                remoteEid,
                sendLib
            )
        );
        require(libSuccess, "setSendLibrary failed");

        // Configure send library (for outgoing messages)
        vm.prank(oapp);
        (bool success1,) = endpointAddr.call(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                oapp,
                sendLib,
                configParams
            )
        );
        require(success1, "setConfig for send library failed");

        // Configure receive library (for incoming messages)
        vm.prank(oapp);
        (bool success2,) = endpointAddr.call(
            abi.encodeWithSignature(
                "setConfig(address,address,(uint32,uint32,bytes)[])",
                oapp,
                receiveLib,
                configParams
            )
        );
        require(success2, "setConfig for receive library failed");
    }

}

