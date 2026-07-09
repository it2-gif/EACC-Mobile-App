import {
  Controller,
  Get,
  Headers,
  Param,
  UnauthorizedException,
} from '@nestjs/common';
import { AdminService } from './admin.service';

@Controller('admin')
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('users')
  listUsers(@Headers('authorization') authorization?: string) {
    return this.adminService.listUsers(this.readBearerToken(authorization));
  }

  @Get('courses/:courseId')
  getCourse(
    @Param('courseId') courseId: string,
    @Headers('authorization') authorization?: string,
  ) {
    return this.adminService.getCourse(
      courseId,
      this.readBearerToken(authorization),
    );
  }

  private readBearerToken(authorization: string | undefined): string {
    if (!authorization?.startsWith('Bearer ')) {
      throw new UnauthorizedException({
        code: 'FIREBASE_TOKEN_MISSING',
        message: 'A Firebase bearer token is required.',
      });
    }

    const token = authorization.substring('Bearer '.length).trim();
    if (!token) {
      throw new UnauthorizedException({
        code: 'FIREBASE_TOKEN_MISSING',
        message: 'A Firebase bearer token is required.',
      });
    }

    return token;
  }
}
