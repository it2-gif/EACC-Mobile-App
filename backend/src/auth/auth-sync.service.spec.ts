import {
  CourseStatus,
  MembershipStatus,
  UserRole,
} from '../../generated/prisma/enums';

jest.mock('../database/prisma.service', () => ({
  PrismaService: class PrismaService {},
}));

import { AuthSyncService } from './auth-sync.service';

describe('AuthSyncService', () => {
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
});
