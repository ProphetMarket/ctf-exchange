// SPDX-License-Identifier: MIT
pragma solidity <0.9.0;

import { IAuth } from "../interfaces/IAuth.sol";

/// @title Auth
/// @notice Provides admin and operator roles and access control modifiers
abstract contract Auth is IAuth {
    /// @dev The set of addresses authorized as Admins
    mapping(address => uint256) public admins;

    /// @dev The set of addresses authorized as Operators
    mapping(address => uint256) public operators;

    /// @dev The number of active admins
    uint256 public adminCount;

    /// @dev The address proposed as a new admin via two-step transfer
    address public pendingAdmin;

    modifier onlyAdmin() {
        if (admins[msg.sender] != 1) revert NotAdmin();
        _;
    }

    modifier onlyOperator() {
        if (operators[msg.sender] != 1) revert NotOperator();
        _;
    }

    constructor() {
        admins[msg.sender] = 1;
        adminCount = 1;
        operators[msg.sender] = 1;
    }

    function isAdmin(address usr) external view returns (bool) {
        return admins[usr] == 1;
    }

    function isOperator(address usr) external view returns (bool) {
        return operators[usr] == 1;
    }

    /// @notice Adds a new admin
    /// Can only be called by a current admin
    /// @param admin_ - The new admin
    function addAdmin(address admin_) external onlyAdmin {
        if (admins[admin_] != 1) {
            admins[admin_] = 1;
            adminCount++;
        }
        emit NewAdmin(admin_, msg.sender);
    }

    /// @notice Adds a new operator
    /// Can only be called by a current admin
    /// @param operator_ - The new operator
    function addOperator(address operator_) external onlyAdmin {
        operators[operator_] = 1;
        emit NewOperator(operator_, msg.sender);
    }

    /// @notice Removes an existing Admin
    /// Can only be called by a current admin
    /// @param admin - The admin to be removed
    function removeAdmin(address admin) external onlyAdmin {
        if (admins[admin] == 1) {
            if (adminCount <= 1) revert CannotRemoveLastAdmin();
            admins[admin] = 0;
            adminCount--;
        }
        emit RemovedAdmin(admin, msg.sender);
    }

    /// @notice Removes an existing operator
    /// Can only be called by a current admin
    /// @param operator - The operator to be removed
    function removeOperator(address operator) external onlyAdmin {
        operators[operator] = 0;
        emit RemovedOperator(operator, msg.sender);
    }

    /// @notice Removes the admin role for the caller
    /// Can only be called by an existing admin
    function renounceAdminRole() external onlyAdmin {
        if (adminCount <= 1) revert CannotRemoveLastAdmin();
        admins[msg.sender] = 0;
        adminCount--;
        emit RemovedAdmin(msg.sender, msg.sender);
    }

    /// @notice Removes the operator role for the caller
    /// Can only be called by an exiting operator
    function renounceOperatorRole() external onlyOperator {
        operators[msg.sender] = 0;
        emit RemovedOperator(msg.sender, msg.sender);
    }

    /// @notice Proposes a new admin via two-step transfer (L-05)
    /// The proposed address must call acceptAdmin() to complete the transfer.
    /// @param newAdmin - The address to propose as admin
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        if (admins[newAdmin] == 1) revert AlreadyAdmin();
        pendingAdmin = newAdmin;
        emit AdminTransferProposed(msg.sender, newAdmin);
    }

    /// @notice Accepts a pending admin role proposed via transferAdmin
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert NotPendingAdmin();
        if (admins[msg.sender] == 1) revert AlreadyAdmin();
        admins[msg.sender] = 1;
        adminCount++;
        pendingAdmin = address(0);
        emit NewAdmin(msg.sender, msg.sender);
    }
}
