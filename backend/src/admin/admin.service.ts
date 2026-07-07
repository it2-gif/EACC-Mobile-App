import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../database/prisma.service';
import { UserRole } from '../../generated/prisma/enums';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async listUsers() {
    const users = await this.prisma.user.findMany({
      orderBy: [{ role: 'asc' }, { name: 'asc' }],
      select: {
        id: true,
        lmsUserId: true,
        role: true,
        name: true,
        email: true,
        status: true,
        lastLoginAt: true,
      },
    });

    return users.map((user) => ({
      id: user.id,
      lmsUserId: user.lmsUserId,
      role: user.role.toLowerCase(),
      name: user.name,
      email: user.email ?? null,
      status: user.status.toLowerCase(),
      lastLoginAt: user.lastLoginAt?.toISOString() ?? null,
    }));
  }

  async getCourse(lmsCourseId: string) {
    const course = await this.prisma.course.findFirst({
      where: { lmsCourseId },
      include: {
        memberships: {
          where: { role: UserRole.STUDENT },
          include: {
            user: true,
          },
        },
      },
    });

    if (!course) {
      throw new NotFoundException(`Course ${lmsCourseId} not found`);
    }

    return {
      id: course.id,
      lmsCourseId: course.lmsCourseId,
      name: course.name,
      category: course.category,
      keyPersonLmsUserId: course.keyPersonLmsUserId,
      keyPersonName: course.keyPersonName,
      students: course.memberships.map((m) => ({
        lmsUserId: m.user.lmsUserId,
        name: m.user.name,
      })),
    };
  }
}
