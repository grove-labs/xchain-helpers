// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ICrossDomainArbitrum {
    function createRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 tokenTotalFeeAmount,
        bytes calldata data
    ) external returns (uint256);
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee) external view returns (uint256);
}

interface IArbSys {
    function sendTxToL1(address target, bytes calldata message) external;
}

library ArbitrumERC20Forwarder {

    address constant internal L1_CROSS_DOMAIN_PLUME = 0x943fc691242291B74B105e8D19bd9E5DC2fcBa1D;
    address constant internal PLUME_GAS_TOKEN       = 0x4C1746A800D224393fE2470C70A35717eD4eA5F1;

    address constant internal L2_CROSS_DOMAIN = 0x0000000000000000000000000000000000000064;

    function sendMessageL1toL2(
        address l1CrossDomain,
        address target,
        bytes memory message,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        uint256 baseFee
    ) internal {
        uint256 maxSubmission = ICrossDomainArbitrum(l1CrossDomain).calculateRetryableSubmissionFee(message.length, baseFee);
        uint256 tokenTotalFeeAmount = maxSubmission + gasLimit * maxFeePerGas;

        if (l1CrossDomain == L1_CROSS_DOMAIN_PLUME) {
            IERC20(PLUME_GAS_TOKEN).approve(l1CrossDomain, tokenTotalFeeAmount);
        } else {
            revert("ArbitrumERC20Forwarder/invalid-l1-cross-domain");
        }

        ICrossDomainArbitrum(l1CrossDomain).createRetryableTicket(
            target,
            0, // we always assume that l2CallValue = 0
            maxSubmission,
            address(0), // burn the excess gas
            address(0), // burn the excess gas
            gasLimit,
            maxFeePerGas,
            tokenTotalFeeAmount,
            message
        );
    }

    function sendMessageL2toL1(
        address target,
        bytes memory message
    ) internal {
        IArbSys(L2_CROSS_DOMAIN).sendTxToL1(
            target,
            message
        );
    }

}
