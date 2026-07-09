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

const SUPER_ADMIN_USERNAME = 'esam';
const SUPER_ADMIN_PASSWORD = '123#@!0';
const MANAGER_OPERATION_CREDENTIALS = [
  { username: 'youssef', password: 'youssef@2023' },
  { username: 'eman.library', password: 'E123456' },
] as const;

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
      const hasSuperAdminCredentials =
        credentials.role === 'admin' &&
        this.matchesHardcodedSuperAdmin(credentials);
      const hasManagerOperationCredentials =
        credentials.role === 'admin' &&
        this.matchesHardcodedManagerOperation(credentials);
      const canViewAllCourses =
        hasSuperAdminCredentials || hasManagerOperationCredentials;

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
        ...(knownCourseIds || canViewAllCourses
          ? {
              hints: {
                ...(knownCourseIds ? { knownCourseIds } : {}),
                hasFullAccess: hasSuperAdminCredentials,
                canViewAllCourses,
              },
            }
          : {}),
      });
      const synced = await this.authSync.syncLmsUser(lmsUser);
      const isSuperAdmin =
        lmsUser.role === 'admin' && hasSuperAdminCredentials;
      const isManagerOperation =
        lmsUser.role === 'admin' && hasManagerOperationCredentials;
      const adminCourses =
        lmsUser.role === 'admin' && canViewAllCourses
          ? await this.loadAdminCourses(
              lmsUser.lmsUserId,
              credentials.username.trim().toLowerCase(),
              lmsUser.name,
              canViewAllCourses,
              lmsUser.courses,
            )
          : null;
      const sessionCourses =
        adminCourses ??
        synced.courses.map((course) => ({
          id: course.id,
          lmsCourseId: course.lmsCourseId,
          name: course.name,
          category: course.category,
          keyPersonLmsUserId: course.keyPersonLmsUserId,
          keyPersonName: course.keyPersonName,
          students:
            lmsUser.courses.find(
              (lmsCourse) => lmsCourse.lmsCourseId === course.lmsCourseId,
            )?.students ?? [],
        }));
      const courseIds =
        isManagerOperation && !isSuperAdmin
          ? []
          : sessionCourses.map((course) => course.lmsCourseId);
      const firebaseCustomToken = await this.firebaseTokens.createCustomToken({
        appUserId: synced.user.id,
        lmsUserId: lmsUser.lmsUserId,
        displayName: synced.user.name,
        role: lmsUser.role,
        courseIds,
        isSuperAdmin,
        canViewAllCourses,
      });

      return {
        status: 'authenticated',
        user: {
          ...lmsUser,
          isSuperAdmin,
          isManagerOperation,
          canViewAllCourses,
        },
        appUser: {
          id: synced.user.id,
          role: synced.user.role.toLowerCase(),
          name: synced.user.name,
          email: synced.user.email,
          isSuperAdmin,
          isManagerOperation,
          canViewAllCourses,
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

  private matchesHardcodedSuperAdmin(credentials: LmsLoginDto): boolean {
    return (
      credentials.username.trim().toLowerCase() === SUPER_ADMIN_USERNAME &&
      credentials.password === SUPER_ADMIN_PASSWORD
    );
  }

  private matchesHardcodedManagerOperation(credentials: LmsLoginDto): boolean {
    const username = credentials.username.trim().toLowerCase();
    return MANAGER_OPERATION_CREDENTIALS.some(
      (manager) =>
        manager.username === username &&
        manager.password === credentials.password,
    );
  }

  private async loadAdminCourses(
    adminLmsUserId: string,
    loginUsername: string,
    adminName: string,
    canViewAllCourses: boolean,
    lmsCourses: NormalizedLmsCourse[] = [],
  ) {
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
            role: UserRole.STUDENT,
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

    const lmsStudentsByCourseId = new Map(
      lmsCourses.map((course) => [
        course.lmsCourseId,
        (course.students ?? []).map((student) => ({
          lmsUserId: student.lmsUserId,
          name: student.name,
        })),
      ]),
    );

    return courses.map((course) => {
      const lmsStudents = lmsStudentsByCourseId.get(course.lmsCourseId) ?? [];
      const storedStudents = course.memberships.map((membership) => ({
        lmsUserId: membership.user.lmsUserId,
        name: membership.user.name,
      }));

      return {
        id: course.id,
        lmsCourseId: course.lmsCourseId,
        name: course.name,
        category: course.category,
        keyPersonLmsUserId: course.keyPersonLmsUserId,
        keyPersonName: course.keyPersonName,
        students: lmsStudents.length > 0 ? lmsStudents : storedStudents,
      };
    });
  }
}
