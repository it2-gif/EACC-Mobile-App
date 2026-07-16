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
import type { Prisma } from '../../generated/prisma/client';
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
const DEFAULT_USER_PAGE_SIZE = 10;
const MAX_USER_PAGE_SIZE = 50;

interface ListUsersOptions {
  skip?: string;
  take?: string;
  role?: string;
  query?: string;
}

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly firebaseAuth: FirebaseAuthService,
    private readonly lmsClient: EaccLmsClient,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async listUsers(firebaseIdToken: string, options: ListUsersOptions = {}) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertSuperAdmin(identity);
    const skip = this.readPositiveInteger(options.skip, 0);
    const take = Math.min(
      this.readPositiveInteger(options.take, DEFAULT_USER_PAGE_SIZE),
      MAX_USER_PAGE_SIZE,
    );
    const role = this.readUserRole(options.role);
    const query = options.query?.trim();
    const baseWhere = this.buildUserWhere({ query });
    const pageWhere = this.buildUserWhere({ query, role });

    const [users, total, admins, teachers, students] = await Promise.all([
      this.prisma.user.findMany({
        where: pageWhere,
        skip,
        take,
        orderBy: [{ role: 'asc' }, { name: 'asc' }, { lmsUserId: 'asc' }],
        select: {
          id: true,
          lmsUserId: true,
          role: true,
          name: true,
          email: true,
          status: true,
          lastLoginAt: true,
        },
      }),
      this.prisma.user.count({ where: pageWhere }),
      this.prisma.user.count({
        where: { AND: [baseWhere, { role: UserRole.ADMIN }] },
      }),
      this.prisma.user.count({
        where: { AND: [baseWhere, { role: UserRole.TEACHER }] },
      }),
      this.prisma.user.count({
        where: { AND: [baseWhere, { role: UserRole.STUDENT }] },
      }),
    ]);

    return {
      items: users.map((user) => ({
        id: user.id,
        lmsUserId: user.lmsUserId,
        role: user.role.toLowerCase(),
        name: user.name,
        email: user.email ?? null,
        status: user.status.toLowerCase(),
        lastLoginAt: user.lastLoginAt?.toISOString() ?? null,
      })),
      total,
      skip,
      take,
      hasMore: skip + users.length < total,
      counts: {
        all: admins + teachers + students,
        admins,
        teachers,
        students,
      },
    };
  }

  private buildUserWhere({
    query,
    role,
  }: {
    query?: string;
    role?: UserRole;
  }): Prisma.UserWhereInput {
    const filters: Prisma.UserWhereInput[] = [{ lmsSource: LMS_SOURCE }];
    if (role) filters.push({ role });

    const normalizedQuery = query?.trim();
    if (normalizedQuery) {
      const matchingRole = this.readUserRole(normalizedQuery);
      filters.push({
        OR: [
          { name: { contains: normalizedQuery, mode: 'insensitive' } },
          { lmsUserId: { contains: normalizedQuery, mode: 'insensitive' } },
          { email: { contains: normalizedQuery, mode: 'insensitive' } },
          ...(matchingRole ? [{ role: matchingRole }] : []),
        ],
      });
    }

    return { AND: filters };
  }

  private readUserRole(role: string | undefined): UserRole | undefined {
    switch (role?.trim().toLowerCase()) {
      case 'admin':
      case 'admins':
        return UserRole.ADMIN;
      case 'teacher':
      case 'teachers':
        return UserRole.TEACHER;
      case 'student':
      case 'students':
        return UserRole.STUDENT;
      default:
        return undefined;
    }
  }

  private readPositiveInteger(value: string | undefined, fallback: number) {
    const parsed = Number.parseInt(value ?? '', 10);
    if (!Number.isFinite(parsed) || parsed < 0) return fallback;
    return parsed;
  }

  async getCourse(lmsCourseId: string, firebaseIdToken: string) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertAdminCourseAccess(identity, lmsCourseId);

    const course = await this.prisma.course.findFirst({
      where: { lmsCourseId, status: CourseStatus.ACTIVE },
      include: {
        memberships: {
          where: {
            role: { in: [UserRole.STUDENT, UserRole.TEACHER] },
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

    const studentMemberships = course.memberships.filter(
      (membership) => membership.role === UserRole.STUDENT,
    );
    const teacherMembership = course.memberships.find(
      (membership) => membership.role === UserRole.TEACHER,
    );

    return {
      id: course.id,
      lmsCourseId: course.lmsCourseId,
      name: course.name,
      category: course.category,
      teacherName: teacherMembership?.user.name,
      keyPersonLmsUserId: course.keyPersonLmsUserId,
      keyPersonName: course.keyPersonName,
      students: studentMemberships.map((m) => ({
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

      const activeTeacherUserId = await this.syncCourseTeacher(
        tx,
        course.id,
        lmsCourse,
      );
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

      if (activeTeacherUserId) {
        await tx.courseMembership.updateMany({
          where: {
            courseId: course.id,
            role: UserRole.TEACHER,
            status: MembershipStatus.ACTIVE,
            userId: { not: activeTeacherUserId },
          },
          data: {
            status: MembershipStatus.INACTIVE,
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
        teacherName: lmsCourse.teacherName,
        keyPersonLmsUserId: course.keyPersonLmsUserId,
        keyPersonName: course.keyPersonName,
        students: students.map((student) => ({
          lmsUserId: student.lmsUserId,
          name: student.name,
        })),
      };
    });
  }

  private async syncCourseTeacher(
    tx: Prisma.TransactionClient,
    courseId: string,
    lmsCourse: NormalizedLmsCourse,
  ) {
    const lmsUserId = lmsCourse.teacherLmsUserId?.trim();
    const name = lmsCourse.teacherName?.trim();
    if (!lmsUserId || !name) return undefined;

    const user = await tx.user.upsert({
      where: {
        lmsSource_lmsUserId_role: {
          lmsSource: LMS_SOURCE,
          lmsUserId,
          role: UserRole.TEACHER,
        },
      },
      create: {
        lmsSource: LMS_SOURCE,
        lmsUserId,
        role: UserRole.TEACHER,
        name,
        status: UserStatus.ACTIVE,
      },
      update: {
        name,
        status: UserStatus.ACTIVE,
      },
    });

    await tx.courseMembership.upsert({
      where: {
        courseId_userId_role: {
          courseId,
          userId: user.id,
          role: UserRole.TEACHER,
        },
      },
      create: {
        courseId,
        userId: user.id,
        role: UserRole.TEACHER,
        status: MembershipStatus.ACTIVE,
        syncedAt: new Date(),
      },
      update: {
        status: MembershipStatus.ACTIVE,
        syncedAt: new Date(),
      },
    });

    return user.id;
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

    if (identity.isSuperAdmin === true || identity.canViewAllCourses === true) {
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

    if (identity.isSuperAdmin === true || identity.canViewAllCourses === true) {
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
