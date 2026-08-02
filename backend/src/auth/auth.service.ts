import {
  BadGatewayException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  CourseStatus,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/enums';
import { Environment } from '../config/environment';
import { PrismaService } from '../database/prisma.service';
import { FirebaseTokenService } from '../firebase/firebase-token.service';
import type { NormalizedLmsCourse } from '../lms/contracts/lms-types';
import { EaccLmsClient } from '../lms/eacc-lms.client';
import {
  InvalidLmsCredentialsError,
  InvalidLmsResponseError,
  LmsUnavailableError,
} from '../lms/eacc-lms.errors';
import { AuthSyncService } from './auth-sync.service';
import { LmsLoginDto } from './dto/lms-login.dto';

const LMS_SOURCE = 'eacc_lms';

type AdminType =
  | 'contact_person'
  | 'operation_manager'
  | 'super_admin'
  | 'super_admin_technical_support'
  | 'academic';

@Injectable()
export class AuthService {
  constructor(
    private readonly lmsClient: EaccLmsClient,
    private readonly authSync: AuthSyncService,
    private readonly prisma: PrismaService,
    private readonly firebaseTokens: FirebaseTokenService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async login(credentials: LmsLoginDto) {
    try {
      // For admin logins, pre-fetch course IDs that are ALREADY known to belong
      // to this admin in our DB. These are passed as hints to the LMS client so
      // it can skip straight to verifying only the admin's own courses (fast path
      // on subsequent logins). On the very first login the DB returns nothing and
      // the LMS client falls back to scanning all courses from /courses.php.
      const knownCourseIds =
        credentials.role === 'admin'
          ? await this.prisma.course
              .findMany({
                where: {
                  status: CourseStatus.ACTIVE,
                  OR: [
                    { keyPersonLmsUserId: credentials.username.toLowerCase() },
                    {
                      keyPersonName: {
                        equals: credentials.username,
                        mode: 'insensitive',
                      },
                    },
                  ],
                },
                select: { lmsCourseId: true },
              })
              .then((rows) => rows.map((r) => r.lmsCourseId))
          : undefined;

      const lmsUser = await this.lmsClient.authenticate({
        ...credentials,
        ...(knownCourseIds
          ? {
              hints: { knownCourseIds },
            }
          : {}),
      });
      const synced = await this.authSync.syncLmsUser(lmsUser);
      const adminAccess = this.resolveAdminAccess(lmsUser, credentials.username);
      const adminCourses =
        lmsUser.role === 'admin' && adminAccess.canViewAllCourses
          ? await this.loadAdminCourses(
              lmsUser.lmsUserId,
              credentials.username.trim().toLowerCase(),
              lmsUser.name,
              adminAccess.canViewAllCourses,
              adminAccess.isSuperAdmin &&
                lmsUser.isCourseCatalogComplete === true,
              lmsUser.courses,
            )
          : null;
      const sessionCourses =
        adminCourses ??
        (await this.loadSessionCourses(synced.courses, lmsUser.courses));
      const courseIds =
        (adminAccess.isManagerOperation || adminAccess.isAcademic) &&
        !adminAccess.isSuperAdmin
          ? []
          : sessionCourses.map((course) => course.lmsCourseId);
      const firebaseCustomToken = await this.firebaseTokens.createCustomToken({
        appUserId: synced.user.id,
        lmsUserId: lmsUser.lmsUserId,
        displayName: synced.user.name,
        role: lmsUser.role,
        courseIds,
        ...adminAccess,
      });

      return {
        status: 'authenticated',
        user: {
          ...lmsUser,
          ...adminAccess,
        },
        appUser: {
          id: synced.user.id,
          role: synced.user.role.toLowerCase(),
          name: synced.user.name,
          email: synced.user.email,
          ...adminAccess,
        },
        courses: sessionCourses,
        firebase: { customToken: firebaseCustomToken },
        nextStep: 'ready',
      };
    } catch (error) {
      if (error instanceof InvalidLmsCredentialsError) {
        throw new UnauthorizedException({
          code: 'INVALID_CREDENTIALS',
          message: 'The username or password is incorrect.',
        });
      }

      if (error instanceof InvalidLmsResponseError) {
        const isDevelopment =
          this.config.get('NODE_ENV', { infer: true }) !== 'production';

        throw new BadGatewayException({
          code: 'LMS_RESPONSE_INVALID',
          message: 'The LMS returned an unsupported response.',
          ...(isDevelopment ? { detail: error.message } : {}),
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
  }

  private resolveAdminAccess(
    lmsUser: {
      role: string;
      isSuperAdmin?: boolean;
      isManagerOperation?: boolean;
      isTechnicalSupport?: boolean;
      isAcademic?: boolean;
    },
    loginUsername: string,
  ) {
    if (lmsUser.role !== 'admin') {
      return {
        adminType: null,
        isContactPerson: false,
        isSuperAdmin: false,
        isManagerOperation: false,
        isTechnicalSupport: false,
        isAcademic: false,
        canViewAllCourses: false,
      };
    }

    const isSuperAdmin = lmsUser.isSuperAdmin === true;
    const isTechnicalSupport =
      isSuperAdmin && lmsUser.isTechnicalSupport === true;
    const normalizedLoginUsername = loginUsername.trim().toLowerCase();
    const isAcademic =
      !isSuperAdmin &&
      (lmsUser.isAcademic === true ||
        normalizedLoginUsername === 'niven' ||
        normalizedLoginUsername === 'neven');
    const isManagerOperation =
      !isSuperAdmin && lmsUser.isManagerOperation === true;
    const canViewAllCourses = isSuperAdmin || isManagerOperation || isAcademic;
    const isContactPerson =
      !isSuperAdmin &&
      !isManagerOperation &&
      !isTechnicalSupport &&
      !isAcademic;
    const adminType: AdminType = isAcademic
      ? 'academic'
      : isSuperAdmin && isTechnicalSupport
        ? 'super_admin_technical_support'
        : isSuperAdmin
          ? 'super_admin'
          : isManagerOperation
            ? 'operation_manager'
            : 'contact_person';

    return {
      adminType,
      isContactPerson,
      isSuperAdmin,
      isManagerOperation,
      isTechnicalSupport,
      isAcademic,
      canViewAllCourses,
    };
  }

  private async loadAdminCourses(
    adminLmsUserId: string,
    loginUsername: string,
    adminName: string,
    canViewAllCourses: boolean,
    syncGlobalCourseSet: boolean,
    lmsCourses: NormalizedLmsCourse[] = [],
  ) {
    if (syncGlobalCourseSet) {
      await this.archiveCoursesMissingFromLms(lmsCourses);
    }

    const courseWhere = canViewAllCourses
      ? { status: CourseStatus.ACTIVE }
      : {
          status: CourseStatus.ACTIVE,
          OR: [
            // Direct match on the extracted LMS user ID
            { keyPersonLmsUserId: adminLmsUserId },
            // Also try the raw login username (covers cases where ID extraction
            // fell back to username, or the LMS stores usernames as keyperson values)
            ...(loginUsername !== adminLmsUserId
              ? [{ keyPersonLmsUserId: loginUsername }]
              : []),
            // Name-based fallback (covers cases where keyperson ID is numeric but
            // the admin name matches the keyperson name stored on the course)
            ...(adminName
              ? [
                  {
                    keyPersonName: {
                      equals: adminName,
                      mode: 'insensitive' as const,
                    },
                  },
                ]
              : []),
          ],
        };

    const courses = await this.prisma.course.findMany({
      where: courseWhere,
      orderBy: [{ name: 'asc' }],
      include: {
        memberships: {
          where: {
            role: { in: [UserRole.STUDENT, UserRole.TEACHER] },
            status: MembershipStatus.ACTIVE,
            user: { status: UserStatus.ACTIVE },
          },
          include: {
            user: {
              select: {
                lmsUserId: true,
                name: true,
              },
            },
          },
        },
      },
    });

    const lmsCourseById = new Map(
      lmsCourses.map((course) => [course.lmsCourseId, course]),
    );

    return courses.map((course) => {
      const lmsCourse = lmsCourseById.get(course.lmsCourseId);
      const lmsStudents =
        lmsCourse?.students?.map((student) => ({
          lmsUserId: student.lmsUserId,
          name: student.name,
        })) ?? [];
      const teacherMembership = course.memberships.find(
        (membership) => membership.role === UserRole.TEACHER,
      );
      const storedStudents = course.memberships
        .filter((membership) => membership.role === UserRole.STUDENT)
        .map((membership) => ({
          lmsUserId: membership.user.lmsUserId,
          name: membership.user.name,
        }));

      return {
        id: course.id,
        lmsCourseId: course.lmsCourseId,
        name: course.name,
        category: course.category,
        teacherName: lmsCourse?.teacherName ?? teacherMembership?.user.name,
        keyPersonLmsUserId: course.keyPersonLmsUserId,
        keyPersonName: course.keyPersonName,
        students: lmsStudents.length > 0 ? lmsStudents : storedStudents,
      };
    });
  }

  private async archiveCoursesMissingFromLms(
    lmsCourses: NormalizedLmsCourse[],
  ) {
    const activeLmsCourseIds = lmsCourses
      .map((course) => course.lmsCourseId.trim())
      .filter(Boolean);

    if (activeLmsCourseIds.length === 0) return;

    await this.prisma.course.updateMany({
      where: {
        lmsSource: LMS_SOURCE,
        status: CourseStatus.ACTIVE,
        lmsCourseId: { notIn: [...new Set(activeLmsCourseIds)] },
      },
      data: {
        status: CourseStatus.ARCHIVED,
      },
    });
  }
  private async loadSessionCourses(
    syncedCourses: Array<{
      id: string;
      lmsCourseId: string;
      name: string;
      category: string | null;
      keyPersonLmsUserId: string | null;
      keyPersonName: string | null;
    }>,
    lmsCourses: NormalizedLmsCourse[] = [],
  ) {
    if (syncedCourses.length === 0) return [];

    const coursesWithMemberships = await this.prisma.course.findMany({
      where: {
        id: { in: syncedCourses.map((course) => course.id) },
        status: CourseStatus.ACTIVE,
      },
      include: {
        memberships: {
          where: {
            role: { in: [UserRole.STUDENT, UserRole.TEACHER] },
            status: MembershipStatus.ACTIVE,
            user: { status: UserStatus.ACTIVE },
          },
          include: {
            user: {
              select: {
                lmsUserId: true,
                name: true,
              },
            },
          },
        },
      },
    });

    const storedCourseById = new Map(
      coursesWithMemberships.map((course) => [course.id, course]),
    );
    const lmsCourseById = new Map(
      lmsCourses.map((course) => [course.lmsCourseId, course]),
    );

    return syncedCourses.map((course) => {
      const storedCourse = storedCourseById.get(course.id);
      const memberships = storedCourse?.memberships ?? [];
      const lmsCourse = lmsCourseById.get(course.lmsCourseId);
      const lmsStudents =
        lmsCourse?.students?.map((student) => ({
          lmsUserId: student.lmsUserId,
          name: student.name,
        })) ?? [];
      const storedStudents = memberships
        .filter((membership) => membership.role === UserRole.STUDENT)
        .map((membership) => ({
          lmsUserId: membership.user.lmsUserId,
          name: membership.user.name,
        }));
      const teacherMembership = memberships.find(
        (membership) => membership.role === UserRole.TEACHER,
      );

      return {
        id: course.id,
        lmsCourseId: course.lmsCourseId,
        name: course.name,
        category: course.category,
        teacherName: lmsCourse?.teacherName ?? teacherMembership?.user.name,
        keyPersonLmsUserId: course.keyPersonLmsUserId,
        keyPersonName: course.keyPersonName,
        students: lmsStudents.length > 0 ? lmsStudents : storedStudents,
      };
    });
  }
}
