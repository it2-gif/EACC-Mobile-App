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

import { AdminService } from './admin.service';

describe('AdminService', () => {
  it('requires super admin access to list users', async () => {
    const prisma = {
      user: {
        findMany: jest.fn(),
      },
    };
    const firebaseAuth = {
      verifyIdToken: jest.fn().mockResolvedValue({
        role: 'admin',
        isSuperAdmin: false,
        canViewAllCourses: true,
      }),
    };
    const service = new AdminService(prisma as never, firebaseAuth as never);

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
    const service = new AdminService(prisma as never, firebaseAuth as never);

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
    const firebaseAuth = {
      verifyIdToken: jest.fn().mockResolvedValue({
        role: 'admin',
        isSuperAdmin: false,
        canViewAllCourses: false,
        courseIds: ['2203'],
      }),
    };
    const service = new AdminService(prisma as never, firebaseAuth as never);

    await expect(service.getCourse('2318', 'firebase-token')).rejects.toMatchObject(
      {
        response: expect.objectContaining({
          code: 'COURSE_ACCESS_DENIED',
        }),
      },
    );
    expect(prisma.course.findFirst).not.toHaveBeenCalled();
  });
});
