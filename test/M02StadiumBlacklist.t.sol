// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {Distributor} from "../src/Distributor.sol";

contract StadiumBlockedToken is ERC20{
    address public stadium;
    bool public blockStadium;
    error BlockedRecipient(address stadium);
    constructor (address _stadium) ERC20("Mock Token", "MTK") {
        stadium = _stadium;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlockStadium(bool blocked) external {
        blockStadium = blocked;
    }

    function _beforeTokenTransfer(address from,address to,uint256 amount) internal override {

        if (blockStadium && to == stadium) {
        revert BlockedRecipient(to);}
        super._beforeTokenTransfer(from, to, amount);
    }
}

contract M02StadiumBlacklistTest is Test {
    StadiumBlockedToken token;
    ProxyFactory factory;
    Distributor distributor;
    address stadium = address(0x3333);
    address winnerA = address(0x1111);
    address winnerB = address(0x2222);

    function setUp() public {
        token = new StadiumBlockedToken(stadium);
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        factory = new ProxyFactory(tokens);
        distributor = new Distributor(address(factory),stadium);
        token.mint(address(distributor), 1000e18);
    }

    function _distribute() internal {
        address[] memory winners = new address[](2);
        winners[0] = winnerA;
        winners[1] = winnerB;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 6000;
        percentages[1] = 3500;

        vm.prank(address(factory));
        distributor.distribute(address(token),winners,percentages,hex"");
    }

    function testNormalDistribution() public {
        _distribute();
        assertEq(token.balanceOf(winnerA),600e18);
        assertEq(token.balanceOf(winnerB),350e18);
        assertEq(token.balanceOf(stadium),50e18);
        assertEq(token.balanceOf(address(distributor)),0);
    }

    function testBlockedStadiumRollsBackWinners() public {
        token.setBlockStadium(true);
        vm.expectRevert(abi.encodeWithSelector(StadiumBlockedToken.BlockedRecipient.selector,stadium));
        _distribute();
        assertEq(token.balanceOf(winnerA),0);
        assertEq(token.balanceOf(winnerB),0);
        assertEq(token.balanceOf(stadium),0);
        assertEq(token.balanceOf(address(distributor)),1000e18);
    }



}