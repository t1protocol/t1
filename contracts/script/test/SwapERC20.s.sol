// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { IL1StandardERC20Gateway } from "../../src/L1/gateways/IL1StandardERC20Gateway.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { PermitSignature } from "../../src/test/utils/PermitSignature.sol";

// solhint-disable var-name-mixedcase

contract SwapERC20 is Script, PermitSignature {
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address private L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");
    address private L1_USDT_ADDR = vm.envAddress("L1_USDT_ADDR");
    uint256 private ALICE_PRIVATE_KEY = vm.envUint("ALICE_PRIVATE_KEY");
    address private alice = vm.addr(ALICE_PRIVATE_KEY);
    uint256 private inputTokenAmount = 1e15; // WETH
    uint256 private outputAmount = 10e18; // USDT
    uint256 private minAmountOut = 1e18; // USDT

    string private constant WITNESS_TYPE_STRING = "uint256 minAmountOut)TokenPermissions(address token,uint256 amount)";
    bytes32 private constant FULL_EXAMPLE_WITNESS_TYPEHASH = keccak256(
        // solhint-disable-next-line max-line-length
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,uint256 minAmountOut)TokenPermissions(address token,uint256 amount)"
    );

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(ALICE_PRIVATE_KEY);

        // Alice needs WETH to swap for USDT
        // Bridge should have USDT to swap for WETH

        address permit2 = IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).permit2();

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: L1_WETH_ADDR, amount: inputTokenAmount }),
            nonce: 0,
            deadline: block.timestamp + 1000
        });

        bytes32 witness = keccak256(abi.encode(minAmountOut));
        bytes memory sig = getPermitWitnessTransferSignature(
            permit,
            ALICE_PRIVATE_KEY,
            FULL_EXAMPLE_WITNESS_TYPEHASH,
            witness,
            ISignatureTransfer(permit2).DOMAIN_SEPARATOR(),
            L1_GATEWAY_ROUTER_PROXY_ADDR
        );

        IL1GatewayRouter.SwapParams memory params = IL1GatewayRouter.SwapParams({
            permit: permit,
            owner: alice,
            outputToken: L1_USDT_ADDR,
            minAmountOut: minAmountOut,
            outputAmount: outputAmount,
            witnessTypeString: WITNESS_TYPE_STRING,
            sig: sig
        });

        // Check if Alice has enough WETH to swap
        if (T1StandardERC20(L1_WETH_ADDR).balanceOf(alice) < inputTokenAmount) {
            revert("Alice doesn't have enough WETH");
        }

        // Check if Alice has approved the permit2 to transfer WETH
        if (T1StandardERC20(L1_WETH_ADDR).allowance(alice, permit2) < inputTokenAmount) {
            T1StandardERC20(L1_WETH_ADDR).approve(permit2, type(uint256).max);
        }

        // Check if the ERC20 gateway has approved the permit2 to transfer USDT
        // TODO include check allowance transfer to the router on USDT
        if (T1StandardERC20(L1_USDT_ADDR).allowance(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR, permit2) < minAmountOut) {
            IL1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).allowRouterToTransfer(
                L1_USDT_ADDR, type(uint160).max, uint48(block.timestamp + 1000)
            );
        }

        // Check if the market maker is set to this address
        if (IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).marketMaker() != address(this)) {
            // Use SetMM script to set this address as the router's market maker
            revert("Signer is not the market maker in the router");
        }

        IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).swapERC20(params);

        vm.stopBroadcast();
    }

    // Override to prefer StdUtils bouns()
    function bound(
        uint256 x,
        uint256 min,
        uint256 max
    )
        internal
        pure
        override(DSTestPlus, StdUtils)
        returns (uint256)
    {
        return StdUtils.bound(x, min, max); // Explicitly choose StdUtils version
    }
}
