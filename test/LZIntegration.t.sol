// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }                   from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder, ILayerZeroEndpointV2 } from "src/forwarders/LZForwarder.sol";
import { LZReceiver, Origin }                from "src/receivers/LZReceiver.sol";

import { RecordedLogs } from "src/testing/utils/RecordedLogs.sol";

contract LZIntegrationTest is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    Domain destination2;
    Bridge bridge2;

    error NoPeer(uint32 eid);
    error OnlyEndpoint(address addr);
    error OnlyPeer(uint32 eid, bytes32 sender);

    function test_invalidEndpoint() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;
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

        runCrossChainTests(getChain("base").createFork());
    }

    function test_binance() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BNB;
        destinationEndpoint   = LZForwarder.ENDPOINT_BNB;

        runCrossChainTests(getChain("bnb_smart_chain").createFork());
    }

    function test_monad() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_MONAD;
        destinationEndpoint   = LZForwarder.ENDPOINT_MONAD;

        initBaseContracts(getChain("monad").createFork());

        // Configure default DVN/Executor for Monad routes as LayerZero admin
        // This bypasses the placeholder DVNs by setting proper defaults
        LZBridgeTesting.configureMonadDefaultDVNsAsAdmin(source, destination);

        // Now run the cross-chain tests (same as runCrossChainTests but with the DVN config first)
        destination.selectFork();

        // Queue up some Destination -> Source messages
        vm.startPrank(destinationAuthority);
        queueDestinationToSource(abi.encodeCall(MessageOrdering.push, (3)));
        queueDestinationToSource(abi.encodeCall(MessageOrdering.push, (4)));
        vm.stopPrank();

        assertEq(moDestination.length(), 0);

        // Do not relay right away
        source.selectFork();

        // Queue up two more Source -> Destination messages
        vm.startPrank(sourceAuthority);
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (1)));
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (2)));
        vm.stopPrank();

        assertEq(moSource.length(), 0);

        relaySourceToDestination();

        assertEq(moDestination.length(), 2);
        assertEq(moDestination.messages(0), 1);
        assertEq(moDestination.messages(1), 2);

        relayDestinationToSource();

        assertEq(moSource.length(), 2);
        assertEq(moSource.messages(0), 3);
        assertEq(moSource.messages(1), 4);

        // Do one more message both ways to ensure subsequent calls don't repeat already sent messages
        vm.startPrank(sourceAuthority);
        queueSourceToDestination(abi.encodeCall(MessageOrdering.push, (5)));
        vm.stopPrank();

        relaySourceToDestination();

        assertEq(moDestination.length(), 3);
        assertEq(moDestination.messages(2), 5);

        vm.startPrank(destinationAuthority);
        queueDestinationToSource(abi.encodeCall(MessageOrdering.push, (6)));
        vm.stopPrank();

        relayDestinationToSource();

        assertEq(moSource.length(), 3);
        assertEq(moSource.messages(2), 6);
    }

    function test_plasma() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_PLASMA;
        destinationEndpoint   = LZForwarder.ENDPOINT_PLASMA;

        runCrossChainTests(getChain("plasma").createFork());
    }

    function initSourceReceiver() internal override returns (address) {
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
        vm.deal(sourceAuthority, 1000 ether);  // Gas to queue message

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        LZForwarder.sendMessage(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver))),
            ILayerZeroEndpointV2(bridge.sourceCrossChainMessenger),
            message,
            options,
            sourceAuthority,
            false
        );
    }

    function queueDestinationToSource(bytes memory message) internal override {
        vm.deal(destinationAuthority, 1000 ether);  // Gas to queue message

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        LZForwarder.sendMessage(
            sourceEndpointId,
            bytes32(uint256(uint160(sourceReceiver))),
            ILayerZeroEndpointV2(bridge.destinationCrossChainMessenger),
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
