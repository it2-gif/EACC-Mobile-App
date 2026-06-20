import {
  BadRequestException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import {
  DevicePlatform,
  MembershipStatus,
  UserRole,
  UserStatus,
} from '../../generated/prisma/client';
import { DecodedIdToken } from 'firebase-admin/auth';
import { PrismaService } from '../database/prisma.service';
import { FirebaseAuthService } from '../firebase/firebase-auth.service';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { SendChatNotificationDto } from './dto/send-chat-notification.dto';

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly firebaseAuth: FirebaseAuthService,
  ) {}

  async registerDeviceToken(
    firebaseIdToken: string,
    input: RegisterDeviceTokenDto,
  ) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    const appUserId = this.readAppUserId(identity);

    await this.prisma.deviceToken.upsert({
      where: { token: input.token },
      update: {
        userId: appUserId,
        platform: this.toDevicePlatform(input.platform),
        deviceName: input.deviceName?.trim() || null,
        active: true,
        lastSeenAt: new Date(),
      },
      create: {
        userId: appUserId,
        token: input.token,
        platform: this.toDevicePlatform(input.platform),
        deviceName: input.deviceName?.trim() || null,
        active: true,
        lastSeenAt: new Date(),
      },
    });

    return { status: 'registered' as const };
  }

  async notifyChatMessage(
    firebaseIdToken: string,
    input: SendChatNotificationDto,
  ) {
    const identity = await this.firebaseAuth.verifyIdToken(firebaseIdToken);
    const senderAppUserId = this.readAppUserId(identity);
    const senderRole = this.readRole(identity);
    const senderCourseIds = this.readCourseIds(identity);

    if (senderRole !== input.senderRole) {
      throw new UnauthorizedException({
        code: 'ROLE_MISMATCH',
        message: 'The sender role does not match the Firebase identity.',
      });
    }

    if (!senderCourseIds.includes(input.courseId)) {
      throw new UnauthorizedException({
        code: 'COURSE_ACCESS_DENIED',
        message: 'The Firebase identity does not have access to this course.',
      });
    }

    const targetRole =
      senderRole === 'student' ? UserRole.TEACHER : UserRole.STUDENT;
    const targetMemberships = await this.prisma.courseMembership.findMany({
      where: {
        course: { lmsCourseId: input.courseId },
        role: targetRole,
        status: MembershipStatus.ACTIVE,
        user: { status: UserStatus.ACTIVE },
      },
      include: {
        user: {
          include: {
            deviceTokens: {
              where: { active: true },
            },
          },
        },
      },
    });

    const recipients =
      senderRole === 'student'
        ? targetMemberships
        : targetMemberships.filter(
            (membership) =>
              membership.user.lmsUserId === input.threadId &&
              membership.role === UserRole.STUDENT,
          );

    const recipientTokens = recipients
      .flatMap((membership) => membership.user.deviceTokens)
      .filter((token) => token.userId !== senderAppUserId)
      .map((token) => token.token);
    const uniqueRecipientTokens = [...new Set(recipientTokens)];

    if (uniqueRecipientTokens.length === 0) {
      return { status: 'skipped' as const, deliveredTo: 0 };
    }

    const response = await this.firebaseAuth.messaging().sendEachForMulticast({
      tokens: uniqueRecipientTokens,
      notification: {
        title: input.senderName,
        body: this.messageBody(input),
      },
      data: {
        type: 'chat_message',
        courseId: input.courseId,
        threadId: input.threadId,
        senderRole: input.senderRole,
        senderName: input.senderName,
        studentName: input.studentName ?? '',
      },
      webpush: {
        notification: {
          title: input.senderName,
          body: this.messageBody(input),
        },
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'chat_messages',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    });

    const invalidTokens = response.responses
      .map((item, index) => ({ item, token: uniqueRecipientTokens[index] }))
      .filter(({ item }) => !item.success)
      .map(({ token }) => token);

    if (invalidTokens.length > 0) {
      await this.prisma.deviceToken.updateMany({
        where: { token: { in: invalidTokens } },
        data: { active: false },
      });
    }

    return {
      status: 'sent' as const,
      deliveredTo: response.successCount,
      failed: response.failureCount,
    };
  }

  private readAppUserId(identity: DecodedIdToken): string {
    if (
      typeof identity.appUserId !== 'string' ||
      identity.appUserId.length === 0
    ) {
      throw new UnauthorizedException({
        code: 'APP_USER_ID_MISSING',
        message: 'The Firebase identity is missing the EACC app user id.',
      });
    }

    return identity.appUserId;
  }

  private readRole(identity: DecodedIdToken): 'student' | 'teacher' {
    if (identity.role === 'student' || identity.role === 'teacher') {
      return identity.role;
    }

    throw new UnauthorizedException({
      code: 'ROLE_CLAIM_INVALID',
      message: 'The Firebase identity role is invalid.',
    });
  }

  private readCourseIds(identity: DecodedIdToken): string[] {
    if (!Array.isArray(identity.courseIds)) {
      return [];
    }

    return identity.courseIds
      .filter((value): value is string => typeof value === 'string')
      .map((value) => value.trim())
      .filter((value) => value.length > 0);
  }

  private toDevicePlatform(platform: RegisterDeviceTokenDto['platform']) {
    switch (platform) {
      case 'android':
        return DevicePlatform.ANDROID;
      case 'ios':
        return DevicePlatform.IOS;
      case 'web':
        return DevicePlatform.WEB;
      default:
        throw new BadRequestException({
          code: 'PLATFORM_INVALID',
          message: 'The device platform is not supported.',
        });
    }
  }

  private messageBody(input: SendChatNotificationDto): string {
    switch (input.messageType) {
      case 'image':
        return 'Sent a photo';
      case 'video':
        return 'Sent a video';
      case 'voice':
        return 'Sent a voice message';
      default:
        const previewText = input.previewText?.trim();
        return previewText && previewText.length > 0
          ? previewText
          : 'Sent a message';
    }
  }
}
