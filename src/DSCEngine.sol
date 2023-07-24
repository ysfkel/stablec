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
    error DSCEngine_PriceFeedAddressesMustBeSameLength();
    error DSCEngine_NotAllowedToken(address tokenCollateral);
    error DSCEngine_TransferFailed();

    /////////////////////
    // State Variables //
    /////////////////////
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => uint256 amount) private s_DSCMinted;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    address[] private s_collateralTokens;
    DecentralizedStableCoin private immutable i_dsc;

    /////////////////////
    // Events         //
    /////////////////////
    event CollateralDeposited(address user, address tokenCollateral, uint256 amount);

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
            revert DSCEngine_NotAllowedToken(token);
        }
        _;
    }

    /////////////////
    /// Functions ///
    /////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAdresses, address dscEnginge) {
        if (tokenAddresses.length != priceFeedAdresses.length) {
            revert DSCEngine_PriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAdresses[i];
            collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscEnginge);
    }

    ///////////////////////////
    /// External Functions ///
    ///////////////////////////
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI - checks effects interaction
     * @param tokenCollateral The adrdess of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateral, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateral)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateral] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateral, amountCollateral);
        if (IERC20(tokenCollateral).transferFrom(msg.sender, address(this), amountCollateral)) {
            revert DSCEngine_TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}
    function redeemCollateral() external {}

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice they must have more collateral than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
    }
    function burnDsc() external {}
    function liquidate() external {}
    function getHealthFactor() external view {}

    /////////////////////////////////////////
    // Private and Internal view functions //
    /////////////////////////////////////////

    function _getAccountInformation(address user) private view returns(uint256 totalMinted, uint256 collateralValueInUsd) {
        totalMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        // 1 get total
        (uint256 totalMinted, uint256 collateralValueInUsd) = _getAccountInformation(user); 
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
    function revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health facrtor - do they have enough collateral
        // 2. Revrt if they dont

    }
   
    /////////////////////////////////////
    // Public & External View Funtions // 
    /////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns(uint256 collateralValueInUsd) {
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
             address token = s_collateralTokens[i];
             uint256 amount = s_collateralDeposited[user][token]; 
            //totalCollateralValueInUsd +=  
        } 
    }
}   

// Threshold set to lets say 150 %
// $150 ETH -> $75 ETH => collateral should never tank less than $75
// $50 DSC
// - liquidation
// If you are under the Threshold eg $74 and someone pays back your minted DSC. they have have all your collateral for a discount
// someone pays $50 DSC and gets your $74 USD worth of ETH
