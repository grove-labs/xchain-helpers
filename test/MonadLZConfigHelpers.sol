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

struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
}

struct SetDefaultUlnConfigParam {
    uint32 eid;
    UlnConfig config;
}

interface ILayerZeroEndpointV2Admin {
    function getSendLibrary(address sender, uint32 dstEid) external view returns (address lib);
}

interface ISendLibAdmin {
    function setDefaultUlnConfigs(SetDefaultUlnConfigParam[] calldata _params) external;
}

library MonadLZConfigHelpers {

    using DomainHelpers for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    // LayerZero Admin Addresses
    address private constant ETHEREUM_ADMIN = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
    address private constant MONAD_ADMIN    = 0xE590a6730D7a8790E99ce3db11466Acb644c3942;

    // Working DVN Addresses (NOT the placeholder deadDVNs)
    address private constant ETHEREUM_DVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;  // Base/Plasma DVN
    address private constant MONAD_DVN    = 0x282b3386571f7f794450d5789911a9804FA346b4;  // LayerZero Labs DVN

    /**
     * @notice Configure working DVNs for Monad↔Ethereum route
     * @dev This function ONLY patches the Monad route's incomplete deployment.
     *      It sets default configurations that all OApps will inherit.
     * @param ethereumFork The Ethereum fork/domain
     * @param monadFork The Monad fork/domain
     */
    function configureMonadDefaults(
        Domain memory ethereumFork,
        Domain memory monadFork
    ) internal {
        _configureDirection({
            fork      : ethereumFork,
            endpoint  : LZForwarder.ENDPOINT_ETHEREUM,
            admin     : ETHEREUM_ADMIN,
            remoteEid : LZForwarder.ENDPOINT_ID_MONAD,
            dvn       : ETHEREUM_DVN
        });
        _configureDirection({
            fork      : monadFork,
            endpoint  : LZForwarder.ENDPOINT_MONAD,
            admin     : MONAD_ADMIN,
            remoteEid : LZForwarder.ENDPOINT_ID_ETHEREUM,
            dvn       : MONAD_DVN
        });
    }

    /**
     * @notice Configures default DVNs for a given source/target direction.
     * @param fork Domain of the network to operate on (source side)
     * @param endpoint Address of the LayerZero endpoint whose send library will be mutated (on 'fork')
     * @param admin Address to use for vm.prank and permissions
     * @param remoteEid The remote endpoint id this config will target
     * @param dvn Address of the working DVN for this direction
     */
    function _configureDirection(
        Domain  memory fork,
        address endpoint,
        address admin,
        uint32  remoteEid,
        address dvn
    ) private {
        fork.selectFork();

        address sendLib = ILayerZeroEndpointV2Admin(endpoint).getSendLibrary(address(0), remoteEid);

        // Set default ULN config with working DVN
        address[] memory dvns = new address[](1);
        dvns[0] = dvn;

        SetDefaultUlnConfigParam[] memory ulnParams = new SetDefaultUlnConfigParam[](1);
        ulnParams[0] = SetDefaultUlnConfigParam({
            eid    : remoteEid,
            config : UlnConfig({
                confirmations        : 15,
                requiredDVNCount     : 1,
                optionalDVNCount     : 0,
                optionalDVNThreshold : 0,
                requiredDVNs         : dvns,
                optionalDVNs         : new address[](0)
            })
        });

        vm.prank(admin);
        ISendLibAdmin(sendLib).setDefaultUlnConfigs(ulnParams);
    }

}

