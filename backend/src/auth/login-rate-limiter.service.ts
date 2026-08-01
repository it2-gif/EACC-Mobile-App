import { HttpException, HttpStatus, Injectable } from '@nestjs/common';

interface LoginRateLimitBucket {
  failures: number[];
  blockedUntil?: number;
}

interface LoginRateLimitDecision {
  limited: boolean;
  retryAfterSeconds?: number;
}

const USERNAME_FAILURE_LIMIT = 5;
const IP_FAILURE_LIMIT = 20;
const WINDOW_MS = 10 * 60 * 1000;
const BLOCK_MS = 15 * 60 * 1000;

@Injectable()
export class LoginRateLimiterService {
  private readonly usernameBuckets = new Map<string, LoginRateLimitBucket>();
  private readonly ipBuckets = new Map<string, LoginRateLimitBucket>();

  assertCanAttempt(input: { username: string; ipAddress: string }) {
    const now = Date.now();
    const usernameKey = this.usernameKey(input.username);
    const ipKey = this.ipKey(input.ipAddress);
    const decisions = [
      this.decisionFor(this.usernameBuckets.get(usernameKey), now),
      this.decisionFor(this.ipBuckets.get(ipKey), now),
    ].filter((decision) => decision.limited);

    if (decisions.length === 0) return;

    const retryAfterSeconds = Math.max(
      ...decisions.map((decision) => decision.retryAfterSeconds ?? 1),
    );

    throw new HttpException({
      code: 'RATE_LIMITED',
      message: `Too many failed login attempts. Please wait ${Math.ceil(
        retryAfterSeconds / 60,
      )} minute(s) and try again.`,
      retryAfterSeconds,
    }, HttpStatus.TOO_MANY_REQUESTS);
  }

  recordFailure(input: { username: string; ipAddress: string }) {
    const now = Date.now();
    this.recordBucketFailure(
      this.usernameBuckets,
      this.usernameKey(input.username),
      USERNAME_FAILURE_LIMIT,
      now,
    );
    this.recordBucketFailure(
      this.ipBuckets,
      this.ipKey(input.ipAddress),
      IP_FAILURE_LIMIT,
      now,
    );
    this.prune(now);
  }

  recordSuccess(input: { username: string; ipAddress: string }) {
    this.usernameBuckets.delete(this.usernameKey(input.username));
    this.ipBuckets.delete(this.ipKey(input.ipAddress));
  }

  private recordBucketFailure(
    buckets: Map<string, LoginRateLimitBucket>,
    key: string,
    limit: number,
    now: number,
  ) {
    const bucket = this.activeBucket(buckets.get(key), now);
    bucket.failures.push(now);

    if (bucket.failures.length >= limit) {
      bucket.blockedUntil = now + BLOCK_MS;
      bucket.failures = [];
    }

    buckets.set(key, bucket);
  }

  private decisionFor(
    bucket: LoginRateLimitBucket | undefined,
    now: number,
  ): LoginRateLimitDecision {
    if (!bucket?.blockedUntil || bucket.blockedUntil <= now) {
      return { limited: false };
    }

    return {
      limited: true,
      retryAfterSeconds: Math.ceil((bucket.blockedUntil - now) / 1000),
    };
  }

  private activeBucket(
    bucket: LoginRateLimitBucket | undefined,
    now: number,
  ): LoginRateLimitBucket {
    if (!bucket || (bucket.blockedUntil && bucket.blockedUntil <= now)) {
      return { failures: [] };
    }

    return {
      blockedUntil: bucket.blockedUntil,
      failures: bucket.failures.filter((time) => now - time <= WINDOW_MS),
    };
  }

  private prune(now: number) {
    this.pruneMap(this.usernameBuckets, now);
    this.pruneMap(this.ipBuckets, now);
  }

  private pruneMap(buckets: Map<string, LoginRateLimitBucket>, now: number) {
    for (const [key, bucket] of buckets.entries()) {
      const active = this.activeBucket(bucket, now);
      if (active.failures.length === 0 && !active.blockedUntil) {
        buckets.delete(key);
      } else {
        buckets.set(key, active);
      }
    }
  }

  private usernameKey(username: string) {
    return username.trim().toLowerCase();
  }

  private ipKey(ipAddress: string) {
    return ipAddress.trim() || 'unknown';
  }
}

