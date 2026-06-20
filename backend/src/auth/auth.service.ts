import {
  BadGatewayException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Environment } from '../config/environment';
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
    private readonly firebaseTokens: FirebaseTokenService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async login(credentials: LmsLoginDto) {
    try {
      const lmsUser = await this.lmsClient.authenticate(credentials);
      const synced = await this.authSync.syncLmsUser(lmsUser);
      const courseIds = synced.courses.map((course) => course.lmsCourseId);
      const firebaseCustomToken =
        lmsUser.role === 'student' || lmsUser.role === 'teacher'
          ? await this.firebaseTokens.createCustomToken({
              appUserId: synced.user.id,
              lmsUserId: lmsUser.lmsUserId,
              displayName: synced.user.name,
              role: lmsUser.role,
              courseIds,
            })
          : undefined;

      return {
        status: 'authenticated',
        user: lmsUser,
        appUser: {
          id: synced.user.id,
          role: synced.user.role.toLowerCase(),
          name: synced.user.name,
          email: synced.user.email,
        },
        courses: synced.courses.map((course) => ({
          id: course.id,
          lmsCourseId: course.lmsCourseId,
          name: course.name,
          category: course.category,
          students:
            lmsUser.courses.find(
              (lmsCourse) => lmsCourse.lmsCourseId === course.lmsCourseId,
            )?.students ?? [],
        })),
        firebase: firebaseCustomToken
          ? {
              customToken: firebaseCustomToken,
            }
          : undefined,
        nextStep: firebaseCustomToken ? 'ready' : 'admin_auth_pending',
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
}
