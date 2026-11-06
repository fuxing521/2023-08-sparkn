
 // SPDX-License-Identifier: MIT
 pragma solidity ^0.8.18;

 import {Test} from "forge-std/Test.sol";
 import {console2} from "forge-std/console2.sol";
 import {ProxyFactory} from "../src/ProxyFactory.sol";
 import {MockERC20} from "./mock/MockERC20.sol";

 contract M01EIP712DigestTest is Test {
     ProxyFactory factory;

     function setUp() public {
        MockERC20 token = new MockERC20("MockUSDC", "MUSDC");
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        factory = new ProxyFactory(tokens);
    }

     function testCompareDigests() public {
        bytes32 contestId = bytes32("contest001");
        bytes memory data = hex"12345678";
        bytes32 domainTypeHash = keccak256(
             "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(domainTypeHash,keccak256(bytes("ProxyFactory")),
            keccak256(bytes("1")),block.chainid,address(factory)));

        bytes32 sparknStructHash = keccak256(abi.encode(contestId, data));

        bytes32 typeHash = keccak256("Distribute(bytes32 contestId,bytes data)");
        bytes32 standardStructHash = keccak256(abi.encode(typeHash,contestId,keccak256(data)));
        bytes32 sparknDigest = keccak256(abi.encodePacked(hex"1901",domainSeparator,sparknStructHash));

        bytes32 standardDigest = keccak256(abi.encodePacked(hex"1901",domainSeparator,standardStructHash)); 

        console2.log("Sparkn Original Digest");
        console2.logBytes32(sparknDigest);

        console2.log("Standard EIP712 Digest");
        console2.logBytes32(standardDigest);

        assertNotEq(sparknStructHash, standardStructHash);
        assertNotEq(sparknDigest, standardDigest);

    {
        (uint8 v, bytes32 r, bytes32 s) =vm.sign(0xA11CE, sparknDigest);
        assertEq(ecrecover(sparknDigest, v, r, s),vm.addr(0xA11CE));

        assertNotEq(ecrecover(standardDigest, v, r, s),vm.addr(0xA11CE));
    }

    {
        (uint8 v, bytes32 r, bytes32 s) =vm.sign(0xA11CE, standardDigest);
        assertEq(ecrecover(standardDigest, v, r, s),vm.addr(0xA11CE));

        assertNotEq(ecrecover(sparknDigest, v, r, s),vm.addr(0xA11CE));
    }
    }

    function testFactoryRejectsStandardSignature() public {
        uint256 privateKey = 0xA11CE;
        address organizer = vm.addr(privateKey);
        bytes32 contestId = bytes32("contest001");
        bytes memory data = hex"12345678";
        bytes memory signature;
    { 
        bytes32 domainSeparator = keccak256(
        abi.encode(keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes("ProxyFactory")),
        keccak256(bytes("1")),
        block.chainid,
        address(factory)));

        bytes32 typeHash = keccak256("Distribute(bytes32 contestId,bytes data)");
        bytes32 standardStructHash = keccak256(abi.encode(typeHash,contestId,keccak256(data)));
        bytes32 standardDigest = keccak256(abi.encodePacked(hex"1901",domainSeparator,standardStructHash));
   
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, standardDigest);
        signature = abi.encodePacked(r, s, v);
    }

        vm.expectRevert(bytes4(keccak256("ProxyFactory__InvalidSignature()")));

        factory.deployProxyAndDistributeBySignature(organizer,contestId,address(0xBEEF),signature,data);
    }
}
