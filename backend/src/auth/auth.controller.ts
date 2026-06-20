import { Body, Controller, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LmsLoginDto } from './dto/lms-login.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('lms-login')
  login(@Body() credentials: LmsLoginDto) {
    return this.authService.login(credentials);
  }
}
