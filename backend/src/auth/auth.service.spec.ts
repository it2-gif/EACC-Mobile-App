import { ConfigService } from '@nestjs/config';
import { CourseStatus, UserRole } from '../../generated/prisma/enums';

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
      role: 'student',
      username: 'student@example.com',
      password: 'password',
    });

    expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith(
      expect.objectContaining({
        appUserId: synced.user.id,
        lmsUserId: '3937',
        displayName: 'Esam Test',
        role: 'student',
        courseIds: ['2191'],
        isSuperAdmin: false,
        canViewAllCourses: false,
        isTechnicalSupport: false,
      }),
    );
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
      role: 'teacher',
      username: 'teacher.one',
      password: 'teacher-password',
    });

    expect(result.courses).toHaveLength(1);
    expect(result.courses[0].students).toEqual([
      { lmsUserId: '9001', name: 'Teacher Student' },
    ]);
  });

  it('falls back to stored active course students when the LMS session has no roster', async () => {
    const lmsUser = {
      lmsUserId: 'student-1',
      role: 'student' as const,
      name: 'Student One',
      courses: [
        {
          lmsCourseId: '2297',
          name: 'Course 2297',
          category: 'Elementary Level - 3 - General English',
        },
      ],
    };
    const synced = {
      user: {
        id: 'student-uuid',
        role: 'STUDENT',
        name: 'Student One',
        email: null,
      },
      courses: [
        {
          id: 'course-uuid',
          lmsCourseId: '2297',
          name: 'Course 2297',
          category: 'Elementary Level - 3 - General English',
          keyPersonLmsUserId: '92',
          keyPersonName: 'Developer',
        },
      ],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const prisma = {
      course: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 'course-uuid',
            memberships: [
              {
                role: UserRole.STUDENT,
                user: { lmsUserId: 'student-1', name: 'Student One' },
              },
              {
                role: UserRole.STUDENT,
                user: { lmsUserId: 'student-2', name: 'Student Two' },
              },
              {
                role: UserRole.TEACHER,
                user: { lmsUserId: 'teacher-1', name: 'Teacher One' },
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
      role: 'student',
      username: 'student.one',
      password: 'student-password',
    });

    expect(result.courses[0]).toEqual(
      expect.objectContaining({
        lmsCourseId: '2297',
        teacherName: 'Teacher One',
        students: [
          { lmsUserId: 'student-1', name: 'Student One' },
          { lmsUserId: 'student-2', name: 'Student Two' },
        ],
      }),
    );
  });

  it('grants super-admin access from the LMS full-access flag', async () => {
    const lmsUser = {
      lmsUserId: '14',
      role: 'admin' as const,
      name: 'Esam',
      isSuperAdmin: true,
      isManagerOperation: false,
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
      username: 'lms.fullaccess',
      password: '123#@!0',
    });

    expect(result.appUser.isSuperAdmin).toBe(true);
    expect(result.appUser.isManagerOperation).toBe(false);
    expect(result.appUser.canViewAllCourses).toBe(true);
    expect(lmsClient.authenticate).toHaveBeenCalledWith(
      expect.objectContaining({
        hints: { knownCourseIds: [] },
      }),
    );
    expect(firebaseTokens.createCustomToken).toHaveBeenCalledWith(
      expect.objectContaining({
        isSuperAdmin: true,
        canViewAllCourses: true,
      }),
    );
  });

  it('grants super-admin and technical-support access from LMS flags', async () => {
    const lmsUser = {
      lmsUserId: '92',
      role: 'admin' as const,
      name: 'abdelrahman',
      isSuperAdmin: true,
      isTechnicalSupport: true,
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
        hints: { knownCourseIds: [] },
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

  it('does not grant super-admin access from a legacy username without the LMS flag', async () => {
    const lmsUser = {
      lmsUserId: '14',
      role: 'admin' as const,
      name: 'Esam',
      isSuperAdmin: false,
      isManagerOperation: false,
      courses: [],
    };
    const synced = {
      user: {
        id: 'legacy-super-admin-uuid',
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

    expect(result.appUser.isSuperAdmin).toBe(false);
    expect(result.appUser.isManagerOperation).toBe(false);
    expect(result.appUser.canViewAllCourses).toBe(false);
    expect(lmsClient.authenticate).toHaveBeenCalledWith(
      expect.objectContaining({
        hints: { knownCourseIds: [] },
      }),
    );
  });

  it.each([
    { username: 'youssef', password: 'youssef@2023', name: 'Youssef' },
    { username: 'eman.library', password: 'E123456', name: 'Eman Library' },
    { username: 'niven', password: 'Niven@2025#', name: 'Niven' },
  ])(
    'grants manager-operation visibility from the LMS flag for $username',
    async ({ username, password, name }) => {
      const lmsUser = {
        lmsUserId: '77',
        role: 'admin' as const,
        name,
        isSuperAdmin: false,
        isManagerOperation: true,
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
                    role: UserRole.STUDENT,
                    user: {
                      lmsUserId: 'stale-db-student',
                      name: 'Student From DB',
                    },
                  },
                  {
                    role: UserRole.TEACHER,
                    user: {
                      lmsUserId: '721258',
                      name: 'Mohamed El-Sayad',
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
      expect(result.courses[0].teacherName).toBe('Mohamed El-Sayad');
      expect(lmsClient.authenticate).toHaveBeenCalledWith(
        expect.objectContaining({
          hints: expect.objectContaining({
            knownCourseIds: [],
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

  it('archives active app courses missing from the full-access LMS open-course list', async () => {
    const lmsUser = {
      lmsUserId: '14',
      role: 'admin' as const,
      name: 'Esam',
      isSuperAdmin: true,
      isManagerOperation: false,
      isCourseCatalogComplete: true,
      courses: [
        {
          lmsCourseId: '2203',
          name: 'Open Course',
          category: 'Preparation',
        },
      ],
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
        findMany: jest
          .fn()
          .mockResolvedValueOnce([])
          .mockResolvedValueOnce([
            {
              id: 'course-uuid',
              lmsCourseId: '2203',
              name: 'Open Course',
              category: 'Preparation',
              keyPersonLmsUserId: null,
              keyPersonName: null,
              memberships: [],
            },
          ]),
        updateMany: jest.fn().mockResolvedValue({ count: 24 }),
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
      password: 'password',
    });

    expect(prisma.course.updateMany).toHaveBeenCalledWith({
      where: {
        lmsSource: 'eacc_lms',
        status: CourseStatus.ACTIVE,
        lmsCourseId: { notIn: ['2203'] },
      },
      data: { status: CourseStatus.ARCHIVED },
    });
    expect(result.courses).toHaveLength(1);
    expect(result.courses[0].lmsCourseId).toBe('2203');
  });
  it('does not archive cached courses when the LMS open-course list is incomplete', async () => {
    const lmsUser = {
      lmsUserId: '14',
      role: 'admin' as const,
      name: 'Esam',
      isSuperAdmin: true,
      isManagerOperation: false,
      isCourseCatalogComplete: false,
      courses: [
        {
          lmsCourseId: '2203',
          name: 'Visible Page 1 Course',
          category: 'Preparation',
        },
      ],
    };
    const synced = {
      user: {
        id: 'admin-uuid',
        role: 'ADMIN',
        name: 'Esam',
        email: null,
      },
      courses: [
        {
          id: 'course-uuid',
          lmsCourseId: '2203',
          name: 'Visible Page 1 Course',
          category: 'Preparation',
        },
      ],
    };
    const lmsClient = { authenticate: jest.fn().mockResolvedValue(lmsUser) };
    const authSync = { syncLmsUser: jest.fn().mockResolvedValue(synced) };
    const prisma = {
      course: {
        findMany: jest.fn().mockResolvedValue([]),
        updateMany: jest.fn(),
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

    await service.login({
      role: 'admin',
      username: 'esam',
      password: 'password',
    });

    expect(prisma.course.updateMany).not.toHaveBeenCalled();
  });
});
