// SPDX-License-Identifier: MIT  
// Handler is going to narror down the way we call function 

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract Handler {
   DSCEngine engine;
   DecentralizedStableCoin dsc;
   MockERC20 weth;
   MockERC20 wbtc;

   constructor(DSCEngine _engine, DecentralizedStableCoin _dsc) {
       engine = _engine;
       dsc = _dsc;
   }

   function depositCollateral(address collateral, uint256 amountCollateral) public {
      engine.depositCollateral(collateral, amountCollateral);
   }

   function _getCollateralFromSeed(uint256 collateralSeed) private view returns(MockERC20) {
     if(collateralSeed % 2 == 0) {
        return MockERC20(weth);
     } else {

     }
   }
}