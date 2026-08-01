import {
  Body,
  Controller,
  Post,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from './auth.service';
import { LmsLoginDto } from './dto/lms-login.dto';
import { LoginRateLimiterService } from './login-rate-limiter.service';

interface LoginRequest {
  ip?: string;
  headers: Record<string, string | string[] | undefined>;
}

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly loginRateLimiter: LoginRateLimiterService,
  ) {}

  @Post('lms-login')
  async login(@Body() credentials: LmsLoginDto, @Req() request: LoginRequest) {
    const ipAddress = readClientIp(request);
    const rateLimitIdentity = { username: credentials.username, ipAddress };

    this.loginRateLimiter.assertCanAttempt(rateLimitIdentity);

    try {
      const session = await this.authService.login(credentials);
      this.loginRateLimiter.recordSuccess(rateLimitIdentity);
      return session;
    } catch (error) {
      if (isInvalidCredentialsError(error)) {
        this.loginRateLimiter.recordFailure(rateLimitIdentity);
      }
      throw error;
    }
  }
}

function readClientIp(request: LoginRequest): string {
  const forwardedFor = request.headers['x-forwarded-for'];
  const rawForwardedFor = Array.isArray(forwardedFor)
    ? forwardedFor[0]
    : forwardedFor;
  const firstForwardedIp = rawForwardedFor?.split(',')[0]?.trim();

  return firstForwardedIp || request.ip || 'unknown';
}

function isInvalidCredentialsError(error: unknown): boolean {
  if (!(error instanceof UnauthorizedException)) return false;

  const response = error.getResponse();
  return (
    typeof response === 'object' &&
    response !== null &&
    'code' in response &&
    response.code === 'INVALID_CREDENTIALS'
  );
}
