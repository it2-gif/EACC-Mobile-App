import { HttpException, HttpStatus } from '@nestjs/common';
import { LoginRateLimiterService } from './login-rate-limiter.service';

describe('LoginRateLimiterService', () => {
  let service: LoginRateLimiterService;

  beforeEach(() => {
    jest.useFakeTimers().setSystemTime(new Date('2026-07-28T12:00:00Z'));
    service = new LoginRateLimiterService();
  });

  afterEach(() => {
    jest.useRealTimers();
  });

  it('blocks a username after repeated failed attempts', () => {
    for (let i = 0; i < 5; i++) {
      service.assertCanAttempt({ username: 'Student@Example.com', ipAddress: '1.1.1.1' });
      service.recordFailure({ username: 'student@example.com', ipAddress: '1.1.1.1' });
    }

    expect(() =>
      service.assertCanAttempt({ username: 'STUDENT@example.com', ipAddress: '2.2.2.2' }),
    ).toThrow(HttpException);
  });

  it('blocks an IP after repeated failed attempts across usernames', () => {
    for (let i = 0; i < 20; i++) {
      service.recordFailure({ username: `user-${i}`, ipAddress: '3.3.3.3' });
    }

    expect(() =>
      service.assertCanAttempt({ username: 'new-user', ipAddress: '3.3.3.3' }),
    ).toThrow(HttpException);
  });

  it('returns HTTP 429 when the rate limit is reached', () => {
    for (let i = 0; i < 5; i++) {
      service.recordFailure({ username: 'student@example.com', ipAddress: '1.1.1.1' });
    }

    try {
      service.assertCanAttempt({ username: 'student@example.com', ipAddress: '1.1.1.1' });
      fail('Expected rate limit exception');
    } catch (error) {
      expect(error).toBeInstanceOf(HttpException);
      expect((error as HttpException).getStatus()).toBe(HttpStatus.TOO_MANY_REQUESTS);
    }
  });

  it('clears counters after a successful login', () => {
    for (let i = 0; i < 4; i++) {
      service.recordFailure({ username: 'student@example.com', ipAddress: '1.1.1.1' });
    }

    service.recordSuccess({ username: 'student@example.com', ipAddress: '1.1.1.1' });

    expect(() =>
      service.assertCanAttempt({ username: 'student@example.com', ipAddress: '1.1.1.1' }),
    ).not.toThrow();
  });

  it('allows attempts again after the block window expires', () => {
    for (let i = 0; i < 5; i++) {
      service.recordFailure({ username: 'student@example.com', ipAddress: '1.1.1.1' });
    }

    jest.advanceTimersByTime(15 * 60 * 1000 + 1);

    expect(() =>
      service.assertCanAttempt({ username: 'student@example.com', ipAddress: '1.1.1.1' }),
    ).not.toThrow();
  });
});

