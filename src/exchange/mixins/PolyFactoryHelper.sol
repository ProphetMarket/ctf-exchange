// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { PolySafeLib } from "../libraries/PolySafeLib.sol";
import { PolyProxyLib } from "../libraries/PolyProxyLib.sol";

interface IPolyProxyFactory {
    function getImplementation() external view returns (address);
}

interface IPolySafeFactory {
    function masterCopy() external view returns (address);
}

abstract contract PolyFactoryHelper {
    /// @notice The Polymarket Proxy Wallet Factory Contract
    address public proxyFactory;
    /// @notice The Polymarket Gnosis Safe Factory Contract
    address public safeFactory;

    /// @notice Delay before a scheduled factory change can be applied.
    ///         Gives users time to cancel orders tied to the current factory.
    uint256 public constant FACTORY_TIMELOCK = 48 hours;

    struct PendingFactory {
        address newAddress;
        uint256 effectiveAt;
    }

    PendingFactory public pendingProxyFactory;
    PendingFactory public pendingSafeFactory;

    event ProxyFactoryUpdated(address indexed oldProxyFactory, address indexed newProxyFactory);
    event SafeFactoryUpdated(address indexed oldSafeFactory, address indexed newSafeFactory);
    event ProxyFactoryChangeScheduled(address indexed newFactory, uint256 effectiveAt);
    event SafeFactoryChangeScheduled(address indexed newFactory, uint256 effectiveAt);
    event ProxyFactoryChangeCancelled();
    event SafeFactoryChangeCancelled();

    error NoFactoryChangeScheduled();
    error TimelockNotElapsed();

    constructor(address _proxyFactory, address _safeFactory) {
        proxyFactory = _proxyFactory;
        safeFactory = _safeFactory;
    }

    /// @notice Gets the Proxy factory address
    function getProxyFactory() public view returns (address) {
        return proxyFactory;
    }

    /// @notice Gets the Safe factory address
    function getSafeFactory() public view returns (address) {
        return safeFactory;
    }

    /// @notice Gets the Polymarket Proxy factory implementation address
    function getPolyProxyFactoryImplementation() public view returns (address) {
        return IPolyProxyFactory(proxyFactory).getImplementation();
    }

    /// @notice Gets the Safe factory implementation address
    function getSafeFactoryImplementation() public view returns (address) {
        return IPolySafeFactory(safeFactory).masterCopy();
    }

    /// @notice Gets the Polymarket proxy wallet address for an address
    /// @param _addr    - The address that owns the proxy wallet
    function getPolyProxyWalletAddress(address _addr) public view returns (address) {
        return PolyProxyLib.getProxyWalletAddress(_addr, getPolyProxyFactoryImplementation(), proxyFactory);
    }

    /// @notice Gets the Polymarket Gnosis Safe address for an address
    /// @param _addr    - The address that owns the proxy wallet
    function getSafeAddress(address _addr) public view returns (address) {
        return PolySafeLib.getSafeAddress(_addr, getSafeFactoryImplementation(), safeFactory);
    }

    // ── Proxy Factory Timelock ───────────────────────────────────

    function _scheduleProxyFactory(address _newProxyFactory) internal {
        require(_newProxyFactory != address(0), "zero address");
        uint256 effectiveAt = block.timestamp + FACTORY_TIMELOCK;
        pendingProxyFactory = PendingFactory(_newProxyFactory, effectiveAt);
        emit ProxyFactoryChangeScheduled(_newProxyFactory, effectiveAt);
    }

    function _applyProxyFactory() internal {
        PendingFactory memory pending = pendingProxyFactory;
        if (pending.newAddress == address(0)) revert NoFactoryChangeScheduled();
        if (block.timestamp < pending.effectiveAt) revert TimelockNotElapsed();
        emit ProxyFactoryUpdated(proxyFactory, pending.newAddress);
        proxyFactory = pending.newAddress;
        delete pendingProxyFactory;
    }

    function _cancelProxyFactory() internal {
        delete pendingProxyFactory;
        emit ProxyFactoryChangeCancelled();
    }

    // ── Safe Factory Timelock ────────────────────────────────────

    function _scheduleSafeFactory(address _newSafeFactory) internal {
        require(_newSafeFactory != address(0), "zero address");
        uint256 effectiveAt = block.timestamp + FACTORY_TIMELOCK;
        pendingSafeFactory = PendingFactory(_newSafeFactory, effectiveAt);
        emit SafeFactoryChangeScheduled(_newSafeFactory, effectiveAt);
    }

    function _applySafeFactory() internal {
        PendingFactory memory pending = pendingSafeFactory;
        if (pending.newAddress == address(0)) revert NoFactoryChangeScheduled();
        if (block.timestamp < pending.effectiveAt) revert TimelockNotElapsed();
        emit SafeFactoryUpdated(safeFactory, pending.newAddress);
        safeFactory = pending.newAddress;
        delete pendingSafeFactory;
    }

    function _cancelSafeFactory() internal {
        delete pendingSafeFactory;
        emit SafeFactoryChangeCancelled();
    }
}
