// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Test} from "forge-std/Test.sol";
import {ProxyFactory} from "../src/ProxyFactory.sol";
import {Distributor} from "../src/Distributor.sol";
import {Proxy} from "../src/Proxy.sol";
import {MockERC20} from "./mock/MockERC20.sol";
import {ECDSA} from "openzeppelin/utils/cryptography/ECDSA.sol";
contract F01SignatureScopeTest is Test{
    ProxyFactory factory;
    Distributor implementationX;
    Distributor implementationY;
    MockERC20 usdc;
    uint256 organizerPrivateKey = 0xA11CE;
    address organizer;
    address sponsor = address(0x1111);
    address stadium = address(0x3333);
    bytes32 contestId = bytes32("contest001");
    bytes32 saltX;
    bytes32 saltY;
    address proxyX;
    address proxyY;

    function setUp() public {
        organizer = vm.addr(organizerPrivateKey);
        usdc = new MockERC20("MockUSDC","MUSDC");
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        factory = new ProxyFactory(tokens);
        implementationX = new Distributor(address(factory),stadium);
        implementationY = new Distributor(address(factory),stadium);
        saltX = keccak256(abi.encode(organizer,contestId,implementationX));
        saltY = keccak256(abi.encode(organizer,contestId,implementationY));
        proxyX = factory.getProxyAddress(saltX,address(implementationX));
        proxyY = factory.getProxyAddress(saltY,address(implementationY));
        uint256 closeTime = block.timestamp + 21 days;
        factory.setContest(organizer,contestId,closeTime,address(implementationX));
        factory.setContest(organizer,contestId,closeTime,address(implementationY));
        usdc.mint(sponsor,6000e18);
        vm.prank(sponsor);
        usdc.transfer(proxyX,1000e18);
        vm.prank(sponsor);
        usdc.transfer(proxyY,5000e18);
    }

    function testRegisteredImplementations() public {
        assertNotEq(address(implementationX),address(implementationY));
        assertNotEq(saltX,saltY);
        assertNotEq(proxyX,proxyY);
        assertGt(factory.saltToCloseTime(saltX),0);
        assertGt(factory.saltToCloseTime(saltY),0);
        assertEq(usdc.balanceOf(proxyX),1000e18);
        assertEq(usdc.balanceOf(proxyY),5000e18);
        assertEq(proxyX.code.length,0);
        assertEq(proxyY.code.length,0);
    }

    function testOrganizerSignature() public {
        address[] memory winners = new address[](2);
        winners[0] = address(0x5555);
        winners[1] = address(0x6666);
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 6000;
        percentages[1] = 3500;
        bytes memory callData = abi.encodeWithSelector(implementationX.distribute.selector,
        address(usdc),winners,percentages,hex"");
        bytes memory signature;
        {
        bytes32 domainTypeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(abi.encode(
            domainTypeHash,keccak256(bytes("ProxyFactory")),keccak256(bytes("1")),block.chainid,address(factory)));
        bytes32 structHash = keccak256(abi.encode(contestId,callData));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901",domainSeparator,structHash));
        (uint8 v,bytes32 r,bytes32 s) = vm.sign(organizerPrivateKey,digest);
        signature = abi.encodePacked(r,s,v);
        address recoveredSigner = ECDSA.recover(digest,signature);
        assertEq(recoveredSigner,organizer);
        assertEq(signature.length,65);
        }
        vm.warp(block.timestamp + 22 days);
        vm.prank(address(0x9999));
        factory.deployProxyAndDistributeBySignature(organizer,contestId,address(implementationX),signature,callData);
        assertGt(proxyX.code.length, 0);
        assertEq(usdc.balanceOf(proxyX),0);
        assertEq(usdc.balanceOf(winners[0]),600e18);
        assertEq(usdc.balanceOf(winners[1]),350e18);
        assertEq(usdc.balanceOf(stadium),50e18);
        assertEq(usdc.balanceOf(proxyY),5000e18);
        assertEq(proxyY.code.length,0);
        vm.prank(address(0x8888));
        address deployedY = factory.deployProxyAndDistributeBySignature(
            organizer,contestId,address(implementationY),signature,callData);
        assertEq(proxyY,deployedY);
        assertGt(proxyY.code.length,0);
        assertEq(usdc.balanceOf(proxyY),0);
        assertEq(usdc.balanceOf(winners[0]),3600e18);
        assertEq(usdc.balanceOf(winners[1]),2100e18);
        assertEq(usdc.balanceOf(stadium),300e18);

    }
}
