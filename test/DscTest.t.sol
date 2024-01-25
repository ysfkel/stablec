// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        MockERC20(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////////////
    // Constructor Tests ///////////
    ////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
   function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
   }

    /////////////////////////
    // Price Tests //////////
    /////////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        // 1205e18 * 2000/ETH = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
            // price $2000/ETH  
        // we have $100 
        // we have 100 / 2000 = 0.5 
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
        console.log("hello foundry ", actualWeth);
    }

    //////////////////////////////////
    // DepositCollateral Test ////////
    //////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public { 
       MockERC20 mockToken = new MockERC20("MockToken", "MKT");
       mockToken.mint(USER, AMOUNT_COLLATERAL);
       vm.startPrank(USER);
       vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(mockToken)));
       engine.depositCollateral(address(mockToken), AMOUNT_COLLATERAL);
       vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        MockERC20(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 expectedDepositedAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

     
}
