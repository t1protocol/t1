// SPDX-License-Identifier: MIT

pragma solidity >=0.8.28;

import { console } from "forge-std/console.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { DSTestPlus } from "solmate/test/utils/DSTestPlus.sol";

import { ITransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { DeployPermit2 } from "@uniswap/permit2/test/utils/DeployPermit2.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

import { L1ETHGateway } from "../L1/gateways/L1ETHGateway.sol";
import { IL1GatewayRouter } from "../L1/gateways/IL1GatewayRouter.sol";
import { L1GatewayRouter } from "../L1/gateways/L1GatewayRouter.sol";
import { L1StandardERC20Gateway } from "../L1/gateways/L1StandardERC20Gateway.sol";
import { L2ETHGateway } from "../L2/gateways/L2ETHGateway.sol";
import { L2StandardERC20Gateway } from "../L2/gateways/L2StandardERC20Gateway.sol";
import { T1StandardERC20 } from "../libraries/token/T1StandardERC20.sol";
import { T1StandardERC20Factory } from "../libraries/token/T1StandardERC20Factory.sol";

import { L1GatewayTestBase } from "./L1GatewayTestBase.t.sol";

import { TransferReentrantToken } from "./mocks/tokens/TransferReentrantToken.sol";

contract L1GatewayRouterTest is L1GatewayTestBase, DeployPermit2 {
    
    T1StandardERC20 private template;
    T1StandardERC20Factory private factory;

    L1StandardERC20Gateway private l1StandardERC20Gateway;
    L2StandardERC20Gateway private l2StandardERC20Gateway;

    L1ETHGateway private l1ETHGateway;
    L2ETHGateway private l2ETHGateway;

    L1GatewayRouter private router;
    MockERC20 private l1Token;
    MockERC20 private usdt;
    MockERC20 private aave;
    MockERC20 private dai;

    address private permit2;

    function setUp() public {
        __L1GatewayTestBase_setUp();

        // Deploy Permit2
        permit2 = DeployPermit2.deployPermit2();

        // Deploy tokens
        l1Token = new MockERC20("Mock", "M", 18);
        usdt = new MockERC20("Tether", "USDT", 6);
        aave = new MockERC20("Aave coin", "AAVE", 18);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);

        // Deploy L2 contracts
        template = new T1StandardERC20();
        factory = new T1StandardERC20Factory(address(template));
        l2StandardERC20Gateway = new L2StandardERC20Gateway(address(1), address(1), address(1), address(factory));
        l2ETHGateway = new L2ETHGateway(address(1), address(1), address(1));

        // Deploy L1 contracts
        l1StandardERC20Gateway = L1StandardERC20Gateway(_deployProxy(address(0)));
        l1ETHGateway = L1ETHGateway(_deployProxy(address(0)));
        router = L1GatewayRouter(_deployProxy(address(new L1GatewayRouter())));
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1StandardERC20Gateway)),
            address(
                new L1StandardERC20Gateway(
                    address(l2StandardERC20Gateway),
                    address(router),
                    address(l1Messenger),
                    address(template),
                    address(factory)
                )
            )
        );
        admin.upgrade(
            ITransparentUpgradeableProxy(address(l1ETHGateway)),
            address(new L1ETHGateway(address(l2ETHGateway), address(router), address(l1Messenger)))
        );

        // Initialize L1 contracts
        l1StandardERC20Gateway.initialize();
        l1ETHGateway.initialize();
        router.initialize(address(l1ETHGateway), address(l1StandardERC20Gateway), permit2);

        aave.mint(address(l1StandardERC20Gateway), 1e21); // 1,000 AAVE
        dai.mint(address(l1StandardERC20Gateway), 1e21); // 1,000 DAI
        usdt.mint(address(l1StandardERC20Gateway), 1e12); // 1,000,000 USDT

        vm.startPrank(address(l1StandardERC20Gateway));
        aave.approve(address(permit2), type(uint160).max);
        dai.approve(address(permit2), type(uint160).max);
        usdt.approve(address(permit2), type(uint160).max);
        vm.stopPrank();
    }

    function testOwnership() public {
        assertEq(address(this), router.owner());
    }

    function testInitialized() public {
        assertEq(address(l1StandardERC20Gateway), router.defaultERC20Gateway());
        assertEq(
            factory.computeL2TokenAddress(address(l2StandardERC20Gateway), address(l1Token)),
            router.getL2ERC20Address(address(l1Token))
        );
        assertEq(address(l1StandardERC20Gateway), router.getERC20Gateway(address(l1Token)));

        hevm.expectRevert("Initializable: contract is already initialized");
        router.initialize(address(l1ETHGateway), address(l1StandardERC20Gateway), address(0));
    }

    function testSetEthGateway() public {
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        router.setETHGateway(address(2));
        hevm.stopPrank();

        // set by owner, should succeed
        hevm.expectEmit(true, true, true, true);
        emit IL1GatewayRouter.SetETHGateway(address(l1ETHGateway), address(2));

        router.setETHGateway(address(2));
        assertEq(address(2), router.ethGateway());
    }

    function testSetDefaultERC20Gateway() public {
        router.setDefaultERC20Gateway(address(0));

        // set by non-owner, should revert
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        router.setDefaultERC20Gateway(address(l1StandardERC20Gateway));
        hevm.stopPrank();

        // set by owner, should succeed
        hevm.expectEmit(true, true, false, true);
        emit IL1GatewayRouter.SetDefaultERC20Gateway(address(0), address(l1StandardERC20Gateway));

        assertEq(address(0), router.getERC20Gateway(address(l1Token)));
        assertEq(address(0), router.defaultERC20Gateway());
        router.setDefaultERC20Gateway(address(l1StandardERC20Gateway));
        assertEq(address(l1StandardERC20Gateway), router.getERC20Gateway(address(l1Token)));
        assertEq(address(l1StandardERC20Gateway), router.defaultERC20Gateway());
    }

    function testSetPermit2() public {
        hevm.startPrank(address(1));
        hevm.expectRevert("Ownable: caller is not the owner");
        router.setPermit2(address(2));
        hevm.stopPrank();

        // set by owner, should succeed
        hevm.expectEmit(true, true, true, true);
        emit IL1GatewayRouter.SetPermit2(permit2, address(2));

        router.setPermit2(address(2));
        assertEq(address(2), router.permit2());
    }

    function testSetERC20Gateway() public {
        router.setDefaultERC20Gateway(address(0));

        // length mismatch, should revert
        address[] memory empty = new address[](0);
        address[] memory single = new address[](1);
        hevm.expectRevert("length mismatch");
        router.setERC20Gateway(empty, single);
        hevm.expectRevert("length mismatch");
        router.setERC20Gateway(single, empty);

        // set by owner, should succeed
        address[] memory _tokens = new address[](1);
        address[] memory _gateways = new address[](1);
        _tokens[0] = address(l1Token);
        _gateways[0] = address(l1StandardERC20Gateway);

        hevm.expectEmit(true, true, true, true);
        emit IL1GatewayRouter.SetERC20Gateway(address(l1Token), address(0), address(l1StandardERC20Gateway));

        assertEq(address(0), router.getERC20Gateway(address(l1Token)));
        router.setERC20Gateway(_tokens, _gateways);
        assertEq(address(l1StandardERC20Gateway), router.getERC20Gateway(address(l1Token)));
    }

    function testFinalizeWithdrawERC20() public {
        hevm.expectRevert("should never be called");
        router.finalizeWithdrawERC20(address(0), address(0), address(0), address(0), 0, "");
    }

    function testFinalizeWithdrawETH() public {
        hevm.expectRevert("should never be called");
        router.finalizeWithdrawETH(address(0), address(0), 0, "");
    }

    function skiptestCalculateOutputAmountSameDecimals() public {
        uint256 inputAmount = 1e18; // 1 DAI
        uint256 providedRate = 2e18; // 2 AAVE per DAI

        uint256 expectedOutput = (inputAmount * providedRate) / 1e18;
        uint256 actualOutput = router.calculateOutputAmount(address(dai), inputAmount, address(aave), providedRate);

        assertEq(actualOutput, expectedOutput, "Output amount incorrect for 18 -> 18 decimals");
    }

    function skiptestCalculateOutputAmountUSDTtoAAVE() public {
        uint256 inputAmount = 1e6; // 1 USDT
        uint256 providedRate = 2e18; // 2 AAVE per USDT

        uint256 expectedOutput = Math.mulDiv(inputAmount, providedRate * 1e18, 1e6 * 1e18);
        uint256 actualOutput = router.calculateOutputAmount(address(usdt), inputAmount, address(aave), providedRate);

        assertEq(actualOutput, expectedOutput, "Output amount incorrect for 6 -> 18 decimals");
    }

    function skiptestCalculateOutputAmountAAVEtoUSDT() public {
        uint256 inputAmount = 1e18; // 1 AAVE
        uint256 providedRate = 2e18; // 2 USDT per AAVE

        uint256 expectedOutput = Math.mulDiv(inputAmount, providedRate * 1e6, 1e18 * 1e18);
        uint256 actualOutput = router.calculateOutputAmount(address(aave), inputAmount, address(usdt), providedRate);

        assertEq(actualOutput, expectedOutput, "Output amount incorrect for 18 -> 6 decimals");
    }

    function skiptestCalculateOutputAmountZeroInput() public {
        hevm.expectRevert("Output amount must be > than 0");
        router.calculateOutputAmount(address(aave), 0, address(usdt), 2e18);
    }

    function skiptestCalculateOutputAmountInsufficientReserves() public {
        uint256 inputAmount = 1000e18; // 1000 AAVE
        uint256 providedRate = 10e20; // High rate to exceed reserves

        hevm.expectRevert("Insufficient reserves");
        router.calculateOutputAmount(address(aave), inputAmount, address(usdt), providedRate);
    }

    function testRequestERC20(address _sender, address _token, uint256 _amount) public {
        hevm.expectRevert("Only in deposit context");
        router.requestERC20(_sender, _token, _amount);
    }

    function testSwapERC20() public {
        address alice = address(3);
        uint256 providedRate = 2e18;

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(aave), amount: 2 }),
            nonce: 1,
            deadline: block.timestamp
        });

        uint256 outputTokenAmount = router.calculateOutputAmount(
            permit.permitted.token, permit.permitted.amount, address(dai), providedRate
        );

        l1StandardERC20Gateway.allowRouterToTransfer(address(dai), type(uint160).max, uint48(block.timestamp + 1000));

        uint256 startBalanceFrom = dai.balanceOf(address(l1StandardERC20Gateway));
        uint256 startBalanceTo = dai.balanceOf(alice);

        hevm.expectEmit(true, true, true, true);
        emit IL1GatewayRouter.Swap(
            alice, permit.permitted.token, address(dai), permit.permitted.amount, outputTokenAmount, providedRate
        );

        router.swapERC20(permit, address(dai), providedRate, alice, bytes32(""), string(""), bytes(""));

        assertEq(dai.balanceOf(address(l1StandardERC20Gateway)), startBalanceFrom - outputTokenAmount);
        assertEq(dai.balanceOf(alice), startBalanceTo + outputTokenAmount);
    }

    function testSwapERC20RevertInvalidOwner() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(usdt), amount: 1 }),
            nonce: 1,
            deadline: block.timestamp
        });

        hevm.expectRevert("Invalid owner address");
        router.swapERC20(permit, address(aave), 1e18, address(0), bytes32(""), "", bytes(""));
    }

    function testSwapERC20RevertInvalidInputToken() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(0), amount: 1 }),
            nonce: 1,
            deadline: block.timestamp
        });

        hevm.expectRevert("Invalid input token address");
        router.swapERC20(permit, address(aave), 1e18, address(1), bytes32(""), "", bytes(""));
    }

    function testSwapERC20RevertInvalidOutputtToken() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(1), amount: 1 }),
            nonce: 1,
            deadline: block.timestamp
        });

        hevm.expectRevert("Invalid output token address");
        router.swapERC20(permit, address(0), 1e18, address(1), bytes32(""), "", bytes(""));
    }

    function testSwapERC20RevertCannotSwapSameToken() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(1), amount: 1 }),
            nonce: 1,
            deadline: block.timestamp
        });

        hevm.expectRevert("Cannot swap the same token");
        router.swapERC20(permit, address(1), 1e18, address(1), bytes32(""), "", bytes(""));
    }

    function testSwapERC20RevertInpuntAmountGreaterThan0() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(2), amount: 0 }),
            nonce: 1,
            deadline: block.timestamp
        });

        hevm.expectRevert("Input amount must be > than 0");
        router.swapERC20(permit, address(aave), 1e18, address(1), bytes32(""), "", bytes(""));
    }

    function testSwapERC20RevertRateGreaterThan0() public {
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({ token: address(1), amount: 1 }),
            nonce: 1,
            deadline: block.timestamp
        });
        hevm.expectRevert("Rate must be > than 0");
        router.swapERC20(permit, address(aave), 0, address(1), bytes32(""), "", bytes(""));
    }

    function testReentrant() public {
        TransferReentrantToken reentrantToken = new TransferReentrantToken("Reentrant", "R", 18);
        reentrantToken.mint(address(this), type(uint128).max);
        reentrantToken.approve(address(router), type(uint256).max);

        reentrantToken.setReentrantCall(
            address(router),
            0,
            abi.encodeWithSelector(
                router.depositERC20AndCall.selector, address(reentrantToken), address(this), 0, new bytes(0), 0
            ),
            true
        );
        hevm.expectRevert("Only not in context");
        router.depositERC20(address(reentrantToken), 1, 0);

        reentrantToken.setReentrantCall(
            address(router),
            0,
            abi.encodeWithSelector(
                router.depositERC20AndCall.selector, address(reentrantToken), address(this), 0, new bytes(0), 0
            ),
            false
        );
        hevm.expectRevert("Only not in context");
        router.depositERC20(address(reentrantToken), 1, 0);
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
