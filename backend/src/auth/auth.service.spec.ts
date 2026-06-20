import { ConfigService } from '@nestjs/config';

jest.mock('../firebase/firebase-token.service', () => ({
  FirebaseTokenService: class FirebaseTokenService {},
}));
jest.mock('../lms/eacc-lms.client', () => ({
  EaccLmsClient: class EaccLmsClient {},
}));
jest.mock('./auth-sync.service', () => ({
  AuthSyncService: class AuthSyncService {},
}));

import { AuthService } from './auth.service';

describe('AuthService', () => {
  it('returns a Firebase custom token with compact LMS authorization claims', async () => {
    const lmsUser = {
      lmsUserId: '3937',
      role: 'student' as const,
      name: 'Esam Test',
      email: 'student@example.com',
      courses: [
        {
          lmsCourseId: '2191',
          name: 'Elementary Level - 3',
          category: 'English',
        },
      ],
    };
    const synced = {
      user: {
        id: '08e5943c-21b4-4bd2-9bae-89b9ba4b1798',
        role: 'STUDENT',
        name: 'Esam Test',
        email: 'student@example.com',
      },
      courses: [
        {
          id: 'course-uuid',
          lmsCourseId: '2191',
          name: 'Elementary Level - 3',
          category: 'English',
        },
      ],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const firebaseTokens = {
      createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
    };
    const config = {
      get: jest.fn().mockReturnValue('test'),
    } as unknown as ConfigService;
    const service = new AuthService(
      lmsClient as never,
      authSync as never,
      firebaseTokens as never,
      config as never,
    );

    const result = await service.login({
      role: 'student',
      username: 'student@example.com',
      password: 'password',
    });

    expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith({
      appUserId: synced.user.id,
      lmsUserId: '3937',
      displayName: 'Esam Test',
      role: 'student',
      courseIds: ['2191'],
    });
    expect(result.firebase).toEqual({ customToken: 'firebase-token' });
    expect(result.nextStep).toBe('ready');
  });
});
