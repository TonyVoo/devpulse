"""Fixed-window rate limiting in Redis: brute-force and abuse protection for login,
registration, invitations, password changes and AI spend (docs/SECURITY.md)."""

import hashlib

from redis.asyncio import Redis

from app.core.errors import RateLimited


async def enforce_rate_limit(
    redis: Redis,
    *,
    scope: str,
    key: str,
    limit: int,
    window_s: int,
    message: str = "Too many attempts, try again later",
) -> None:
    digest = hashlib.sha256(key.encode()).hexdigest()[:32]  # never store raw emails/IPs as keys
    redis_key = f"rl:{scope}:{digest}"
    async with redis.pipeline(transaction=True) as pipe:
        pipe.incr(redis_key)
        pipe.expire(redis_key, window_s, nx=True)
        count, _ = await pipe.execute()
    if int(count) > limit:
        ttl = await redis.ttl(redis_key)
        raise RateLimited(
            message,
            headers={"Retry-After": str(max(int(ttl), 1))},
        )
