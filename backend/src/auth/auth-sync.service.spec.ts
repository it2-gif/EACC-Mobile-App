import {
  CourseStatus,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/enums';

jest.mock('../database/prisma.service', () => ({
  PrismaService: class PrismaService {},
}));

import { AuthSyncService } from './auth-sync.service';

describe('AuthSyncService', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('upserts the LMS user, active courses, and memberships', async () => {
    const now = new Date('2026-06-18T12:00:00.000Z');
    jest.spyOn(global, 'Date').mockImplementation(() => now);

    const user = {
      id: 'user-1',
      role: UserRole.STUDENT,
      name: 'Esam Test',
      email: 'student@example.com',
    };
    const course = {
      id: 'course-1',
      lmsCourseId: '2191',
      name: 'Elementary Level - 3',
      category: 'English',
    };
    const tx = {
      user: { upsert: jest.fn().mockResolvedValue(user) },
      course: { upsert: jest.fn().mockResolvedValue(course) },
      courseMembership: { upsert: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      $transaction: jest.fn((callback: (transaction: typeof tx) => unknown) =>
        callback(tx),
      ),
    };

    const service = new AuthSyncService(prisma as never);
    const result = await service.syncLmsUser({
      lmsUserId: '3937',
      role: 'student',
      name: 'Esam Test',
      email: 'student@example.com',
      courses: [
        {
          lmsCourseId: '2191',
          name: 'Elementary Level - 3',
          category: 'English',
        },
      ],
    });

    const activeCourseCreate = expect.objectContaining({
      lmsCourseId: '2191',
      status: CourseStatus.ACTIVE,
    }) as unknown;
    const activeMembershipCreate = expect.objectContaining({
      role: UserRole.STUDENT,
      status: MembershipStatus.ACTIVE,
    }) as unknown;

    expect(result).toEqual({ user, courses: [course] });
    expect(tx.user.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          lmsSource_lmsUserId_role: {
            lmsSource: 'eacc_lms',
            lmsUserId: '3937',
            role: UserRole.STUDENT,
          },
        },
      }),
    );
    expect(tx.course.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: activeCourseCreate,
      }),
    );
    expect(tx.courseMembership.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: activeMembershipCreate,
      }),
    );
  });

  it('syncs LMS course students as active student memberships', async () => {
    const teacher = {
      id: 'teacher-1',
      role: UserRole.TEACHER,
      name: 'Teacher One',
      email: null,
    };
    const student = {
      id: 'student-1',
      role: UserRole.STUDENT,
      name: 'Student One',
      email: null,
    };
    const course = {
      id: 'course-1',
      lmsCourseId: '2203',
      name: 'Preparation IELTS - IELTS',
      category: 'Preparation',
    };
    const tx = {
      user: {
        upsert: jest
          .fn()
          .mockResolvedValueOnce(teacher)
          .mockResolvedValueOnce(student),
      },
      course: { upsert: jest.fn().mockResolvedValue(course) },
      courseMembership: { upsert: jest.fn().mockResolvedValue({}) },
    };
    const prisma = {
      $transaction: jest.fn((callback: (transaction: typeof tx) => unknown) =>
        callback(tx),
      ),
    };

    const service = new AuthSyncService(prisma as never);
    await service.syncLmsUser({
      lmsUserId: 'teacher-lms-id',
      role: 'teacher',
      name: 'Teacher One',
      courses: [
        {
          lmsCourseId: '2203',
          name: 'Preparation IELTS - IELTS',
          category: 'Preparation',
          students: [{ lmsUserId: '9001', name: 'Student One' }],
        },
      ],
    });

    expect(tx.user.upsert).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: {
          lmsSource_lmsUserId_role: {
            lmsSource: 'eacc_lms',
            lmsUserId: '9001',
            role: UserRole.STUDENT,
          },
        },
        create: expect.objectContaining({
          lmsUserId: '9001',
          role: UserRole.STUDENT,
          name: 'Student One',
          status: UserStatus.ACTIVE,
        }),
      }),
    );
    expect(tx.courseMembership.upsert).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({
        where: {
          courseId_userId_role: {
            courseId: 'course-1',
            userId: 'student-1',
            role: UserRole.STUDENT,
          },
        },
        create: expect.objectContaining({
          role: UserRole.STUDENT,
          status: MembershipStatus.ACTIVE,
        }),
      }),
    );
  });
});
