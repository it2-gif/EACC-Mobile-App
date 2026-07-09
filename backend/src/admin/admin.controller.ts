import {
  Controller,
  Get,
  Headers,
  Param,
  Post,
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

  @Post('courses/:courseId/refresh')
  refreshCourse(
    @Param('courseId') courseId: string,
    @Headers('authorization') authorization?: string,
  ) {
    return this.adminService.refreshCourse(
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
