// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }                   from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder, ILayerZeroEndpointV2 } from "src/forwarders/LZForwarder.sol";
import { LZReceiver, Origin }                from "src/receivers/LZReceiver.sol";
import { RecordedLogs }                      from "src/testing/utils/RecordedLogs.sol";

import "./IntegrationBase.t.sol";

interface ITreasury {
    function setLzTokenEnabled(bool _lzTokenEnabled) external;
    function setLzTokenFee(uint256 _lzTokenFee) external;
}

contract LZIntegrationTestWithLZToken is IntegrationBaseTest {

    using DomainHelpers   for *;
    using LZBridgeTesting for *;
    using OptionsBuilder  for bytes;

    uint32 sourceEndpointId = LZForwarder.ENDPOINT_ID_ETHEREUM;
    uint32 destinationEndpointId;

    address sourceEndpoint = LZForwarder.ENDPOINT_ETHEREUM;
    address destinationEndpoint;

    address lzToken  = 0x6985884C4392D348587B19cb9eAAf157F13271cd;
    address lzOwner  = 0xBe010A7e3686FdF65E93344ab664D065A0B02478;
    address treasury = 0x5ebB3f2feaA15271101a927869B3A56837e73056;

    Domain destination2;
    Bridge bridge2;

    function setUp() public override {
        super.setUp();

        source.selectFork();

        vm.startPrank(lzOwner);
        ILayerZeroEndpointV2(sourceEndpoint).setLzToken(lzToken);
        ITreasury(treasury).setLzTokenEnabled(true);
        ITreasury(treasury).setLzTokenFee(1e18);
        vm.stopPrank();
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
        LZBridgeTesting.configureMonadDefaultDVNsAsAdmin(source, destination);

        // Run cross-chain tests
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
        // Gas to queue message
        vm.deal(sourceAuthority, 1 ether);
        deal(lzToken, sourceAuthority, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        assertEq(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertEq(address(sourceAuthority).balance,                    1 ether);

        LZForwarder.sendMessage(
            destinationEndpointId,
            bytes32(uint256(uint160(destinationReceiver))),
            ILayerZeroEndpointV2(bridge.sourceCrossChainMessenger),
            message,
            options,
            sourceAuthority,
            true
        );

        // LZ token and ETH spent
        assertLt(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertLt(address(sourceAuthority).balance,                    1 ether);
    }

    function queueDestinationToSource(bytes memory message) internal override {
        vm.deal(destinationAuthority, 1000 ether); // Gas to queue message

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
