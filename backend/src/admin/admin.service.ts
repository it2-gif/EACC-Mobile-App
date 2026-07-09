import {
  BadGatewayException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { DecodedIdToken } from 'firebase-admin/auth';
import {
  CourseStatus,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/enums';
import { Environment } from '../config/environment';
import { PrismaService } from '../database/prisma.service';
import { FirebaseAuthService } from '../firebase/firebase-auth.service';
import type { NormalizedLmsCourse } from '../lms/contracts/lms-types';
import { EaccLmsClient } from '../lms/eacc-lms.client';
import {
  InvalidLmsCredentialsError,
  LmsUnavailableError,
} from '../lms/eacc-lms.errors';

const LMS_SOURCE = 'eacc_lms';

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly firebaseAuth: FirebaseAuthService,
    private readonly lmsClient: EaccLmsClient,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async listUsers(firebaseIdToken: string) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertSuperAdmin(identity);

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

  async getCourse(lmsCourseId: string, firebaseIdToken: string) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertAdminCourseAccess(identity, lmsCourseId);

    const course = await this.prisma.course.findFirst({
      where: { lmsCourseId, status: CourseStatus.ACTIVE },
      include: {
        memberships: {
          where: {
            role: UserRole.STUDENT,
            status: MembershipStatus.ACTIVE,
            user: { status: UserStatus.ACTIVE },
          },
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

  async refreshCourse(lmsCourseId: string, firebaseIdToken: string) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertCanRefreshLmsCourse(identity);

    const courseId = lmsCourseId.trim();
    if (!courseId) {
      throw new NotFoundException('Course not found');
    }

    const credentials = this.readLmsSyncCredentials();
    let lmsCourse: NormalizedLmsCourse | undefined;

    try {
      lmsCourse = await this.lmsClient.loadAdminCourseById(
        credentials,
        courseId,
      );
    } catch (error) {
      if (error instanceof InvalidLmsCredentialsError) {
        throw new ServiceUnavailableException({
          code: 'LMS_SYNC_CREDENTIALS_INVALID',
          message: 'The LMS sync admin credentials are not valid.',
        });
      }

      if (error instanceof LmsUnavailableError) {
        throw new BadGatewayException({
          code: 'LMS_UNAVAILABLE',
          message: 'The LMS is currently unavailable.',
        });
      }

      throw error;
    }

    if (!lmsCourse) {
      throw new NotFoundException({
        code: 'LMS_COURSE_NOT_FOUND',
        message: `Course ${courseId} was not found in the LMS.`,
      });
    }

    return this.syncAndSerializeCourse(lmsCourse);
  }

  private async syncAndSerializeCourse(lmsCourse: NormalizedLmsCourse) {
    const shouldSyncRoster = lmsCourse.students !== undefined;
    const students = (lmsCourse.students ?? [])
      .map((student) => ({
        lmsUserId: student.lmsUserId.trim(),
        name: student.name.trim(),
      }))
      .filter((student) => student.lmsUserId && student.name);

    return this.prisma.$transaction(async (tx) => {
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
          keyPersonLmsUserId: lmsCourse.keyPersonLmsUserId,
          keyPersonName: lmsCourse.keyPersonName,
          status: CourseStatus.ACTIVE,
        },
        update: {
          name: lmsCourse.name,
          category: lmsCourse.category,
          keyPersonLmsUserId: lmsCourse.keyPersonLmsUserId,
          keyPersonName: lmsCourse.keyPersonName,
          status: CourseStatus.ACTIVE,
        },
      });

      const activeStudentUserIds: string[] = [];

      for (const student of students) {
        const user = await tx.user.upsert({
          where: {
            lmsSource_lmsUserId_role: {
              lmsSource: LMS_SOURCE,
              lmsUserId: student.lmsUserId,
              role: UserRole.STUDENT,
            },
          },
          create: {
            lmsSource: LMS_SOURCE,
            lmsUserId: student.lmsUserId,
            role: UserRole.STUDENT,
            name: student.name,
            status: UserStatus.ACTIVE,
          },
          update: {
            name: student.name,
            status: UserStatus.ACTIVE,
          },
        });

        activeStudentUserIds.push(user.id);

        await tx.courseMembership.upsert({
          where: {
            courseId_userId_role: {
              courseId: course.id,
              userId: user.id,
              role: UserRole.STUDENT,
            },
          },
          create: {
            courseId: course.id,
            userId: user.id,
            role: UserRole.STUDENT,
            status: MembershipStatus.ACTIVE,
            syncedAt: new Date(),
          },
          update: {
            status: MembershipStatus.ACTIVE,
            syncedAt: new Date(),
          },
        });
      }

      if (shouldSyncRoster) {
        await tx.courseMembership.updateMany({
          where: {
            courseId: course.id,
            role: UserRole.STUDENT,
            status: MembershipStatus.ACTIVE,
            ...(activeStudentUserIds.length > 0
              ? { userId: { notIn: activeStudentUserIds } }
              : {}),
          },
          data: {
            status: MembershipStatus.INACTIVE,
            syncedAt: new Date(),
          },
        });
      }

      return {
        id: course.id,
        lmsCourseId: course.lmsCourseId,
        name: course.name,
        category: course.category,
        keyPersonLmsUserId: course.keyPersonLmsUserId,
        keyPersonName: course.keyPersonName,
        students: students.map((student) => ({
          lmsUserId: student.lmsUserId,
          name: student.name,
        })),
      };
    });
  }

  private assertAdminCourseAccess(
    identity: DecodedIdToken,
    lmsCourseId: string,
  ) {
    if (identity.role !== 'admin') {
      throw new UnauthorizedException({
        code: 'ADMIN_ROLE_REQUIRED',
        message: 'Only admin accounts can load admin course details.',
      });
    }

    if (
      identity.isSuperAdmin === true ||
      identity.canViewAllCourses === true
    ) {
      return;
    }

    const courseIds = this.readCourseIds(identity);
    if (!courseIds.includes(lmsCourseId)) {
      throw new ForbiddenException({
        code: 'COURSE_ACCESS_DENIED',
        message: 'This admin account cannot access that course.',
      });
    }
  }

  private assertSuperAdmin(identity: DecodedIdToken) {
    if (identity.role !== 'admin' || identity.isSuperAdmin !== true) {
      throw new ForbiddenException({
        code: 'SUPER_ADMIN_REQUIRED',
        message: 'Only super admin accounts can access this admin resource.',
      });
    }
  }

  private assertCanRefreshLmsCourse(identity: DecodedIdToken) {
    if (identity.role !== 'admin') {
      throw new UnauthorizedException({
        code: 'ADMIN_ROLE_REQUIRED',
        message: 'Only admin accounts can refresh LMS course details.',
      });
    }

    if (
      identity.isSuperAdmin === true ||
      identity.canViewAllCourses === true
    ) {
      return;
    }

    throw new ForbiddenException({
      code: 'COURSE_REFRESH_DENIED',
      message: 'This admin account cannot refresh LMS course details.',
    });
  }

  private readLmsSyncCredentials(): {
    username: string;
    password: string;
  } {
    const username = this.config.get('LMS_SYNC_ADMIN_USERNAME', {
      infer: true,
    });
    const password = this.config.get('LMS_SYNC_ADMIN_PASSWORD', {
      infer: true,
    });

    if (!username || !password) {
      throw new ServiceUnavailableException({
        code: 'LMS_SYNC_CREDENTIALS_MISSING',
        message:
          'LMS sync admin credentials are not configured on the backend.',
      });
    }

    return { username, password };
  }

  private readCourseIds(identity: DecodedIdToken): string[] {
    if (!Array.isArray(identity.courseIds)) return [];

    return identity.courseIds
      .filter((value): value is string => typeof value === 'string')
      .map((value) => value.trim())
      .filter(Boolean);
  }
}
