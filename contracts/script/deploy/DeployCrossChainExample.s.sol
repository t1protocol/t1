// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

import { IL1T1Messenger } from "../../src/L1/IL1T1Messenger.sol";
import { IL2T1Messenger } from "../../src/L2/IL2T1Messenger.sol";
import { IT1Messenger } from "../../src/libraries/IT1Messenger.sol";

contract CrossChainExample {
    IT1Messenger public immutable MESSENGER;

    // map request ids to their originators
    mapping(bytes32 requestId => address sender) public requests;

    // events for tracking cross-chain interactions
    event CrossChainRequestSent(bytes32 indexed requestId, uint64 destChainId, address target, bytes data);
    event CrossChainRequestReceived(bytes32 indexed requestId, address originator, bytes data);

    constructor(IT1Messenger _messenger) {
        MESSENGER = _messenger;
    }

    /**
     * @notice sends a cross-chain request to another chain
     * @param destChainId the destination chain id
     * @param target address of contract to call on destination chain
     * @param data the calldata to execute
     * @return requestId unique identifier for this request
     */
    function sendCrossChainRequest(
        uint64 destChainId,
        address target,
        uint256 gasLimit,
        bytes calldata data
    )
        external
        payable
        returns (bytes32 requestId)
    {
        // create a unique request id
        requestId = keccak256(abi.encode(block.chainid, destChainId, target, data, block.timestamp, msg.sender));

        // store the originator
        requests[requestId] = msg.sender;

        // prepare the message - making it call the handleRequest function on the remote chain
        bytes memory message =
            abi.encodeWithSelector(CrossChainExample.handleRequest.selector, requestId, msg.sender, data);

        // send via t1 messenger
        MESSENGER.sendMessage{ value: gasLimit }(
            target,
            0, // no value transfer
            message,
            gasLimit, // gas limit,
            destChainId
        );

        emit CrossChainRequestSent(requestId, destChainId, target, data);
        return requestId;
    }

    /**
     * @notice handles incoming cross-chain requests
     * @param requestId the unique request identifier
     * @param originator the address that initiated the request
     * @param data the calldata to execute
     */
    function handleRequest(bytes32 requestId, address originator, bytes calldata data) external {
        // security check - only t1 messenger can call this
        require(msg.sender == address(MESSENGER), "unauthorized");
        require(MESSENGER.xDomainMessageSender() != address(0), "invalid sender");

        // process the received data - in a real implementation, you would do something useful with it

        emit CrossChainRequestReceived(requestId, originator, data);
    }

    // example function that could be called via cross-chain messaging
    function echo(string calldata message) external pure returns (string memory) {
        return message;
    }
}

contract DeployCrossChainExample is Script {
    function deploy_example_to_l1() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        address l1Messenger = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        uint256 deployerPk = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        CrossChainExample example = new CrossChainExample(IL1T1Messenger(l1Messenger));

        console2.log("L1_EXAMPLE_ADDR=", address(example));

        vm.stopBroadcast();
    }

    function deploy_example_to_t1() public {
        vm.createSelectFork(vm.rpcUrl("t1"));
        address l2Messenger = vm.envAddress("L2_T1_MESSENGER_PROXY_ADDR");
        uint256 deployerPk = vm.envUint("L2_DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPk);

        CrossChainExample example = new CrossChainExample(IL2T1Messenger(l2Messenger));

        console2.log("L2_EXAMPLE_ADDR=", address(example));

        vm.stopBroadcast();
    }
}
