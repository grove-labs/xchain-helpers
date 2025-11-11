// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { Vm } from "forge-std/Vm.sol";

import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { Bridge, BridgeType }    from "../Bridge.sol";
import { Domain, DomainHelpers } from "../Domain.sol";
import { RecordedLogs }          from "../utils/RecordedLogs.sol";
import { LZForwarder }           from "../../forwarders/LZForwarder.sol";

struct Origin {
    uint32  srcEid;
    bytes32 sender;
    uint64  nonce;
}

struct UlnConfig {
    uint64 confirmations;
    uint8 requiredDVNCount;
    uint8 optionalDVNCount;
    uint8 optionalDVNThreshold;
    address[] requiredDVNs;
    address[] optionalDVNs;
}

struct ExecutorConfig {
    uint32 maxMessageSize;
    address executor;
}

struct SetConfigParam {
    uint32 eid;
    uint32 configType;
    bytes config;
}

interface IEndpoint {
    function eid() external view returns (uint32);
    function verify(Origin calldata _origin, address _receiver, bytes32 _payloadHash) external;
    function lzReceive(
        Origin calldata _origin,
        address _receiver,
        bytes32 _guid,
        bytes calldata _message,
        bytes calldata _extraData
    ) external payable;

    function inboundNonce(address _receiver, uint32 _srcEid, bytes32 _sender) external view returns (uint64);
    function getSendLibrary(address sender, uint32 dstEid) external view returns (address lib);
    function getReceiveLibrary(address receiver, uint32 srcEid) external view returns (address lib, bool isDefault);
    function setConfig(address _oapp, address _lib, SetConfigParam[] calldata _params) external;
    function setDelegate(address _delegate) external;
    function setSendLibrary(address _oapp, uint32 _eid, address _newLib) external;
    function setReceiveLibrary(address _oapp, uint32 _eid, address _newLib, uint256 _gracePeriod) external;
    function owner() external view returns (address);
}

interface ISendLibAdmin {
    function setDefaultExecutorConfigs(SetDefaultExecutorConfigParam[] calldata _params) external;
    function setDefaultUlnConfigs(SetDefaultUlnConfigParam[] calldata _params) external;
}

struct SetDefaultExecutorConfigParam {
    uint32 eid;
    ExecutorConfig config;
}

struct SetDefaultUlnConfigParam {
    uint32 eid;
    UlnConfig config;
}

contract PacketBytesHelper {

    function srcEid(bytes calldata packetBytes) external pure returns (uint32) {
        return PacketV1Codec.srcEid(packetBytes);
    }

    function nonce(bytes calldata packetBytes) external pure returns (uint64) {
        return PacketV1Codec.nonce(packetBytes);
    }

    function dstEid(bytes calldata packetBytes) external pure returns (uint32) {
        return PacketV1Codec.dstEid(packetBytes);
    }

    function guid(bytes calldata packetBytes) external pure returns (bytes32) {
        return PacketV1Codec.guid(packetBytes);
    }

    function message(bytes calldata packetBytes) external pure returns (bytes memory) {
        return PacketV1Codec.message(packetBytes);
    }

}

