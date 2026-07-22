// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// Real NVDA prints from Hood Chain, packed as 5 bytes of timestamp and 8
/// bytes of price. Rounds arrive later; the reader lives here.
library History {
    bytes internal constant BLOB = hex"";

    function load() internal pure returns (uint40[] memory ts, uint64[] memory px) {
        bytes memory b = BLOB;
        uint256 n = b.length / 13;
        ts = new uint40[](n);
        px = new uint64[](n);
        for (uint256 i = 0; i < n; ++i) {
            uint256 o = 32 + i * 13;
            uint256 w;
            assembly { w := mload(add(b, o)) }
            ts[i] = uint40(w >> 216);
            px[i] = uint64((w >> 152) & 0xffffffffffffffff);
        }
    }
}
