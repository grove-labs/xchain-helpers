// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./IntegrationBase.t.sol";

import { ArbitrumBridgeTesting }  from "src/testing/bridges/ArbitrumBridgeTesting.sol";
import { ArbitrumERC20Forwarder } from "src/forwarders/ArbitrumERC20Forwarder.sol";
import { ArbitrumReceiver }       from "src/receivers/ArbitrumReceiver.sol";
import { ArbitrumERC20ForwarderExecutor } from "./mocks/ArbitrumERC20ForwarderExecutor.sol";

contract ArbitrumERC20IntegrationTest is IntegrationBaseTest {

    using ArbitrumBridgeTesting for *;
    using DomainHelpers         for *;

    function initBaseContracts(Domain memory _destination) internal override {
        super.initBaseContracts(_destination);
    }

    function test_invalidSourceAuthority() public {
        setChain("plume", ChainData({
            name: "Plume",
            rpcUrl: vm.envString("PLUME_RPC_URL"),
            chainId: 98866
        }));
        initBaseContracts(getChain("plume").createFork());

        destination.selectFork();
        vm.expectRevert("ArbitrumReceiver/invalid-l1Authority");
        vm.prank(randomAddress);
        MessageOrdering(destinationReceiver).push(1);
    }

    function test_invalidL1CrossDomain() public {
        ArbitrumERC20ForwarderExecutor executor = new ArbitrumERC20ForwarderExecutor();

        vm.expectRevert("ArbitrumERC20Forwarder/invalid-l1-cross-domain");
        executor.sendMessageL1toL2(
            randomAddress,
            destinationReceiver,
            ""
        );
    }

    function test_plume() public {
        // Needed for arbitrum cross-chain messages
        source.selectFork();
        deal(ArbitrumERC20Forwarder.PLUME_GAS_TOKEN, sourceAuthority, 100 ether);
        deal(ArbitrumERC20Forwarder.PLUME_GAS_TOKEN, randomAddress,   100 ether);

        setChain("plume", ChainData({
            name: "Plume",
            rpcUrl: vm.envString("PLUME_RPC_URL"),
            chainId: 98866
        }));

        runCrossChainTests(getChain("plume").createFork());
    }

    function initSourceReceiver() internal override pure returns (address) {
        return address(0);
    }

    function initDestinationReceiver() internal override returns (address) {
        return address(new ArbitrumReceiver(sourceAuthority, address(moDestination)));
    }

    function initBridgeTesting() internal override returns (Bridge memory) {
        return ArbitrumBridgeTesting.createNativeBridge(source, destination);
    }

    function queueSourceToDestination(bytes memory message) internal override {
        ArbitrumERC20Forwarder.sendMessageL1toL2(
            bridge.sourceCrossChainMessenger,
            destinationReceiver,
            message,
            100000,
            1 gwei,
            block.basefee + 10 gwei
        );
    }

    function queueDestinationToSource(bytes memory message) internal override {
        ArbitrumERC20Forwarder.sendMessageL2toL1(
            address(moSource),  // No receiver so send directly to the message ordering contract
            message
        );
    }

    function relaySourceToDestination() internal override {
        bridge.relayMessagesToDestination(true);
    }

    function relayDestinationToSource() internal override {
        bridge.relayMessagesToSource(true);
    }

}