library LZBridgeTesting {

    bytes32 private constant PACKET_SENT_TOPIC = keccak256("PacketSent(bytes,bytes,address)");

    using DomainHelpers for *;
    using RecordedLogs  for *;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function createLZBridge(Domain memory source, Domain memory destination) internal returns (Bridge memory bridge) {
        return init(Bridge({
            bridgeType:                     BridgeType.LZ,
            source:                         source,
            destination:                    destination,
            sourceCrossChainMessenger:      getLZEndpointFromChainAlias(source.chain.chainAlias),
            destinationCrossChainMessenger: getLZEndpointFromChainAlias(destination.chain.chainAlias),
            lastSourceLogIndex:             0,
            lastDestinationLogIndex:        0,
            extraData:                      abi.encode(getReceiveLibraryFromChainAlias(source.chain.chainAlias), getReceiveLibraryFromChainAlias(destination.chain.chainAlias))
        }));
    }

    function getLZEndpointFromChainAlias(string memory chainAlias) internal pure returns (address) {
        bytes32 name = keccak256(bytes(chainAlias));
               if (name == keccak256("mainnet")) {
            return LZForwarder.ENDPOINT_ETHEREUM;
        } else if (name == keccak256("avalanche")) {
            return LZForwarder.ENDPOINT_AVALANCHE;
        } else if (name == keccak256("base")) {
            return LZForwarder.ENDPOINT_BASE;
        } else if (name == keccak256("bnb_smart_chain")) {
            return LZForwarder.ENDPOINT_BNB;
        } else if (name == keccak256("monad")) {
            return LZForwarder.ENDPOINT_MONAD;
        } else if (name == keccak256("plasma")) {
            return LZForwarder.ENDPOINT_PLASMA;
        } else {
            revert("Unsupported chain");
        }
    }

    function getReceiveLibraryFromChainAlias(string memory chainAlias) internal pure returns (address) {
        bytes32 name = keccak256(bytes(chainAlias));
               if (name == keccak256("mainnet")) {
            return LZForwarder.RECEIVE_LIBRARY_ETHEREUM;
        } else if (name == keccak256("avalanche")) {
            return LZForwarder.RECEIVE_LIBRARY_AVALANCHE;
        } else if (name == keccak256("base")) {
            return LZForwarder.RECEIVE_LIBRARY_BASE;
        } else if (name == keccak256("bnb_smart_chain")) {
            return LZForwarder.RECEIVE_LIBRARY_BNB;
        } else if (name == keccak256("monad")) {
            return LZForwarder.RECEIVE_LIBRARY_MONAD;
        } else if (name == keccak256("plasma")) {
            return LZForwarder.RECEIVE_LIBRARY_PLASMA;
        } else {
            revert("Unsupported chain");
        }
    }

    function init(Bridge memory bridge) internal returns (Bridge memory) {
        RecordedLogs.init();

        // For consistency with other bridges
        bridge.source.selectFork();

        return bridge;
    }

    function relayMessagesToDestination(
        Bridge storage bridge,
        bool           switchToDestinationFork,
        address        sender,
        address        receiver
    ) internal {
        bridge.destination.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(true, PACKET_SENT_TOPIC, bridge.sourceCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            ( bytes memory encodedPacket,, ) = abi.decode(logs[i].data, (bytes, bytes, address));

            // Step 1: Parse data from encoded packet in event

            uint32 destinationEid = getDestinationEid(encodedPacket);
            bytes32 guid = getGuid(encodedPacket);
            bytes memory message = getMessage(encodedPacket);

            uint64 inboundNonce = IEndpoint(bridge.destinationCrossChainMessenger).inboundNonce(receiver, getSourceEid(encodedPacket), bytes32(uint256(uint160(sender))));

            if (destinationEid == IEndpoint(bridge.destinationCrossChainMessenger).eid()) {
                ( , address destinationReceiveLibrary ) = abi.decode(bridge.extraData, (address, address));
                bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));

                // Step 2: Prank as destinationReceiveLibrary to bypass DVN verification step, required before lzReceive can be called

                vm.startPrank(destinationReceiveLibrary);
                IEndpoint(bridge.destinationCrossChainMessenger).verify(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  inboundNonce + 1
                    }),
                    receiver,
                    payloadHash
                );
                vm.stopPrank();

                // Step 3: Call permissionless lzReceive on endpoint now that payload is verified

                IEndpoint(bridge.destinationCrossChainMessenger).lzReceive(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  inboundNonce + 1
                    }),
                    receiver,
                    guid,
                    message,
                    ""
                );
            }
        }

        if (!switchToDestinationFork) {
            bridge.source.selectFork();
        }
    }

    function relayMessagesToSource(
        Bridge storage bridge,
        bool           switchToSourceFork,
        address        sender,
        address        receiver
    ) internal {
        bridge.source.selectFork();

        Vm.Log[] memory logs = bridge.ingestAndFilterLogs(false, PACKET_SENT_TOPIC, bridge.destinationCrossChainMessenger);
        for (uint256 i = 0; i < logs.length; i++) {
            ( bytes memory encodedPacket,, ) = abi.decode(logs[i].data, (bytes, bytes, address));

            // Step 1: Parse data from encoded packet in event

            uint32 destinationEid = getDestinationEid(encodedPacket);  // NOTE: destinationEid in this case is for the source endpoint ID
            bytes32 guid = getGuid(encodedPacket);
            bytes memory message = getMessage(encodedPacket);
            uint64 inboundNonce = IEndpoint(bridge.sourceCrossChainMessenger).inboundNonce(receiver, getSourceEid(encodedPacket), bytes32(uint256(uint160(sender))));

            if (destinationEid == IEndpoint(bridge.sourceCrossChainMessenger).eid()) {
                ( address sourceReceiveLibrary, ) = abi.decode(bridge.extraData, (address, address));
                bytes32 payloadHash = keccak256(abi.encodePacked(guid, message));

                // Step 2: Prank as destinationReceiveLibrary to bypass DVN verification step, required before lzReceive can be called

                vm.startPrank(sourceReceiveLibrary);
                IEndpoint(bridge.sourceCrossChainMessenger).verify(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  inboundNonce + 1
                    }),
                    receiver,
                    payloadHash
                );
                vm.stopPrank();

                // Step 3: Call permissionless lzReceive on endpoint now that payload is verified

                IEndpoint(bridge.sourceCrossChainMessenger).lzReceive(
                    Origin({
                        srcEid: getSourceEid(encodedPacket),
                        sender: bytes32(uint256(uint160(sender))),
                        nonce:  inboundNonce + 1
                    }),
                    receiver,
                    guid,
                    message,
                    ""
                );
            }
        }

        if (!switchToSourceFork) {
            bridge.destination.selectFork();
        }
    }

    function getDestinationEid(bytes memory encodedPacket) public returns (uint32) {
        return new PacketBytesHelper().dstEid(encodedPacket);
    }

    function getGuid(bytes memory encodedPacket) public returns (bytes32) {
        return new PacketBytesHelper().guid(encodedPacket);
    }

    function getMessage(bytes memory encodedPacket) public returns (bytes memory) {
        return new PacketBytesHelper().message(encodedPacket);
    }

    function getSourceEid(bytes memory encodedPacket) public returns (uint32) {
        return new PacketBytesHelper().srcEid(encodedPacket);
    }

    function getNonce(bytes memory encodedPacket) public returns (uint64) {
        return new PacketBytesHelper().nonce(encodedPacket);
    }

    /// @dev Configure a working DVN for both source and destination OApps for chains with placeholder DVNs (e.g. Monad)
    /// @param sourceFork The source fork/domain
    /// @param destFork The destination fork/domain
    /// @param sourceOApp The source OApp address (e.g., test contract)
    /// @param destOApp The destination OApp address
    /// @param sourceEndpoint The source endpoint address
    /// @param destEndpoint The destination endpoint address
    /// @param sourceEid The source endpoint ID
    /// @param destEid The destination endpoint ID
    function configureBidirectionalDVN(
        Domain memory sourceFork,
        Domain memory destFork,
        address sourceOApp,
        address destOApp,
        address sourceEndpoint,
        address destEndpoint,
        uint32 sourceEid,
        uint32 destEid
    ) internal {
        // Use chain-specific DVNs:
        // Ethereum: Use Base/Plasma's working DVN
        address ethereumDVN = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b;
        address ethereumExecutor = 0x173272739Bd7Aa6e4e214714048a9fE699453059;

        // Monad: Use LayerZero Labs DVN (from deployment config)
        address monadDVN = 0x282b3386571f7f794450d5789911a9804FA346b4;
        address monadExecutor = 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b;

        // Configure source → destination (on source fork/chain - Ethereum)
        sourceFork.selectFork();

        // Get the send and receive libraries for the route
        address ethSendLib302 = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1; // SendUln302
        address ethReceiveLib302 = 0xc02Ab410f0734EFa3F14628780e6e695156024C2; // ReceiveUln302

        // Step 1: Set delegate
        vm.prank(sourceOApp);
        IEndpoint(sourceEndpoint).setDelegate(sourceOApp);

        // Step 2: Set send and receive libraries explicitly
        vm.prank(sourceOApp);
        IEndpoint(sourceEndpoint).setSendLibrary(sourceOApp, destEid, ethSendLib302);

        vm.prank(sourceOApp);
        IEndpoint(sourceEndpoint).setReceiveLibrary(sourceOApp, destEid, ethReceiveLib302, 0);

        // Step 3: Configure DVNs and Executor
        {
            address[] memory dvns = new address[](1);
            dvns[0] = ethereumDVN;

            SetConfigParam[] memory params = new SetConfigParam[](2);
            params[0] = SetConfigParam({
                eid: destEid,
                configType: 2,
                config: abi.encode(UlnConfig({
                    confirmations: 15,
                    requiredDVNCount: 1,
                    optionalDVNCount: 0,
                    optionalDVNThreshold: 0,
                    requiredDVNs: dvns,
                    optionalDVNs: new address[](0)
                }))
            });
            params[1] = SetConfigParam({
                eid: destEid,
                configType: 1,
                config: abi.encode(ExecutorConfig({
                    maxMessageSize: 10000,
                    executor: ethereumExecutor
                }))
            });

            vm.prank(sourceOApp);
            IEndpoint(sourceEndpoint).setConfig(sourceOApp, ethSendLib302, params);
        }

        // Configure destination → source (on destination fork/chain - Monad)
        destFork.selectFork();

        // Get Monad's send and receive libraries from deployment config
        address monadSendLib302 = 0xC39161c743D0307EB9BCc9FEF03eeb9Dc4802de7; // sendUln302
        address monadReceiveLib302 = 0xe1844c5D63a9543023008D332Bd3d2e6f1FE1043; // receiveUln302

        // Step 1: Set delegate
        vm.prank(destOApp);
        IEndpoint(destEndpoint).setDelegate(destOApp);

        // Step 2: Set send and receive libraries explicitly
        vm.prank(destOApp);
        IEndpoint(destEndpoint).setSendLibrary(destOApp, sourceEid, monadSendLib302);

        vm.prank(destOApp);
        IEndpoint(destEndpoint).setReceiveLibrary(destOApp, sourceEid, monadReceiveLib302, 0);

        // Step 3: Configure DVNs and Executor
        {
            address[] memory dvns = new address[](1);
            dvns[0] = monadDVN;

            SetConfigParam[] memory params = new SetConfigParam[](2);
            params[0] = SetConfigParam({
                eid: sourceEid,
                configType: 2,
                config: abi.encode(UlnConfig({
                    confirmations: 15,
                    requiredDVNCount: 1,
                    optionalDVNCount: 0,
                    optionalDVNThreshold: 0,
                    requiredDVNs: dvns,
                    optionalDVNs: new address[](0)
                }))
            });
            params[1] = SetConfigParam({
                eid: sourceEid,
                configType: 1,
                config: abi.encode(ExecutorConfig({
                    maxMessageSize: 10000,
                    executor: monadExecutor
                }))
            });

            vm.prank(destOApp);
            IEndpoint(destEndpoint).setConfig(destOApp, monadSendLib302, params);
        }
    }

    /// @dev Configure default DVNs and Executors for Monad routes as the LayerZero admin
    /// This sets the DEFAULT configuration that all OApps will inherit
    function configureMonadDefaultDVNsAsAdmin(
        Domain memory ethereumFork,
        Domain memory monadFork
    ) internal {
        address ethereumEndpoint = 0x1a44076050125825900e736c501f859c50fE728c;
        address monadEndpoint = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;

        address ethereumAdmin = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
        address monadAdmin = 0xE590a6730D7a8790E99ce3db11466Acb644c3942;

        uint32 ethereumEid = 30101;
        uint32 monadEid = 30390;

        // Configure Ethereum → Monad (on Ethereum chain as Ethereum admin)
        ethereumFork.selectFork();

        address ethSendLib = IEndpoint(ethereumEndpoint).getSendLibrary(address(0), monadEid);

        {
            // Set default DVN config for Ethereum → Monad route
            address[] memory dvns = new address[](1);
            dvns[0] = 0x589dEDbD617e0CBcB916A9223F4d1300c294236b; // Working Ethereum DVN

            SetDefaultUlnConfigParam[] memory ulnParams = new SetDefaultUlnConfigParam[](1);
            ulnParams[0] = SetDefaultUlnConfigParam({
                eid: monadEid,
                config: UlnConfig({
                    confirmations: 15,
                    requiredDVNCount: 1,
                    optionalDVNCount: 0,
                    optionalDVNThreshold: 0,
                    requiredDVNs: dvns,
                    optionalDVNs: new address[](0)
                })
            });

            vm.prank(ethereumAdmin);
            ISendLibAdmin(ethSendLib).setDefaultUlnConfigs(ulnParams);

            // Set default Executor config
            SetDefaultExecutorConfigParam[] memory execParams = new SetDefaultExecutorConfigParam[](1);
            execParams[0] = SetDefaultExecutorConfigParam({
                eid: monadEid,
                config: ExecutorConfig({
                    maxMessageSize: 10000,
                    executor: 0x173272739Bd7Aa6e4e214714048a9fE699453059
                })
            });

            vm.prank(ethereumAdmin);
            ISendLibAdmin(ethSendLib).setDefaultExecutorConfigs(execParams);
        }

        // Configure Monad → Ethereum (on Monad chain as Monad admin)
        monadFork.selectFork();

        address monadSendLib = IEndpoint(monadEndpoint).getSendLibrary(address(0), ethereumEid);

        {
            // Set default DVN config for Monad → Ethereum route
            address[] memory dvns = new address[](1);
            dvns[0] = 0x282b3386571f7f794450d5789911a9804FA346b4; // LayerZero Labs DVN on Monad

            SetDefaultUlnConfigParam[] memory ulnParams = new SetDefaultUlnConfigParam[](1);
            ulnParams[0] = SetDefaultUlnConfigParam({
                eid: ethereumEid,
                config: UlnConfig({
                    confirmations: 15,
                    requiredDVNCount: 1,
                    optionalDVNCount: 0,
                    optionalDVNThreshold: 0,
                    requiredDVNs: dvns,
                    optionalDVNs: new address[](0)
                })
            });

            vm.prank(monadAdmin);
            ISendLibAdmin(monadSendLib).setDefaultUlnConfigs(ulnParams);

            // Set default Executor config
            SetDefaultExecutorConfigParam[] memory execParams = new SetDefaultExecutorConfigParam[](1);
            execParams[0] = SetDefaultExecutorConfigParam({
                eid: ethereumEid,
                config: ExecutorConfig({
                    maxMessageSize: 10000,
                    executor: 0x4208D6E27538189bB48E603D6123A94b8Abe0A0b
                })
            });

            vm.prank(monadAdmin);
            ISendLibAdmin(monadSendLib).setDefaultExecutorConfigs(execParams);
        }
    }

}

interface ISendLibVerify {
    function getConfig(uint32 eid, address oapp, uint32 configType) external view returns (bytes memory);
}
