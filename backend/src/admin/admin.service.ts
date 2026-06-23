import { Injectable } from '@nestjs/common';
import { PrismaService } from '../database/prisma.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async listUsers() {
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
}
