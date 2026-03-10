// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

/// @title PolySafeLib
/// @notice Helper library to compute Polymarket gnosis safe addresses
library PolySafeLib {
    /// @dev GnosisSafeProxy creation code compiled with Foundry (solc 0.8.4, optimizer 200, Istanbul EVM).
    ///      Updated from Polymarket's original Hardhat-compiled constant to match our Poly SafeProxyFactory
    ///      deployment. The proxy logic is identical; only the IPFS metadata hash differs.
    bytes private constant proxyCreationCode =
        hex"608060405234801561001057600080fd5b5060405161017138038061017183398101604081905261002f916100b9565b6001600160a01b0381166100945760405162461bcd60e51b815260206004820152602260248201527f496e76616c69642073696e676c65746f6e20616464726573732070726f766964604482015261195960f21b606482015260840160405180910390fd5b600080546001600160a01b0319166001600160a01b03929092169190911790556100e7565b6000602082840312156100ca578081fd5b81516001600160a01b03811681146100e0578182fd5b9392505050565b607c806100f56000396000f3fe6080604052600080546001600160a01b0316813563530ca43760e11b1415602857808252602082f35b3682833781823684845af490503d82833e806041573d82fd5b503d81f3fea264697066735822122004356d37e05102655be65c4848223c2cf91f2f887bb3aaf1c0ebaa8a5130562f64736f6c63430008040033";

    /// @notice Gets the Polymarket Gnosis safe address for a signer
    /// @param signer   - Address of the signer
    /// @param deployer - Address of the deployer contract
    function getSafeAddress(address signer, address implementation, address deployer)
        internal
        pure
        returns (address safe)
    {
        bytes32 bytecodeHash = keccak256(getContractBytecode(implementation));
        bytes32 salt = keccak256(abi.encode(signer));
        safe = _computeCreate2Address(deployer, bytecodeHash, salt);
    }

    function getContractBytecode(address masterCopy) internal pure returns (bytes memory) {
        return abi.encodePacked(proxyCreationCode, abi.encode(masterCopy));
    }

    function _computeCreate2Address(address deployer, bytes32 bytecodeHash, bytes32 salt)
        internal
        pure
        returns (address)
    {
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, bytecodeHash));
        return address(uint160(uint256(_data)));
    }
}
