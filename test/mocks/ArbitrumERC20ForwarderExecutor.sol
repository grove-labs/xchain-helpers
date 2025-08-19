// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { ArbitrumERC20Forwarder } from "src/forwarders/ArbitrumERC20Forwarder.sol";

contract ArbitrumERC20ForwarderExecutor {

    function sendMessageL1toL2(
        address l1CrossDomain,
        address target,
        bytes memory message
    ) public {
        ArbitrumERC20Forwarder.sendMessageL1toL2(
            l1CrossDomain,
            target,
            message,
            100000,
            1 gwei,
            1 gwei
        );
    }

}
