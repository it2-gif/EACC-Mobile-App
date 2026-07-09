import {
  CourseStatus,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/enums';

jest.mock('../database/prisma.service', () => ({
  PrismaService: class PrismaService {},
}));

jest.mock('../firebase/firebase-auth.service', () => ({
  FirebaseAuthService: class FirebaseAuthService {},
}));

jest.mock('../lms/eacc-lms.client', () => ({
  EaccLmsClient: class EaccLmsClient {},
}));

import { AdminService } from './admin.service';

describe('AdminService', () => {
  it('requires super admin access to list users', async () => {
    const prisma = {
      user: {
        findMany: jest.fn(),
      },
    };
    const { service } = createService({
      prisma,
      firebaseAuth: {
        verifyIdToken: jest.fn().mockResolvedValue({
          role: 'admin',
          isSuperAdmin: false,
          canViewAllCourses: true,
        }),
      },
    });

    await expect(service.listUsers('firebase-token')).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'SUPER_ADMIN_REQUIRED',
      }),
    });
    expect(prisma.user.findMany).not.toHaveBeenCalled();
  });

  it('returns a course with active student memberships for all-course admins', async () => {
    const prisma = {
      course: {
        findFirst: jest.fn().mockResolvedValue({
          id: 'course-uuid',
          lmsCourseId: '2318',
          name: 'Preparation IELTS - IELTS',
          category: 'Preparation',
          keyPersonLmsUserId: '77',
          keyPersonName: 'Safy',
          memberships: [
            {
              user: {
                lmsUserId: '8680',
                name: 'Jana ramy ahmed',
              },
            },
          ],
        }),
      },
    };
    const firebaseAuth = {
      verifyIdToken: jest.fn().mockResolvedValue({
        role: 'admin',
        canViewAllCourses: true,
        courseIds: [],
      }),
    };
    const { service } = createService({ prisma, firebaseAuth });

    const result = await service.getCourse('2318', 'firebase-token');

    expect(firebaseAuth.verifyIdToken).toHaveBeenCalledWith('firebase-token');
    expect(prisma.course.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { lmsCourseId: '2318', status: CourseStatus.ACTIVE },
        include: expect.objectContaining({
          memberships: expect.objectContaining({
            where: {
              role: UserRole.STUDENT,
              status: MembershipStatus.ACTIVE,
              user: { status: UserStatus.ACTIVE },
            },
          }),
        }),
      }),
    );
    expect(result.students).toEqual([
      { lmsUserId: '8680', name: 'Jana ramy ahmed' },
    ]);
  });

  it('denies scoped admins when the course is not in their token claims', async () => {
    const prisma = {
      course: {
        findFirst: jest.fn(),
      },
    };
    const { service } = createService({
      prisma,
      firebaseAuth: {
        verifyIdToken: jest.fn().mockResolvedValue({
          role: 'admin',
          isSuperAdmin: false,
          canViewAllCourses: false,
          courseIds: ['2203'],
        }),
      },
    });

    await expect(
      service.getCourse('2318', 'firebase-token'),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'COURSE_ACCESS_DENIED',
      }),
    });
    expect(prisma.course.findFirst).not.toHaveBeenCalled();
  });

  it('refreshes one LMS course for all-course admins and syncs its students', async () => {
    const course = {
      id: 'course-uuid',
      lmsCourseId: '455',
      name: 'Pre-Intermediate Level - 5',
      category: 'English Adult',
      keyPersonLmsUserId: '12',
      keyPersonName: 'Esraa Al Shaik',
    };
    const student = {
      id: 'student-uuid',
      lmsUserId: '7001',
      name: 'Student One',
    };
    const tx = {
      course: {
        upsert: jest.fn().mockResolvedValue(course),
      },
      user: {
        upsert: jest.fn().mockResolvedValue(student),
      },
      courseMembership: {
        upsert: jest.fn().mockResolvedValue({}),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback: (transaction: typeof tx) => unknown) =>
        callback(tx),
      ),
    };
    const lmsClient = {
      loadAdminCourseById: jest.fn().mockResolvedValue({
        lmsCourseId: '455',
        name: 'Pre-Intermediate Level - 5',
        category: 'English Adult',
        keyPersonLmsUserId: '12',
        keyPersonName: 'Esraa Al Shaik',
        students: [{ lmsUserId: '7001', name: 'Student One' }],
      }),
    };
    const { service } = createService({
      prisma,
      lmsClient,
      configValues: {
        LMS_SYNC_ADMIN_USERNAME: 'sync-admin',
        LMS_SYNC_ADMIN_PASSWORD: 'sync-password',
      },
      firebaseAuth: {
        verifyIdToken: jest.fn().mockResolvedValue({
          role: 'admin',
          isSuperAdmin: false,
          canViewAllCourses: true,
        }),
      },
    });

    const result = await service.refreshCourse('455', 'firebase-token');

    expect(lmsClient.loadAdminCourseById).toHaveBeenCalledWith(
      { username: 'sync-admin', password: 'sync-password' },
      '455',
    );
    expect(tx.course.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          lmsSource_lmsCourseId: {
            lmsSource: 'eacc_lms',
            lmsCourseId: '455',
          },
        },
        create: expect.objectContaining({
          lmsCourseId: '455',
          status: CourseStatus.ACTIVE,
        }),
      }),
    );
    expect(tx.user.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          lmsUserId: '7001',
          role: UserRole.STUDENT,
          status: UserStatus.ACTIVE,
        }),
      }),
    );
    expect(tx.courseMembership.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          role: UserRole.STUDENT,
          status: MembershipStatus.ACTIVE,
        }),
      }),
    );
    expect(result).toMatchObject({
      lmsCourseId: '455',
      name: 'Pre-Intermediate Level - 5',
      category: 'English Adult',
      students: [{ lmsUserId: '7001', name: 'Student One' }],
    });
  });
});

function createService({
  prisma = {},
  firebaseAuth = {
    verifyIdToken: jest.fn().mockResolvedValue({
      role: 'admin',
      isSuperAdmin: true,
    }),
  },
  lmsClient = {},
  configValues = {},
}: {
  prisma?: unknown;
  firebaseAuth?: unknown;
  lmsClient?: unknown;
  configValues?: Record<string, string | undefined>;
}) {
  const config = {
    get: jest.fn((key: string) => configValues[key]),
  };

  return {
    config,
    service: new AdminService(
      prisma as never,
      firebaseAuth as never,
      lmsClient as never,
      config as never,
    ),
  };
}
