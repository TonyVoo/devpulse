"""UUIDv7 (RFC 9562): time-ordered ids for good B-tree locality.

Python 3.12's stdlib has no uuid7; this is a small, spec-conformant implementation.
"""

import os
import time
from uuid import UUID


def uuid7() -> UUID:
    ts_ms = time.time_ns() // 1_000_000
    rand = int.from_bytes(os.urandom(10), "big")
    rand_a = rand >> 62 & 0xFFF  # 12 bits
    rand_b = rand & ((1 << 62) - 1)  # 62 bits
    value = (ts_ms & ((1 << 48) - 1)) << 80
    value |= 0x7 << 76  # version 7
    value |= rand_a << 64
    value |= 0b10 << 62  # RFC 4122 variant
    value |= rand_b
    return UUID(int=value)
