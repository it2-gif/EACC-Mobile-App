import { ConfigService } from '@nestjs/config';

jest.mock('../firebase/firebase-token.service', () => ({
  FirebaseTokenService: class FirebaseTokenService {},
}));
jest.mock('../database/prisma.service', () => ({
  PrismaService: class PrismaService {},
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
    const prisma = {};
    const firebaseTokens = {
      createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
    };
    const config = {
      get: jest.fn().mockReturnValue('test'),
    } as unknown as ConfigService;
    const service = new AuthService(
      lmsClient as never,
      authSync as never,
      prisma as never,
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
      isSuperAdmin: false,
      canViewAllCourses: false,
      isTechnicalSupport: false,
    });
    expect(result.firebase).toEqual({ customToken: 'firebase-token' });
    expect(result.nextStep).toBe('ready');
  });

  it('keeps other admin credentials scoped as contact-person access', async () => {
    const lmsUser = {
      lmsUserId: '92',
      role: 'admin' as const,
      name: 'Developer',
      isSuperAdmin: false,
      courses: [],
    };
    const synced = {
      user: {
        id: 'admin-uuid',
        role: 'ADMIN',
        name: 'Developer',
        email: null,
      },
      courses: [],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const prisma = {
      course: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const firebaseTokens = {
      createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
    };
    const config = {
      get: jest.fn().mockReturnValue('test'),
    } as unknown as ConfigService;
    const service = new AuthService(
      lmsClient as never,
      authSync as never,
      prisma as never,
      firebaseTokens as never,
      config as never,
    );

    const result = await service.login({
      role: 'admin',
      username: 'legacy-admin',
      password: 'legacy-password',
    });

    expect(result.appUser.isSuperAdmin).toBe(false);
    expect(result.appUser.isManagerOperation).toBe(false);
    expect(result.appUser.canViewAllCourses).toBe(false);
    expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith(
      expect.objectContaining({
        isSuperAdmin: false,
        canViewAllCourses: false,
      }),
    );
  });

  it('returns contact-person linked-course students from the LMS roster', async () => {
    const lmsUser = {
      lmsUserId: '92',
      role: 'admin' as const,
      name: 'Developer',
      isSuperAdmin: false,
      courses: [
        {
          lmsCourseId: '2290',
          name: 'Elementary Level - 3 - General English',
          category: 'English Adult',
          students: [{ lmsUserId: '8660', name: 'Linked Student' }],
        },
      ],
    };
    const synced = {
      user: {
        id: 'admin-uuid',
        role: 'ADMIN',
        name: 'Developer',
        email: null,
      },
      courses: [
        {
          id: 'course-uuid',
          lmsCourseId: '2290',
          name: 'Elementary Level - 3 - General English',
          category: 'English Adult',
          keyPersonLmsUserId: '92',
          keyPersonName: 'Developer',
        },
      ],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const prisma = {
      course: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const firebaseTokens = {
      createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
    };
    const config = {
      get: jest.fn().mockReturnValue('test'),
    } as unknown as ConfigService;
    const service = new AuthService(
      lmsClient as never,
      authSync as never,
      prisma as never,
      firebaseTokens as never,
      config as never,
    );

    const result = await service.login({
      role: 'admin',
      username: 'developer',
      password: 'developer-password',
    });

    expect(result.appUser.canViewAllCourses).toBe(false);
    expect(result.courses).toHaveLength(1);
    expect(result.courses[0].students).toEqual([
      { lmsUserId: '8660', name: 'Linked Student' },
    ]);
  });

  it('returns teacher course students from the LMS roster', async () => {
    const lmsUser = {
      lmsUserId: 'teacher-1',
      role: 'teacher' as const,
      name: 'Teacher One',
      courses: [
        {
          lmsCourseId: '2203',
          name: 'Preparation IELTS - IELTS',
          category: 'Preparation',
          students: [{ lmsUserId: '9001', name: 'Teacher Student' }],
        },
      ],
    };
    const synced = {
      user: {
        id: 'teacher-uuid',
        role: 'TEACHER',
        name: 'Teacher One',
        email: null,
      },
      courses: [
        {
          id: 'course-uuid',
          lmsCourseId: '2203',
          name: 'Preparation IELTS - IELTS',
          category: 'Preparation',
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
      {} as never,
      firebaseTokens as never,
      config as never,
    );

    const result = await service.login({
      role: 'teacher',
      username: 'teacher.one',
      password: 'teacher-password',
    });

    expect(result.courses).toHaveLength(1);
    expect(result.courses[0].students).toEqual([
      { lmsUserId: '9001', name: 'Teacher Student' },
    ]);
  });

  it('grants super-admin access only to the hardcoded admin credentials', async () => {
    const lmsUser = {
      lmsUserId: '14',
      role: 'admin' as const,
      name: 'Esam',
      isSuperAdmin: false,
      courses: [],
    };
    const synced = {
      user: {
        id: 'admin-uuid',
        role: 'ADMIN',
        name: 'Esam',
        email: null,
      },
      courses: [],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const prisma = {
      course: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const firebaseTokens = {
      createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
    };
    const config = {
      get: jest.fn().mockReturnValue('test'),
    } as unknown as ConfigService;
    const service = new AuthService(
      lmsClient as never,
      authSync as never,
      prisma as never,
      firebaseTokens as never,
      config as never,
    );

    const result = await service.login({
      role: 'admin',
      username: 'esam',
      password: '123#@!0',
    });

    expect(result.appUser.isSuperAdmin).toBe(true);
    expect(result.appUser.isManagerOperation).toBe(false);
    expect(result.appUser.canViewAllCourses).toBe(true);
    expect(lmsClient.authenticate).toHaveBeenCalledWith(
      expect.objectContaining({
        hints: expect.objectContaining({
          hasFullAccess: true,
          canViewAllCourses: true,
        }),
      }),
    );
    expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith(
      expect.objectContaining({
        isSuperAdmin: true,
        canViewAllCourses: true,
      }),
    );
  });

  it('grants abdelrahman both super-admin and technical-support access', async () => {
    const lmsUser = {
      lmsUserId: '92',
      role: 'admin' as const,
      name: 'abdelrahman',
      isSuperAdmin: false,
      courses: [],
    };
    const synced = {
      user: {
        id: 'support-admin-uuid',
        role: 'ADMIN',
        name: 'abdelrahman',
        email: null,
      },
      courses: [],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const prisma = {
      course: {
        findMany: jest.fn().mockResolvedValue([]),
      },
    };
    const firebaseTokens = {
      createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
    };
    const config = {
      get: jest.fn().mockReturnValue('test'),
    } as unknown as ConfigService;
    const service = new AuthService(
      lmsClient as never,
      authSync as never,
      prisma as never,
      firebaseTokens as never,
      config as never,
    );

    const result = await service.login({
      role: 'admin',
      username: 'abdelrahman',
      password: 'Casillas2004',
    });

    expect(result.appUser.isSuperAdmin).toBe(true);
    expect(result.appUser.isManagerOperation).toBe(false);
    expect(result.appUser.canViewAllCourses).toBe(true);
    expect(result.appUser.isTechnicalSupport).toBe(true);
    expect(lmsClient.authenticate).toHaveBeenCalledWith(
      expect.objectContaining({
        hints: expect.objectContaining({
          hasFullAccess: true,
          canViewAllCourses: true,
        }),
      }),
    );
    expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith(
      expect.objectContaining({
        isSuperAdmin: true,
        canViewAllCourses: true,
        isTechnicalSupport: true,
      }),
    );
  });
  it.each([
    { username: 'youssef', password: 'youssef@2023', name: 'Youssef' },
    { username: 'eman.library', password: 'E123456', name: 'Eman Library' },
  ])(
    'grants manager-operation visibility without super-admin permissions for $username',
    async ({ username, password, name }) => {
      const lmsUser = {
        lmsUserId: '77',
        role: 'admin' as const,
        name,
        isSuperAdmin: false,
        courses: [
          {
            lmsCourseId: '2203',
            name: 'Preparation IELTS - IELTS',
            category: 'Preparation',
            students: [{ lmsUserId: '9001', name: 'Student From LMS' }],
          },
        ],
      };
      const synced = {
        user: {
          id: 'manager-uuid',
          role: 'ADMIN',
          name,
          email: null,
        },
        courses: [],
      };
      const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
      const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
      const prisma = {
        course: {
          findMany: jest
            .fn()
            .mockResolvedValueOnce([])
            .mockResolvedValueOnce([
              {
                id: 'course-uuid',
                lmsCourseId: '2203',
                name: 'Preparation IELTS - IELTS',
                category: 'Preparation',
                keyPersonLmsUserId: '92',
                keyPersonName: 'testapp',
                memberships: [
                  {
                    user: {
                      lmsUserId: 'stale-db-student',
                      name: 'Student From DB',
                    },
                  },
                ],
              },
            ]),
        },
      };
      const firebaseTokens = {
        createCustomToken: jest.fn().mockResolvedValue('firebase-token'),
      };
      const config = {
        get: jest.fn().mockReturnValue('test'),
      } as unknown as ConfigService;
      const service = new AuthService(
        lmsClient as never,
        authSync as never,
        prisma as never,
        firebaseTokens as never,
        config as never,
      );

      const result = await service.login({
        role: 'admin',
        username,
        password,
      });

      expect(result.appUser.isSuperAdmin).toBe(false);
      expect(result.appUser.isManagerOperation).toBe(true);
      expect(result.appUser.canViewAllCourses).toBe(true);
      expect(result.courses).toHaveLength(1);
      expect(result.courses[0].students).toEqual([
        { lmsUserId: '9001', name: 'Student From LMS' },
      ]);
      expect(lmsClient.authenticate).toHaveBeenCalledWith(
        expect.objectContaining({
          hints: expect.objectContaining({
            hasFullAccess: false,
            canViewAllCourses: true,
          }),
        }),
      );
      expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith(
        expect.objectContaining({
          courseIds: [],
          isSuperAdmin: false,
          canViewAllCourses: true,
        }),
      );
    },
  );
});
