import {
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  App,
  cert,
  getApp,
  getApps,
  initializeApp,
  ServiceAccount,
} from 'firebase-admin/app';
import { DecodedIdToken, getAuth } from 'firebase-admin/auth';
import { getMessaging, Messaging } from 'firebase-admin/messaging';
import { Environment } from '../config/environment';

export interface FirebaseIdentity {
  appUserId: string;
  lmsUserId: string;
  displayName: string;
  role: 'student' | 'teacher';
  courseIds: string[];
}

@Injectable()
export class FirebaseAuthService {
  private app?: App;

  constructor(private readonly config: ConfigService<Environment, true>) {}

  async createCustomToken(identity: FirebaseIdentity): Promise<string> {
    const uid = `${identity.role}:${identity.lmsUserId}`;

    return getAuth(this.getFirebaseApp()).createCustomToken(uid, {
      appUserId: identity.appUserId,
      lmsUserId: identity.lmsUserId,
      displayName: identity.displayName,
      role: identity.role,
      courseIds: [...new Set(identity.courseIds)],
    });
  }

  async verifyIdToken(idToken: string): Promise<DecodedIdToken> {
    try {
      return await getAuth(this.getFirebaseApp()).verifyIdToken(idToken);
    } catch {
      throw new UnauthorizedException({
        code: 'INVALID_FIREBASE_TOKEN',
        message: 'The Firebase session is invalid or expired.',
      });
    }
  }

  messaging(): Messaging {
    return getMessaging(this.getFirebaseApp());
  }

  private getFirebaseApp(): App {
    if (this.app) return this.app;

    if (getApps().length > 0) {
      this.app = getApp();
      return this.app;
    }

    const projectId = this.config.get('FIREBASE_PROJECT_ID', { infer: true });
    const clientEmail = this.config.get('FIREBASE_CLIENT_EMAIL', {
      infer: true,
    });
    const privateKey = this.config.get('FIREBASE_PRIVATE_KEY', { infer: true });

    if (!projectId || !clientEmail || !privateKey) {
      throw new ServiceUnavailableException({
        code: 'FIREBASE_AUTH_NOT_CONFIGURED',
        message:
          'Firebase authentication is not configured on the EACC backend.',
      });
    }

    const serviceAccount: ServiceAccount = {
      projectId,
      clientEmail,
      privateKey,
    };

    this.app = initializeApp({
      credential: cert(serviceAccount),
      projectId,
    });

    return this.app;
  }
}
