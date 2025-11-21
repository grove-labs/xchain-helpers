// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import { Address } from "openzeppelin-contracts/contracts/utils/Address.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";

import { SetConfigParam } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig }      from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

import { OAppReceiver, Origin, OAppCore } from "layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

/**
 * @title  LZReceiver
 * @notice Receive messages from LayerZero-style bridge.
 */
contract LZReceiver is OAppReceiver {

    using Address for address;

    address public immutable target;

    uint32  public immutable srcEid;

    bytes32 public immutable sourceAuthority;

    constructor(
        address   _destinationEndpoint,
        uint32    _srcEid,
        bytes32   _sourceAuthority,
        address   _target,
        address   _delegate,
        address   _owner,
        address[] memory _requiredDVNs
    ) OAppCore(_destinationEndpoint, _delegate) Ownable(_owner) {
        target          = _target;
        sourceAuthority = _sourceAuthority;
        srcEid          = _srcEid;

        _setPeer(_srcEid, _sourceAuthority);
        _configureReceiver(_requiredDVNs);
    }

    function _configureReceiver(address[] memory _requiredDVNs) internal {
        ( address receiveLib, ) = endpoint.getReceiveLibrary(address(0), srcEid);

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations        : 15,
            requiredDVNCount     : uint8(_requiredDVNs.length),
            optionalDVNCount     : 0,
            optionalDVNThreshold : 0,
            requiredDVNs         : _requiredDVNs,
            optionalDVNs         : new address[](0)
        });

        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = SetConfigParam({
            eid        : srcEid,
            configType : 2,
            config     : abi.encode(ulnConfig)
        });

        endpoint.setConfig(address(this), receiveLib, configParams);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32,  // _guid
        bytes calldata _message,
        address,  // _executor
        bytes calldata  // _extraData
    ) internal override {
        require(_origin.srcEid == srcEid,          "LZReceiver/invalid-srcEid");
        require(_origin.sender == sourceAuthority, "LZReceiver/invalid-sourceAuthority");

        target.functionCallWithValue(_message, msg.value);
    }

    function allowInitializePath(Origin calldata origin) public view override returns (bool) {
        return super.allowInitializePath(origin)
            && origin.srcEid == srcEid
            && origin.sender == sourceAuthority;
    }

}
