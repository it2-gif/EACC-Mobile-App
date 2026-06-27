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
      const lmsUser = await this.lmsClient.authenticate(credentials);
      const synced = await this.authSync.syncLmsUser(lmsUser);
      const courseIds = synced.courses.map((course) => course.lmsCourseId);
      const adminCourses =
        lmsUser.role === 'admin' ? await this.loadAdminCourses() : null;
      const firebaseCustomToken = await this.firebaseTokens.createCustomToken({
        appUserId: synced.user.id,
        lmsUserId: lmsUser.lmsUserId,
        displayName: synced.user.name,
        role: lmsUser.role,
        courseIds,
      });

      return {
        status: 'authenticated',
        user: lmsUser,
        appUser: {
          id: synced.user.id,
          role: synced.user.role.toLowerCase(),
          name: synced.user.name,
          email: synced.user.email,
        },
        courses:
          adminCourses ??
          synced.courses.map((course) => ({
            id: course.id,
            lmsCourseId: course.lmsCourseId,
            name: course.name,
            category: course.category,
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

  private async loadAdminCourses() {
    const courses = await this.prisma.course.findMany({
      where: { status: CourseStatus.ACTIVE },
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
      students: course.memberships.map((membership) => ({
        lmsUserId: membership.user.lmsUserId,
        name: membership.user.name,
      })),
    }));
  }
}
