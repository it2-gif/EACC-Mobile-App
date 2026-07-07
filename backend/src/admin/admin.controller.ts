import { Controller, Get, Param } from '@nestjs/common';
import { AdminService } from './admin.service';

@Controller('admin')
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('users')
  listUsers() {
    return this.adminService.listUsers();
  }

  @Get('courses/:courseId')
  getCourse(@Param('courseId') courseId: string) {
    return this.adminService.getCourse(courseId);
  }
}
