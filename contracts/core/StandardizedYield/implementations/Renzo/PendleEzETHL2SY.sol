// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../../SYBase.sol";
import "../../../../interfaces/Renzo/IRenzoDepositL2.sol";
import "../../../../interfaces/Connext/IConnext.sol";

// Using wETH instead of ETH for deposit
// --- 1. For Arbitrum/OP (ETH gas chain), using ETH as token in means wETH user would have to unwrap -> wrap on Renzo side.
// --- 2. There's no ETH on BSC, so this implementation still works there
// --- 3. Not doing both ETH and wETH is shorter, and also reusable on BSC

contract PendleEzETHL2SY is SYBase {
    using PMath for uint256;

    address public immutable ezETH;
    address public immutable renzoDeposit;
    address public immutable wETH;

    address public immutable connext;
    bytes32 public immutable swapKey;

    uint8 public immutable depositTokenId;
    uint8 public immutable collateralTokenId;

    constructor(
        address _ezETH,
        address _renzoDeposit,
        address _wETH,
        uint8 _depositTokenId,
        uint8 _collateralTokenId
    ) SYBase("SY Renzo ezETH", "SY-ezETH", _ezETH) {
        ezETH = _ezETH;
        renzoDeposit = _renzoDeposit;
        wETH = _wETH;

        // Connext preview
        depositTokenId = _depositTokenId;
        collateralTokenId = _collateralTokenId;
        connext = IRenzoDepositL2(renzoDeposit).connext();
        swapKey = IRenzoDepositL2(renzoDeposit).swapKey();

        _safeApproveInf(wETH, renzoDeposit);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual override returns (uint256) {
        if (tokenIn == wETH) {
            return IRenzoDepositL2(renzoDeposit).deposit(amountDeposited, 0, type(uint256).max);
        }
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256) {
        _transferOut(ezETH, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/
    function exchangeRate() public view override returns (uint256) {
        return IRenzoDepositL2(renzoDeposit).lastPrice();
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(address tokenIn, uint256 amountTokenToDeposit) internal view override returns (uint256) {
        if (tokenIn == wETH) {
            uint256 amountWETHBridged = IConnext(connext).calculateSwap(
                swapKey,
                depositTokenId,
                collateralTokenId,
                amountTokenToDeposit
            );

            uint256 feeBps = IRenzoDepositL2(renzoDeposit).bridgeRouterFeeBps();
            amountWETHBridged -= amountWETHBridged * feeBps / 10_000;

            uint256 lastPrice = IRenzoDepositL2(renzoDeposit).lastPrice();
            return amountWETHBridged.divDown(lastPrice);
        }
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(ezETH, wETH);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(ezETH);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == ezETH || token == wETH;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == ezETH;
    }

    // Putting ERC WETH here so it works on both eth gas chain and BNB
    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, wETH, 18);
    }
}