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
import { EaccLmsClient } from '../lms/eacc-lms.client';
import {
  InvalidLmsCredentialsError,
  InvalidLmsResponseError,
  LmsUnavailableError,
} from '../lms/eacc-lms.errors';
import { AuthSyncService } from './auth-sync.service';
import { LmsLoginDto } from './dto/lms-login.dto';

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
        ...(knownCourseIds ? { hints: { knownCourseIds } } : {}),
      });
      const synced = await this.authSync.syncLmsUser(lmsUser);
      const isSuperAdmin =
        lmsUser.role === 'admin' && lmsUser.isSuperAdmin === true;
      const adminCourses =
        lmsUser.role === 'admin' && isSuperAdmin
          ? await this.loadAdminCourses(
              lmsUser.lmsUserId,
              credentials.username.trim().toLowerCase(),
              lmsUser.name,
              isSuperAdmin,
            )
          : null;
      const courseIds = synced.courses.map((course) => course.lmsCourseId);
      const firebaseCustomToken = await this.firebaseTokens.createCustomToken({
        appUserId: synced.user.id,
        lmsUserId: lmsUser.lmsUserId,
        displayName: synced.user.name,
        role: lmsUser.role,
        courseIds,
        isSuperAdmin,
      });

      return {
        status: 'authenticated',
        user: { ...lmsUser, isSuperAdmin },
        appUser: {
          id: synced.user.id,
          role: synced.user.role.toLowerCase(),
          name: synced.user.name,
          email: synced.user.email,
          isSuperAdmin,
        },
        courses:
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
          })),
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

  private async loadAdminCourses(
    adminLmsUserId: string,
    loginUsername: string,
    adminName: string,
    isSuperAdmin: boolean,
  ) {
    const courseWhere = isSuperAdmin
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

    return courses.map((course) => ({
      id: course.id,
      lmsCourseId: course.lmsCourseId,
      name: course.name,
      category: course.category,
      keyPersonLmsUserId: course.keyPersonLmsUserId,
      keyPersonName: course.keyPersonName,
      students: course.memberships.map((membership) => ({
        lmsUserId: membership.user.lmsUserId,
        name: membership.user.name,
      })),
    }));
  }
}
