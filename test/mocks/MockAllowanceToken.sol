// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @dev Plain ERC-20 for the localhost viem integration. Its unique name avoids upstream mock artifact collisions.
contract MockAllowanceToken is ERC20 {
    constructor() ERC20("Example USD", "USD") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }
}
