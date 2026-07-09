import {
  ForbiddenException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
import { DecodedIdToken } from 'firebase-admin/auth';
import {
  CourseStatus,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/enums';
import { PrismaService } from '../database/prisma.service';
import { FirebaseAuthService } from '../firebase/firebase-auth.service';

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly firebaseAuth: FirebaseAuthService,
  ) {}

  async listUsers(firebaseIdToken: string) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertSuperAdmin(identity);

    const users = await this.prisma.user.findMany({
      orderBy: [{ role: 'asc' }, { name: 'asc' }],
      select: {
        id: true,
        lmsUserId: true,
        role: true,
        name: true,
        email: true,
        status: true,
        lastLoginAt: true,
      },
    });

    return users.map((user) => ({
      id: user.id,
      lmsUserId: user.lmsUserId,
      role: user.role.toLowerCase(),
      name: user.name,
      email: user.email ?? null,
      status: user.status.toLowerCase(),
      lastLoginAt: user.lastLoginAt?.toISOString() ?? null,
    }));
  }

  async getCourse(lmsCourseId: string, firebaseIdToken: string) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    this.assertAdminCourseAccess(identity, lmsCourseId);

    const course = await this.prisma.course.findFirst({
      where: { lmsCourseId, status: CourseStatus.ACTIVE },
      include: {
        memberships: {
          where: {
            role: UserRole.STUDENT,
            status: MembershipStatus.ACTIVE,
            user: { status: UserStatus.ACTIVE },
          },
          include: {
            user: true,
          },
        },
      },
    });

    if (!course) {
      throw new NotFoundException(`Course ${lmsCourseId} not found`);
    }

    return {
      id: course.id,
      lmsCourseId: course.lmsCourseId,
      name: course.name,
      category: course.category,
      keyPersonLmsUserId: course.keyPersonLmsUserId,
      keyPersonName: course.keyPersonName,
      students: course.memberships.map((m) => ({
        lmsUserId: m.user.lmsUserId,
        name: m.user.name,
      })),
    };
  }

  private assertAdminCourseAccess(
    identity: DecodedIdToken,
    lmsCourseId: string,
  ) {
    if (identity.role !== 'admin') {
      throw new UnauthorizedException({
        code: 'ADMIN_ROLE_REQUIRED',
        message: 'Only admin accounts can load admin course details.',
      });
    }

    if (
      identity.isSuperAdmin === true ||
      identity.canViewAllCourses === true
    ) {
      return;
    }

    const courseIds = this.readCourseIds(identity);
    if (!courseIds.includes(lmsCourseId)) {
      throw new ForbiddenException({
        code: 'COURSE_ACCESS_DENIED',
        message: 'This admin account cannot access that course.',
      });
    }
  }

  private assertSuperAdmin(identity: DecodedIdToken) {
    if (identity.role !== 'admin' || identity.isSuperAdmin !== true) {
      throw new ForbiddenException({
        code: 'SUPER_ADMIN_REQUIRED',
        message: 'Only super admin accounts can access this admin resource.',
      });
    }
  }

  private readCourseIds(identity: DecodedIdToken): string[] {
    if (!Array.isArray(identity.courseIds)) return [];

    return identity.courseIds
      .filter((value): value is string => typeof value === 'string')
      .map((value) => value.trim())
      .filter(Boolean);
  }
}
