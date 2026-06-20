import { Injectable } from '@nestjs/common';
import {
  CourseStatus,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/enums';
import { PrismaService } from '../database/prisma.service';
import {
  LmsUserRole,
  NormalizedLmsCourse,
  NormalizedLmsUser,
} from '../lms/contracts/lms-types';

const LMS_SOURCE = 'eacc_lms';

@Injectable()
export class AuthSyncService {
  constructor(private readonly prisma: PrismaService) {}

  async syncLmsUser(lmsUser: NormalizedLmsUser) {
    const role = toPrismaRole(lmsUser.role);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.upsert({
        where: {
          lmsSource_lmsUserId_role: {
            lmsSource: LMS_SOURCE,
            lmsUserId: lmsUser.lmsUserId,
            role,
          },
        },
        create: {
          lmsSource: LMS_SOURCE,
          lmsUserId: lmsUser.lmsUserId,
          role,
          name: lmsUser.name,
          email: lmsUser.email,
          status: UserStatus.ACTIVE,
          lastLoginAt: new Date(),
        },
        update: {
          name: lmsUser.name,
          email: lmsUser.email,
          status: UserStatus.ACTIVE,
          lastLoginAt: new Date(),
        },
      });

      const courses = await Promise.all(
        lmsUser.courses.map((course) =>
          this.syncCourseMembership(tx, user.id, role, course),
        ),
      );

      return {
        user,
        courses,
      };
    });
  }

  private async syncCourseMembership(
    tx: PrismaTransaction,
    userId: string,
    role: UserRole,
    lmsCourse: NormalizedLmsCourse,
  ) {
    const course = await tx.course.upsert({
      where: {
        lmsSource_lmsCourseId: {
          lmsSource: LMS_SOURCE,
          lmsCourseId: lmsCourse.lmsCourseId,
        },
      },
      create: {
        lmsSource: LMS_SOURCE,
        lmsCourseId: lmsCourse.lmsCourseId,
        name: lmsCourse.name,
        category: lmsCourse.category,
        status: CourseStatus.ACTIVE,
      },
      update: {
        name: lmsCourse.name,
        category: lmsCourse.category,
        status: CourseStatus.ACTIVE,
      },
    });

    await tx.courseMembership.upsert({
      where: {
        courseId_userId_role: {
          courseId: course.id,
          userId,
          role,
        },
      },
      create: {
        courseId: course.id,
        userId,
        role,
        status: MembershipStatus.ACTIVE,
        syncedAt: new Date(),
      },
      update: {
        status: MembershipStatus.ACTIVE,
        syncedAt: new Date(),
      },
    });

    return course;
  }
}

type PrismaTransaction = Parameters<
  Parameters<PrismaService['$transaction']>[0]
>[0];

function toPrismaRole(role: LmsUserRole): UserRole {
  const roles: Record<LmsUserRole, UserRole> = {
    student: UserRole.STUDENT,
    teacher: UserRole.TEACHER,
    admin: UserRole.ADMIN,
  };

  return roles[role];
}
