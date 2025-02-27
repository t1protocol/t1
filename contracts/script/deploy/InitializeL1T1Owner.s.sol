// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.28;

import { Script } from "forge-std/Script.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import { L1T1Messenger } from "../../src/L1/L1T1Messenger.sol";
import { L1GatewayRouter } from "../../src/L1/gateways/L1GatewayRouter.sol";
import { L1MessageQueue } from "../../src/L1/rollup/L1MessageQueue.sol";
import { T1MessengerBase } from "../../src/libraries/T1MessengerBase.sol";
import { L2GasPriceOracle } from "../../src/L1/rollup/L2GasPriceOracle.sol";
import { MultipleVersionRollupVerifier } from "../../src/L1/rollup/MultipleVersionRollupVerifier.sol";
import { L1MessageQueueWithGasPriceOracle } from "../../src/L1/rollup/L1MessageQueueWithGasPriceOracle.sol";
import { T1Chain } from "../../src/L1/rollup/T1Chain.sol";
import { T1Owner } from "../../src/misc/T1Owner.sol";
import { Whitelist } from "../../src/L2/predeploys/Whitelist.sol";

// solhint-disable max-states-count
// solhint-disable var-name-mixedcase

contract InitializeL1T1Owner is Script {
    uint256 private L1_DEPLOYER_PRIVATE_KEY = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");

    bytes32 private constant SECURITY_COUNCIL_NO_DELAY_ROLE = keccak256("SECURITY_COUNCIL_NO_DELAY_ROLE");
    bytes32 private constant T1_MULTISIG_NO_DELAY_ROLE = keccak256("T1_MULTISIG_NO_DELAY_ROLE");
    bytes32 private constant EMERGENCY_MULTISIG_NO_DELAY_ROLE = keccak256("EMERGENCY_MULTISIG_NO_DELAY_ROLE");

    bytes32 private constant TIMELOCK_1DAY_DELAY_ROLE = keccak256("TIMELOCK_1DAY_DELAY_ROLE");
    bytes32 private constant TIMELOCK_7DAY_DELAY_ROLE = keccak256("TIMELOCK_7DAY_DELAY_ROLE");

    address private T1_MULTISIG_ADDR = vm.envAddress("L1_T1_MULTISIG_ADDR");
    address private SECURITY_COUNCIL_ADDR = vm.envAddress("L1_SECURITY_COUNCIL_ADDR");
    address private EMERGENCY_MULTISIG_ADDR = vm.envAddress("L1_EMERGENCY_MULTISIG_ADDR");

    address private L1_T1_OWNER_ADDR = vm.envAddress("L1_T1_OWNER_ADDR");
    address private L1_1D_TIMELOCK_ADDR = vm.envAddress("L1_1D_TIMELOCK_ADDR");
    address private L1_7D_TIMELOCK_ADDR = vm.envAddress("L1_7D_TIMELOCK_ADDR");
    address private L1_14D_TIMELOCK_ADDR = vm.envAddress("L1_14D_TIMELOCK_ADDR");

    address private L1_PROXY_ADMIN_ADDR = vm.envAddress("L1_PROXY_ADMIN_ADDR");
    address private L1_T1_CHAIN_PROXY_ADDR = vm.envAddress("L1_T1_CHAIN_PROXY_ADDR");
    address private L1_MESSAGE_QUEUE_PROXY_ADDR = vm.envAddress("L1_MESSAGE_QUEUE_PROXY_ADDR");
    address private L2_GAS_PRICE_ORACLE_PROXY_ADDR = vm.envAddress("L2_GAS_PRICE_ORACLE_PROXY_ADDR");
    address private L1_T1_MESSENGER_PROXY_ADDR = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
    address private L1_GATEWAY_ROUTER_PROXY_ADDR = vm.envAddress("L1_GATEWAY_ROUTER_PROXY_ADDR");
    address private L1_ETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_ETH_GATEWAY_PROXY_ADDR");
    address private L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR = vm.envAddress("L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR");
    address private L1_WETH_GATEWAY_PROXY_ADDR = vm.envAddress("L1_WETH_GATEWAY_PROXY_ADDR");
    address private L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR = vm.envAddress("L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR");
    address private L1_WHITELIST_ADDR = vm.envAddress("L1_WHITELIST_ADDR");

    T1Owner private owner;

    function run() external {
        vm.startBroadcast(L1_DEPLOYER_PRIVATE_KEY);

        owner = T1Owner(payable(L1_T1_OWNER_ADDR));

        // @note we don't config 14D access, since the default admin is a 14D timelock which can access all methods.
        configProxyAdmin();
        configT1Chain();
        configL1MessageQueue();
        configL1T1Messenger();
        configL2GasPriceOracle();
        configL1Whitelist();
        configMultipleVersionRollupVerifier();
        configL1GatewayRouter();

        grantRoles();
        transferOwnership();

        vm.stopBroadcast();
    }

    function transferOwnership() internal {
        Ownable(L1_PROXY_ADMIN_ADDR).transferOwnership(address(owner));
        Ownable(L1_T1_CHAIN_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L1_MESSAGE_QUEUE_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L1_T1_MESSENGER_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L2_GAS_PRICE_ORACLE_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L1_WHITELIST_ADDR).transferOwnership(address(owner));
        Ownable(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR).transferOwnership(address(owner));
        Ownable(L1_GATEWAY_ROUTER_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L1_ETH_GATEWAY_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L1_STANDARD_ERC20_GATEWAY_PROXY_ADDR).transferOwnership(address(owner));
        Ownable(L1_WETH_GATEWAY_PROXY_ADDR).transferOwnership(address(owner));
    }

    function grantRoles() internal {
        owner.grantRole(SECURITY_COUNCIL_NO_DELAY_ROLE, SECURITY_COUNCIL_ADDR);
        owner.grantRole(T1_MULTISIG_NO_DELAY_ROLE, T1_MULTISIG_ADDR);
        owner.grantRole(EMERGENCY_MULTISIG_NO_DELAY_ROLE, EMERGENCY_MULTISIG_ADDR);
        owner.grantRole(TIMELOCK_1DAY_DELAY_ROLE, L1_1D_TIMELOCK_ADDR);
        owner.grantRole(TIMELOCK_7DAY_DELAY_ROLE, L1_7D_TIMELOCK_ADDR);

        owner.grantRole(owner.DEFAULT_ADMIN_ROLE(), L1_14D_TIMELOCK_ADDR);
        owner.revokeRole(owner.DEFAULT_ADMIN_ROLE(), vm.addr(L1_DEPLOYER_PRIVATE_KEY));
    }

    function configProxyAdmin() internal {
        bytes4[] memory _selectors;

        // no delay, security council
        _selectors = new bytes4[](2);
        _selectors[0] = ProxyAdmin.upgrade.selector;
        _selectors[1] = ProxyAdmin.upgradeAndCall.selector;
        owner.updateAccess(L1_PROXY_ADMIN_ADDR, _selectors, SECURITY_COUNCIL_NO_DELAY_ROLE, true);
    }

    function configT1Chain() internal {
        bytes4[] memory _selectors;

        // no delay, t1 multisig and emergency multisig
        _selectors = new bytes4[](4);
        _selectors[0] = T1Chain.revertBatch.selector;
        _selectors[1] = T1Chain.removeSequencer.selector;
        _selectors[2] = T1Chain.removeProver.selector;
        _selectors[3] = T1Chain.setPause.selector;
        owner.updateAccess(L1_T1_CHAIN_PROXY_ADDR, _selectors, T1_MULTISIG_NO_DELAY_ROLE, true);
        owner.updateAccess(L1_T1_CHAIN_PROXY_ADDR, _selectors, EMERGENCY_MULTISIG_NO_DELAY_ROLE, true);

        // delay 1 day, t1 multisig
        _selectors = new bytes4[](2);
        _selectors[0] = T1Chain.addSequencer.selector;
        _selectors[1] = T1Chain.addProver.selector;
        owner.updateAccess(L1_T1_CHAIN_PROXY_ADDR, _selectors, TIMELOCK_1DAY_DELAY_ROLE, true);

        // delay 7 day, t1 multisig
        _selectors = new bytes4[](1);
        _selectors[0] = T1Chain.updateMaxNumTxInChunk.selector;
        owner.updateAccess(L1_T1_CHAIN_PROXY_ADDR, _selectors, TIMELOCK_7DAY_DELAY_ROLE, true);
    }

    function configL1MessageQueue() internal {
        bytes4[] memory _selectors;

        // delay 1 day, t1 multisig
        _selectors = new bytes4[](2);
        _selectors[0] = L1MessageQueue.updateGasOracle.selector;
        _selectors[1] = L1MessageQueue.updateMaxGasLimit.selector;
        owner.updateAccess(L1_MESSAGE_QUEUE_PROXY_ADDR, _selectors, TIMELOCK_1DAY_DELAY_ROLE, true);

        // no delay, security council
        _selectors = new bytes4[](1);
        _selectors[0] = L1MessageQueueWithGasPriceOracle.setL2BaseFee.selector;
        owner.updateAccess(L1_MESSAGE_QUEUE_PROXY_ADDR, _selectors, SECURITY_COUNCIL_NO_DELAY_ROLE, true);
    }

    function configL1T1Messenger() internal {
        bytes4[] memory _selectors;

        // no delay, t1 multisig and emergency multisig
        _selectors = new bytes4[](1);
        _selectors[0] = T1MessengerBase.setPause.selector;
        owner.updateAccess(L1_T1_MESSENGER_PROXY_ADDR, _selectors, T1_MULTISIG_NO_DELAY_ROLE, true);
        owner.updateAccess(L1_T1_MESSENGER_PROXY_ADDR, _selectors, EMERGENCY_MULTISIG_NO_DELAY_ROLE, true);

        // delay 1 day, t1 multisig
        _selectors = new bytes4[](1);
        _selectors[0] = L1T1Messenger.updateMaxReplayTimes.selector;
        owner.updateAccess(L1_T1_MESSENGER_PROXY_ADDR, _selectors, TIMELOCK_1DAY_DELAY_ROLE, true);
    }

    function configL2GasPriceOracle() internal {
        bytes4[] memory _selectors;

        // no delay, t1 multisig and emergency multisig
        _selectors = new bytes4[](1);
        _selectors[0] = L2GasPriceOracle.setIntrinsicParams.selector;
        owner.updateAccess(L2_GAS_PRICE_ORACLE_PROXY_ADDR, _selectors, T1_MULTISIG_NO_DELAY_ROLE, true);
        owner.updateAccess(L2_GAS_PRICE_ORACLE_PROXY_ADDR, _selectors, EMERGENCY_MULTISIG_NO_DELAY_ROLE, true);
    }

    function configL1Whitelist() internal {
        bytes4[] memory _selectors;

        // delay 1 day, t1 multisig
        _selectors = new bytes4[](1);
        _selectors[0] = Whitelist.updateWhitelistStatus.selector;
        owner.updateAccess(L1_WHITELIST_ADDR, _selectors, TIMELOCK_1DAY_DELAY_ROLE, true);
    }

    function configMultipleVersionRollupVerifier() internal {
        bytes4[] memory _selectors;

        // no delay, security council
        _selectors = new bytes4[](1);
        _selectors[0] = MultipleVersionRollupVerifier.updateVerifier.selector;
        owner.updateAccess(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR, _selectors, SECURITY_COUNCIL_NO_DELAY_ROLE, true);

        // delay 7 day, t1 multisig
        _selectors = new bytes4[](1);
        _selectors[0] = MultipleVersionRollupVerifier.updateVerifier.selector;
        owner.updateAccess(L1_MULTIPLE_VERSION_ROLLUP_VERIFIER_ADDR, _selectors, TIMELOCK_7DAY_DELAY_ROLE, true);
    }

    function configL1GatewayRouter() internal {
        bytes4[] memory _selectors;

        // delay 1 day, t1 multisig
        _selectors = new bytes4[](1);
        _selectors[0] = L1GatewayRouter.setERC20Gateway.selector;
        owner.updateAccess(L1_GATEWAY_ROUTER_PROXY_ADDR, _selectors, TIMELOCK_1DAY_DELAY_ROLE, true);

        // no delay, t1 multisig
        _selectors = new bytes4[](2);
        _selectors[0] = L1GatewayRouter.setPermit2.selector;
        _selectors[1] = L1GatewayRouter.setMM.selector;
        owner.updateAccess(L1_GATEWAY_ROUTER_PROXY_ADDR, _selectors, T1_MULTISIG_NO_DELAY_ROLE, true);
        owner.updateAccess(L1_GATEWAY_ROUTER_PROXY_ADDR, _selectors, EMERGENCY_MULTISIG_NO_DELAY_ROLE, true);
        owner.updateAccess(L1_GATEWAY_ROUTER_PROXY_ADDR, _selectors, SECURITY_COUNCIL_NO_DELAY_ROLE, true);
    }
}
