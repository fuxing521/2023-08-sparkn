// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test} from "forge-std/Test.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {Distributor} from "../src/Distributor.sol";
import {Proxy} from "../src/Proxy.sol";
contract CREATE2PrefundAddressMismatchTest is Test {
    ProxyFactory factory;
    MockERC20 usdc;
    Distributor implementation;
    address sponsor = address(0x1111);
    address stadiumAddress = address(0x3333);
    address organizer = address(0x4444);
    bytes32 contestId = "1" ;
    address[] winners;
    uint256[] percentage;
    bytes eventData = abi.encode(bytes32("contest1"));
    bytes callData;
    function  setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC");
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        factory = new ProxyFactory(tokens);
        usdc.mint(sponsor,1000e18);
        implementation = new Distributor(address(factory),stadiumAddress);
        winners.push(address(0x5555));
        winners.push(address(0x6666));
        winners.push(address(0x7777));
        percentage.push(6000);
        percentage.push(2000);
        percentage.push(1500);
        callData = abi.encodeWithSelector(
            implementation.distribute.selector,
            address(usdc),
            winners,
            percentage,
            eventData
        );
    }

    function testUnregisteredSalt() public {
        factory.setContest(organizer,contestId,block.timestamp + 20 days,address(implementation));
        bytes32 saltA = keccak256(abi.encode(organizer,contestId,implementation));
        address predictedA = factory.getProxyAddress(saltA,address(implementation));
        bytes32 saltB = keccak256(abi.encode("Unregestered"));
        address implementationAddressB = address(0xBEEF);
        address predictedB = factory.getProxyAddress(saltB,implementationAddressB);
        assertNotEq(predictedA,predictedB);
        assertEq(factory.saltToCloseTime(saltB),0);
        vm.prank(sponsor);
        usdc.transfer(predictedB,1000e18);
        assertEq(usdc.balanceOf(predictedB),1000e18);
        assertEq(predictedB.code.length , 0);
        vm.warp(block.timestamp + 21 days);
        vm.expectRevert(bytes4(keccak256("ProxyFactory__DelegateCallFailed()")));
        vm.prank(organizer);
        factory.deployProxyAndDistribute(contestId,address(implementation),callData);
        assertEq(usdc.balanceOf(predictedB),1000e18);
        assertEq(usdc.balanceOf(predictedA),0);
        assertEq(predictedA.code.length,0);
    }
    
    function testCurrentAddressCanDistribute() public {
        factory.setContest(organizer,contestId,block.timestamp + 20 days,address(implementation));
        bytes32 salt = keccak256(abi.encode(organizer,contestId,implementation));
        address predicted = factory.getProxyAddress(salt,address(implementation));
        vm.prank(sponsor);
        usdc.transfer(predicted,1000e18);
        assertEq(usdc.balanceOf(predicted),1000e18);
        assertEq(predicted.code.length,0);
        vm.warp(block.timestamp + 21 days);
        vm.prank(organizer);
        address deployed = factory.deployProxyAndDistribute(contestId,address(implementation),callData);
        assertEq(predicted,deployed);
        assertGt(predicted.code.length,0);
        assertEq(usdc.balanceOf(winners[0]),600e18);
        assertEq(usdc.balanceOf(winners[1]),200e18);
        assertEq(usdc.balanceOf(winners[2]),150e18);
        assertEq(usdc.balanceOf(stadiumAddress),50e18);
        assertEq(usdc.balanceOf(predicted),0);
    }
    

    
}