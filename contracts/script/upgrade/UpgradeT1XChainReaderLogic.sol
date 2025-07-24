// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {DeploymentUtils} from "../lib/DeploymentUtils.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {T1XChainReader} from "../../src/libraries/xChain/T1XChainReader.sol";
import {T1Owner} from "../../src/misc/T1Owner.sol";

/**
 * @title UpgradeT1XChainReaderLogic
 * @dev Contains the core business logic for upgrading T1XChainReader implementation
 */
abstract contract UpgradeT1XChainReaderLogic is Script, DeploymentUtils {
    // Security council role
    bytes32 internal constant SECURITY_COUNCIL_NO_DELAY_ROLE = keccak256("SECURITY_COUNCIL_NO_DELAY_ROLE");

    /**
     * @dev Deploys a new T1XChainReader implementation
     * @return implementation The address of the new implementation
     */
    function _deployNewImplementation() internal returns (T1XChainReader implementation) {
        uint256 deployerPrivateKey = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address messengerProxyAddr = vm.envAddress("L1_T1_MESSENGER_PROXY_ADDR");
        address signerAddr = vm.envAddress("L1_SIGNER");

        vm.startBroadcast(deployerPrivateKey);
        implementation = new T1XChainReader(signerAddr);
        vm.stopBroadcast();

        logAddress("L1_T1_X_CHAIN_READ_IMPLEMENTATION_ADDR_NEW", address(implementation));

        console.log("New T1XChainReader implementation deployed at:", vm.toString(address(implementation)));
    }

    /**
     * @dev Performs the upgrade using T1Owner (for production networks)
     * @param newImplementation The new implementation address
     */
    function _upgradeViaT1Owner(address newImplementation) internal {
        uint256 securityCouncilPrivateKey = vm.envUint("L1_SECURITY_COUNCIL_PRIVATE_KEY");
        address proxyAdminAddr = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        address t1OwnerAddr = vm.envAddress("L1_T1_OWNER_ADDR");
        address xChainReaderProxyAddr = vm.envAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR");

        vm.startBroadcast(securityCouncilPrivateKey);

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);

        address currentImplementation =
            proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(xChainReaderProxyAddr));

        console.log(
            "Upgrading T1XChainReader implementation from",
            vm.toString(currentImplementation),
            "to new implementation",
            vm.toString(newImplementation)
        );

        try T1Owner(payable(t1OwnerAddr)).execute(
            proxyAdminAddr,
            0,
            abi.encodeWithSelector(
                proxyAdmin.upgrade.selector, ITransparentUpgradeableProxy(xChainReaderProxyAddr), newImplementation
            ),
            SECURITY_COUNCIL_NO_DELAY_ROLE
        ) {
            console.log("T1XChainReader upgrade successful");
            _verifyUpgrade(proxyAdminAddr, xChainReaderProxyAddr, newImplementation);
        } catch Error(string memory reason) {
            console.log("T1XChainReader upgrade failed:", reason);
            revert(string(abi.encodePacked("T1XChainReader upgrade failed: ", reason)));
        } catch (bytes memory) {
            console.log("T1XChainReader upgrade failed with unknown error");
            revert("T1XChainReader upgrade failed with unknown error");
        }

        vm.stopBroadcast();
    }

    /**
     * @dev Performs the upgrade directly via ProxyAdmin (for local testing)
     * @param newImplementation The new implementation address
     */
    function _upgradeDirectly(address newImplementation) internal {
        uint256 deployerPrivateKey = vm.envUint("L1_DEPLOYER_PRIVATE_KEY");
        address proxyAdminAddr = vm.envAddress("L1_PROXY_ADMIN_ADDR");
        address xChainReaderProxyAddr = vm.envAddress("L1_T1_X_CHAIN_READ_PROXY_ADDR");

        vm.startBroadcast(deployerPrivateKey);

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);

        address currentImplementation =
            proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(xChainReaderProxyAddr));

        console.log(
            "Upgrading T1XChainReader implementation from",
            vm.toString(currentImplementation),
            "to new implementation",
            vm.toString(newImplementation)
        );

        proxyAdmin.upgrade(ITransparentUpgradeableProxy(xChainReaderProxyAddr), newImplementation);

        console.log("T1XChainReader upgrade successful");
        _verifyUpgrade(proxyAdminAddr, xChainReaderProxyAddr, newImplementation);

        vm.stopBroadcast();
    }

    /**
     * @dev Verifies that the upgrade was successful
     * @param proxyAdminAddr The ProxyAdmin address
     * @param xChainReaderProxyAddr The proxy address
     * @param expectedImplementation The expected implementation address
     */
    function _verifyUpgrade(address proxyAdminAddr, address xChainReaderProxyAddr, address expectedImplementation)
        internal
        view
    {
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);
        address actualImplementation =
            proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(xChainReaderProxyAddr));

        if (actualImplementation == expectedImplementation) {
            console.log("Verification successful: Implementation is now", vm.toString(actualImplementation));
        } else {
            console.log(
                "Verification failed: Expected",
                vm.toString(expectedImplementation),
                "but got",
                vm.toString(actualImplementation)
            );
            revert("Upgrade verification failed");
        }
    }

    /**
     * @dev Main upgrade function that handles the complete upgrade process
     * @param local If the deployment is on a local network
     */
    function _performUpgrade(bool local) internal {
        // Deploy new implementation
        T1XChainReader newImplementation = _deployNewImplementation();

        // Perform upgrade based on configuration
        if (local) {
            _upgradeDirectly(address(newImplementation));
        } else {
            _upgradeViaT1Owner(address(newImplementation));
        }
    }
}
