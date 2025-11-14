// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {
    LZForwarder,
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingFee
} from "src/forwarders/LZForwarder.sol";

import { LZReceiver, Origin } from "src/receivers/LZReceiver.sol";

import { LZBridgeTesting } from "src/testing/bridges/LZBridgeTesting.sol";
import { RecordedLogs }    from "src/testing/utils/RecordedLogs.sol";

import { MessageSender } from "test/mocks/MessageSender.sol";

contract LZIntegrationTest is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    address sourceDVN = LZForwarder.DVN_ETHEREUM;
    address destinationDVN;

    Domain destination2;
    Bridge bridge2;

    error NoPeer(uint32 eid);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);

    function test_invalidEndpoint() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationDVN        = LZForwarder.DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(OnlyEndpoint.selector, randomAddress));
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsNoPeer() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationDVN        = LZForwarder.DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert(abi.encodeWithSelector(NoPeer.selector, 0));
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_lzReceive_revertsOnlyPeer() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationDVN        = LZForwarder.DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert(abi.encodeWithSelector(OnlyPeer.selector, sourceEndpointId, bytes32(uint256(uint160(randomAddress)))));
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_invalidSourceEid() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationDVN        = LZForwarder.DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        // NOTE: To pass initial check, we set the peer.
        vm.prank(makeAddr("owner"));
        LZReceiver(destinationReceiver).setPeer(0, bytes32(uint256(uint160(sourceAuthority))));

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("LZReceiver/invalid-srcEid");
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: 0,
                sender: bytes32(uint256(uint160(sourceAuthority))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_invalidSourceAuthority() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationDVN        = LZForwarder.DVN_BASE;
        initBaseContracts(getChain("base").createFork());

        destination.selectFork();

        // NOTE: To pass initial check, we set the peer.
        vm.prank(makeAddr("owner"));
        LZReceiver(destinationReceiver).setPeer(sourceEndpointId, bytes32(uint256(uint160(randomAddress))));

        vm.prank(bridge.destinationCrossChainMessenger);
        vm.expectRevert("LZReceiver/invalid-sourceAuthority");
        LZReceiver(destinationReceiver).lzReceive(
            Origin({
                srcEid: sourceEndpointId,
                sender: bytes32(uint256(uint160(randomAddress))),
                nonce:  1
            }),
            bytes32(0),
            abi.encodeCall(MessageOrdering.push, (1)),
            address(0),
            ""
        );
    }

    function test_base() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
        destinationDVN        = LZForwarder.DVN_BASE;

        runCrossChainTests(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BNB;
        destinationEndpoint   = LZForwarder.ENDPOINT_BNB;
        destinationDVN        = LZForwarder.DVN_BNB;

        runCrossChainTests(getChain("bnb_smart_chain").createFork());
    }

    function test_monad_t() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_MONAD;
        destinationEndpoint   = LZForwarder.ENDPOINT_MONAD;
        destinationDVN        = LZForwarder.DVN_MONAD;

        runCrossChainTests(getChain("monad").createFork());
    }

    function test_plasma() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_PLASMA;
        destinationEndpoint   = LZForwarder.ENDPOINT_PLASMA;
        destinationDVN        = LZForwarder.DVN_PLASMA;

        runCrossChainTests(getChain("plasma").createFork());
    }

    function initSourceReceiver() internal override returns (address) {
        MessageSender senderImpl = new MessageSender();
        vm.etch(sourceAuthority, address(senderImpl).code);
        vm.deal(sourceAuthority, 1000 ether);

        MessageSender(payable(sourceAuthority)).configureSender(
            sourceEndpoint,
            destinationEndpointId,
            sourceDVN
        );

        return address(new LZReceiver(
            sourceEndpoint,
            destinationEndpointId,
            bytes32(uint256(uint160(destinationAuthority))),
            address(moSource),
            makeAddr("delegate"),
            makeAddr("owner")
        ));
    }

    function initDestinationReceiver() internal override returns (address) {
        MessageSender senderImpl = new MessageSender();
        vm.etch(destinationAuthority, address(senderImpl).code);
        vm.deal(destinationAuthority, 1000 ether);

        MessageSender(payable(destinationAuthority)).configureSender(
            destinationEndpoint,
            sourceEndpointId,
            destinationDVN
        );

        return address(new LZReceiver(
            destinationEndpoint,
            sourceEndpointId,
            bytes32(uint256(uint160(sourceAuthority))),
            address(moDestination),
            makeAddr("delegate"),
            makeAddr("owner")
        ));
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return LZBridgeTesting.createLZBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        source.selectFork();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Calculate fee
        MessagingParams memory params = MessagingParams({
            dstEid:       destinationEndpointId,
            receiver:     bytes32(uint256(uint160(destinationReceiver))),
            message:      message,
            options:      options,
            payInLzToken: false
        });
        MessagingFee memory fee = ILayerZeroEndpointV2(bridge.sourceCrossChainMessenger).quote(params, sourceAuthority);

        // Call through the MessageSender contract (sourceAuthority)
        MessageSender(payable(sourceAuthority)).sendMessage{value: fee.nativeFee}(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver))),
            bridge.sourceCrossChainMessenger,
            message,
            options,
            sourceAuthority,
            false
        );
    }

    function queueDestinationToSource(bytes memory message) internal override {
        destination.selectFork();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        // Calculate fee
        MessagingParams memory params = MessagingParams({
            dstEid:       sourceEndpointId,
            receiver:     bytes32(uint256(uint160(sourceReceiver))),
            message:      message,
            options:      options,
            payInLzToken: false
        });
        MessagingFee memory fee = ILayerZeroEndpointV2(bridge.destinationCrossChainMessenger).quote(params, destinationAuthority);

        // Call through the MessageSender contract (destinationAuthority)
        MessageSender(payable(destinationAuthority)).sendMessage{value: fee.nativeFee}(
            sourceEndpointId,
            bytes32(uint256(uint160(sourceReceiver))),
            bridge.destinationCrossChainMessenger,
            message,
            options,
            destinationAuthority,
            false
        );
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true, sourceAuthority, destinationReceiver);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true, destinationAuthority, sourceReceiver);
    }

}
