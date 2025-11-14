// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { OptionsBuilder } from "layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { LZBridgeTesting }                             from "src/testing/bridges/LZBridgeTesting.sol";
import { LZForwarder, ILayerZeroEndpointV2,
         MessagingParams, MessagingFee }               from "src/forwarders/LZForwarder.sol";
import { LZReceiver, Origin }                          from "src/receivers/LZReceiver.sol";
import { MessageSender }                               from "test/mocks/MessageSender.sol";
import { RecordedLogs }                                from "src/testing/utils/RecordedLogs.sol";

import "./IntegrationBase.t.sol";
import "./MonadLZConfigHelpers.sol";

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

        // Deploy MessageSender and etch it at authority addresses
        MessageSender senderImpl = new MessageSender();
        bytes memory senderCode = address(senderImpl).code;

        source.selectFork();
        vm.etch(sourceAuthority, senderCode);
        vm.deal(sourceAuthority, 1000 ether);
    }

    function _setupDestinationAuthority() internal {
        // Etch MessageSender at destinationAuthority on destination fork
        destination.selectFork();
        MessageSender senderImpl = new MessageSender();
        vm.etch(destinationAuthority, address(senderImpl).code);
        vm.deal(destinationAuthority, 1000 ether);
    }

    function test_base() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BASE;
        destinationEndpoint   = LZForwarder.ENDPOINT_BASE;

        initBaseContracts(getChain("base").createFork());
        _setupDestinationAuthority();
        executeTestingSequence();
    }

    function test_binance() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_BNB;
        destinationEndpoint   = LZForwarder.ENDPOINT_BNB;

        initBaseContracts(getChain("bnb_smart_chain").createFork());
        _setupDestinationAuthority();
        executeTestingSequence();
    }

    function test_monad() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_MONAD;
        destinationEndpoint   = LZForwarder.ENDPOINT_MONAD;

        initBaseContracts(getChain("monad").createFork());

        // Setup destinationAuthority as a MessageSender
        _setupDestinationAuthority();

        // MONAD-SPECIFIC WORKAROUND: Configure working DVNs to bypass placeholder deadDVNs
        // TODO: Remove this once Monad's LayerZero deployment is complete with real DVNs
        MonadLZConfigHelpers.configureMonadDefaults(
            source,
            destination,
            sourceAuthority,
            destinationAuthority
        );

        executeTestingSequence();
    }

    function test_plasma() public {
        destinationEndpointId = LZForwarder.ENDPOINT_ID_PLASMA;
        destinationEndpoint   = LZForwarder.ENDPOINT_PLASMA;

        initBaseContracts(getChain("plasma").createFork());
        _setupDestinationAuthority();
        executeTestingSequence();
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
        source.selectFork();

        // Gas to queue message
        vm.deal(sourceAuthority, 1 ether);
        deal(lzToken, sourceAuthority, 1 ether);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200_000, 0);

        assertEq(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertEq(address(sourceAuthority).balance,                    1 ether);

        // Calculate fee
        MessagingParams memory params = MessagingParams({
            dstEid:       destinationEndpointId,
            receiver:     bytes32(uint256(uint160(destinationReceiver))),
            message:      message,
            options:      options,
            payInLzToken: true
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
            true
        );

        // LZ token and ETH spent
        assertLt(IERC20(lzToken).balanceOf(address(sourceAuthority)), 1 ether);
        assertLt(address(sourceAuthority).balance,                    1 ether);
    }

    function queueDestinationToSource(bytes memory message) internal override {
        destination.selectFork();

        vm.deal(destinationAuthority, 1000 ether); // Gas to queue message

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
