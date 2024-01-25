// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author Yusuf Kelo
 * This system is designed to be a minimal as possible and have the tokens maintain a 1 token == $1 peg .
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically Stable
 * It is similar to DAI if DAI had no governance , no fees and was only backed by WETH and WBTC
 *
 * Our DSC sytem should always be over collateralzied, A no point sshould the value of all collateral <= the $ backed value of all the DSC
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming as well as deposiing and withdrawing collaetral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /////////////////
    //  Errors     //
    //////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken(address tokenCollateral);
    error DSCEngine__TransferFailed();
    error DSCDSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSC__MintFailed();
    error DSCEngine__HealthFactorOk(address user);
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////
    // State Variables //
    /////////////////////
    uint256 private LIQUIDATION_THRESHOLD = 50; //50% liquidation threshold means we need to be 200% overcollateralized
    uint256 private LIQUIDATION_PRECISION = 100;
    uint256 private MIN_HEALTH_FACTOR = 1e18;
    uint256 private PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This is a 10 % bonus given to liquidators
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => uint256 amount) private s_DSCMinted;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    /////////////////////
    // Events         //
    /////////////////////
    event CollateralDeposited(address indexed user, address tokenCollateral, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256  amount);

    /////////////////
    /// Modifiers ///
    /////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken(token);
        }
        _;
    }

    /////////////////
    /// Functions ///
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAdresses, address dscEnginge) {
        if (tokenAddresses.length != priceFeedAdresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAdresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscEnginge);
    }

    ///////////////////////////
    /// External Functions ///
    ///////////////////////////

    /***
     * @param tokenCollateral The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of descentralized stablecoin to mint
     * @notice This token will deposit and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
      address tokenCollateral,
      uint256 amountCollateral, 
      uint256 amountDscToMint) external {
        depositCollateral(tokenCollateral, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI - checks effects interaction
     * @param tokenCollateral The adrdess of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateral, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateral] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateral, amountCollateral);
        bool success = IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * 
     * @param tokenCollateral The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC and redeems underlying DSC
     */
    function redeemCollateralForDsc( address tokenCollateral, uint256  amountCollateral, uint256 amountDscToBurn) external {
           burnDsc(amountDscToBurn);
           redeemCollateral(tokenCollateral, amountCollateral);
           // redeemCollateral already checks health factor
    }
    function redeemCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral) 
        moreThanZero(amountCollateral) nonReentrant()public {
         _redeemCollateral(msg.sender, msg.sender,tokenCollateralAddress, amountCollateral);
         _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        if (!i_dsc.mint(msg.sender, amountDscToMint)) {
            revert DSC__MintFailed();
        }
    }
    

    function burnDsc(uint256 amount) public {
        _burnDsc(msg.sender, msg.sender, amount);
       _revertIfHealthFactorIsBroken(msg.sender); // I do not think this line will ever hit, thinking of pulling it out, because burning debt will not reduce health factor
    }
    
    /**
     * @param collateral The ERC20 collateral to receive / liquidate from user
     * @param userToLiquidate user to liquidate -> user who has broken the health factor
     * @param debt Debt to cover -> The amount of DSC to burn to improve user health factor
     * 
     * @notice originally $100 ETH backing -> $50 DSC 
     *         current    $75  ETH backing -> $50 DCS
     *         if someone is almost under collateralized, we will pay you to liquidate  them !
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This fundtion working assumes the protocol will be roughly 200% overcollateralized in otder to work 
     * @notice A known bug would be if the protocol were 100% or less collateralized , then we wouldnt be able to incentivize the liquidator.
     *         for example if the price of the collateral plummeted before anyone could be liquidated
     */

    function liquidate(address collateral, address userToLiquidate, uint256 debt)
      moreThanZero(debt) nonReentrant() external {
          
          uint256 startingUserHealthFactor = _healthFactor(userToLiquidate);
          if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
              revert DSCEngine__HealthFactorOk(userToLiquidate);
          }
          // we want to burn their DSC "debt"
          // and take their collateral
          // Bad user: $140 ETH, $100 DSC 
          // debt to cover 100 DSC
          // $100 of DSC == ?? ETH  
          // 0.05 
          uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debt);
          // in addition to gving the liquidator the collateral 
          // we also give them a 10% bonus to incentise them 
          // so we are giving the liquidator $110 of WETH for 100 DSC 
          uint256 bonusCollateral = ( tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
          uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
          _redeemCollateral(userToLiquidate, msg.sender, collateral, debt);  
          // we need to burn dsc
          _burnDsc(userToLiquidate, msg.sender, debt);
          // if health factor is not improved , revert 
          uint256 endingHealthFactor = _healthFactor(userToLiquidate);
          if(endingHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
          }
          _revertIfHealthFactorIsBroken(msg.sender);
    }
    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Private and Internal view functions //
    /////////////////////////////////////////

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress, 
        uint256 amountCollateral )  private  {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
         
         if(!IERC20(tokenCollateralAddress).transfer(to,amountCollateral)) {
            revert DSCEngine__TransferFailed();
         }
    }

    /**
     * @dev Low-level internal function , do not call unless the function calling it is checking for health factors being broker 
     */
    function _burnDsc(address onBehalfOf, address dscFrom,uint256 amountDscToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
       i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalMinted, uint256 collateralValueInUsd)
    {
        totalMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalMinted, uint256 collateralValueInUsd) internal view returns (uint256) {
        if (totalMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // eg 1000 ETH - collateralValueInUsd
        // LR - liquidation ration
        // PR - precision
        // 1000 ETH * 50 LR = 50,000 / 100 PR= 500
        return (collateralAdjustedForThreshold * PRECISION) / totalMinted;
    }

    /**
     * @notice The health factor is the numeric representation of the safety of your deposited
     * assets against the borrowed assets and its underlying value. The higher the value is,
     * the safer the state of your funds are against a liquidation scenario. If the health factor
     *  reaches 1, the liquidation of your deposits will be triggered.
     * https://docs.aave.com/faq/borrowing#what-is-the-health-factor
     * https://docs.aave.com/risk/asset-risk/risk-parameters#health-factor
     * @param user user adddress
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health facrtor - do they have enough collateral
        // 2. Revrt if they dont
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCDSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        uint256 precisePrice = getPrecisePrice(price, PRECISION, priceFeed.decimals());

        return (precisePrice * amount) / PRECISION;
        // The returned price value from CL    have 1e8 decimal
        // converts the price to 1e18 decimal and multiples by amount, and divides by 1e18
        //return ((uint256(price) * ADD_FEED_PRECISION) * amount) / PRECISION;
    }

    /////////////////////////////////////
    // Public & External View Funtions //
    /////////////////////////////////////

    function calculateHealthFactor(uint256 totalMinted, uint256 collateralValueInUsd) external view returns (uint256) {
        return _calculateHealthFactor(totalMinted, collateralValueInUsd);
    }


    /**
     * @notice calculates the amount of of collateral received for usdAmountInWei.
     *  usdAmountInWei / collateralPrice = collaetral amount
     * @param token collateral token address 
     * @param usdAmountInWei amount of usd in wei to pay for collateral 
     */
    function getTokenAmountFromUsd(address token , uint256 usdAmountInWei) public view returns(uint256){
         // price of ETH (token)
         // $/ETH ETH ??
         // $2000 / ETH. $1000 = 0.5 ETH 
         AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
         (, int256 price,,,) = priceFeed.latestRoundData(); 
         // price (collateral price) has 8 decimals places and we need it to have 18 decimals
         uint256 precisePrice = getPrecisePrice(price, PRECISION, priceFeed.decimals());
         // 10e18 / ($2000e8 * 1e10)  = 0.005 
         // using 1e18 as multiplyer for 10e18  
         // ($10e18 * 1e18 / ($2000e8 * 1e10) - where 1e10 is the additional decimals to make price which has decimal 1e8 = 1e18
         // = 5000000000000000
         // 5000000000000000 / 1e18 = 0.005000000000000000
         return (usdAmountInWei * PRECISION) / precisePrice;
    }

    /**
     * @notice returns total collateral value deposited by the user for all collateral assets
     * @param user user address
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][tokenAddress];
            totalCollateralValueInUsd += _getUsdValue(tokenAddress, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) external view returns (uint256 usdValue) {
        return _getUsdValue(token, amount);
    }
     
     /**
      * 
      * @param price collateral price
      * @param precision collateral token decimal precision
      * @param priceFeedDecimals price feed decimals
      */
     function getPrecisePrice(int256 price, uint256 precision, uint256 priceFeedDecimals ) public pure returns(uint256 precisePrice) {
        // The returned price value from CL could have a different precision e.g 1e8 decimal
        // we convert the price feed precision to match the collateral token precision 1e18 decimal for ETH for example.ab
        //  multiples by amount, and divides by 1e18
        uint256 priceFeedPrecision = 10 ** priceFeedDecimals;
        if (precision > priceFeedPrecision) {
            uint256 additional_feed_precision = precision / priceFeedPrecision;
            precisePrice = uint256(price) * additional_feed_precision;
            return precisePrice;
        } else {
            // when feed dcimal is greater (or if both are equal which would return 1)
            uint256 additional_feed_precision = priceFeedPrecision / precision;
            precisePrice = uint256(price) /  additional_feed_precision;
            return precisePrice;
        }
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalMinted, uint256 collateralValueInUsd)
    {
        (totalMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    //

    function getPrecision() external view returns (uint256) {
        return PRECISION;
    }

    // function getAdditionalFeedPrecision() external pure returns (uint256) {
    //     return ADDITIONAL_FEED_PRECISION;
    // }

    function getLiquidationThreshold() external view returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external view returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}

// Threshold set to lets say 150 %
// $150 ETH -> $75 ETH => collateral should never tank less than $75
// $50 DSC
// - liquidation
// If you are under the Threshold eg $74 and someone pays back your minted DSC. they have have all your collateral for a discount
// someone pays $50 DSC and gets your $74 USD worth of ETH
