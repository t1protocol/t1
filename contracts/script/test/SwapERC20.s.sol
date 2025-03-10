// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import { Script } from "forge-std/Script.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

import { IL1GatewayRouter } from "../../src/L1/gateways/IL1GatewayRouter.sol";
import { IL1StandardERC20Gateway } from "../../src/L1/gateways/IL1StandardERC20Gateway.sol";
import { T1StandardERC20 } from "../../src/libraries/token/T1StandardERC20.sol";
import { PermitSignature } from "../../src/test/utils/PermitSignature.sol";
import { T1Constants } from "../../src/libraries/constants/T1Constants.sol";

// solhint-disable var-name-mixedcase
// solhint-disable reason-string

contract SwapERC20 is Script, PermitSignature {
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address private L1_WETH_ADDR = vm.envAddress("L1_WETH_ADDR");
    address private L1_USDT_ADDR = vm.envAddress("L1_USDT_ADDR");
    uint256 private ALICE_PRIVATE_KEY = vm.envUint("ALICE_PRIVATE_KEY");
    address private alice = vm.addr(ALICE_PRIVATE_KEY);
    uint256 private MARKET_MAKER_PRIVATE_KEY = vm.envUint("MARKET_MAKER_PRIVATE_KEY");
    address private marketMaker = vm.addr(MARKET_MAKER_PRIVATE_KEY);
    uint256 private inputTokenAmount = 0.0001 ether; // WETH
    uint256 private outputTokenAmount = 1 ether; // USDT

    function run() external {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast(MARKET_MAKER_PRIVATE_KEY);

        // Alice needs WETH to swap for USDT
        // Bridge should have USDT to swap for WETH

        address permit2 = IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).permit2();

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: L1_WETH_ADDR, amount: inputTokenAmount }),
            nonce: uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.prevrandao))),
            deadline: block.timestamp + 10_000_000
        });

        IL1GatewayRouter.Witness memory witness = IL1GatewayRouter.Witness({
            direction: 0,
            priceAfterSlippage: 0,
            outputTokenAddress: L1_USDT_ADDR,
            outputTokenAmount: outputTokenAmount
        });

        bytes32 witnessEncoded = keccak256(abi.encode(T1Constants.WITNESS_TYPEHASH, witness));

        bytes memory sig = getPermitWitnessTransferSignature(
            permit,
            ALICE_PRIVATE_KEY,
            T1Constants.FULL_PERMITWITNESSTRANSFERFROM_TYPEHASH,
            witnessEncoded,
            ISignatureTransfer(permit2).DOMAIN_SEPARATOR(),
            L1_GATEWAY_ROUTER_PROXY_ADDR
        );

        IL1GatewayRouter.SwapParams memory params =
            IL1GatewayRouter.SwapParams({ permit: permit, owner: alice, witness: witness, sig: sig });

        // Check if Alice has enough WETH to swap
        require(T1StandardERC20(L1_WETH_ADDR).balanceOf(alice) >= inputTokenAmount, "Alice doesn't have enough WETH");

        // Check if Alice has approved the permit2 to transfer WETH
        if (T1StandardERC20(L1_WETH_ADDR).allowance(alice, permit2) < inputTokenAmount) {
            T1StandardERC20(L1_WETH_ADDR).approve(permit2, type(uint256).max);
        }

        // Check if the ERC20 gateway has approved the permit2 to transfer USDT
        // TODO - Check if allowance has expired
        if (T1StandardERC20(L1_USDT_ADDR).allowance(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR, permit2) < outputTokenAmount)
        {
            IL1StandardERC20Gateway(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).allowRouterToTransfer(
                L1_USDT_ADDR, type(uint160).max, uint48(block.timestamp + 10_000_000)
            );
        }

        // Check if the ERC20 gateway has enough USDT to swap
        require(
            T1StandardERC20(L1_USDT_ADDR).balanceOf(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR) >= outputTokenAmount,
            "ERC20 gateway doesn't have enough USDT"
        );

        // Use SetMM script to set alice as the router's market maker
        require(
            IL1GatewayRouter(L1_GATEWAY_ROUTER_PROXY_ADDR).marketMaker() == marketMaker,
            "Signer is not the market maker in the router"
        );

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
