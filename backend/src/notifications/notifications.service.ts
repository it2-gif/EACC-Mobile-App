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
  private readonly recentNotificationKeys = new Map<string, number>();
  private static readonly notificationDedupeTtlMs = 5 * 60 * 1000;

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
    const senderRole = this.readSenderRole(identity);
    const senderCourseIds = this.readCourseIds(identity);

    if (senderRole !== input.senderRole) {
      throw new UnauthorizedException({
        code: 'ROLE_MISMATCH',
        message: 'The sender role does not match the Firebase identity.',
      });
    }

    // Admin has no courseIds in their token — they have global access.
    if (senderRole !== 'admin' && !senderCourseIds.includes(input.courseId)) {
      throw new UnauthorizedException({
        code: 'COURSE_ACCESS_DENIED',
        message: 'The Firebase identity does not have access to this course.',
      });
    }

    // Determine which course members to notify based on the message audience.
    // - Course announcement: notify active students in the course.
    // - Student private reply: notify active teachers in the course.
    // - Teacher/admin private message: notify only the selected student thread.
    const isCourseAudience = input.audience === 'course';

    if (isCourseAudience && senderRole === 'student') {
      throw new UnauthorizedException({
        code: 'ANNOUNCEMENT_ACCESS_DENIED',
        message: 'Students cannot send course announcements.',
      });
    }

    const dedupeKey = this.notificationDedupeKey(input);
    if (dedupeKey !== null && !this.reserveNotificationKey(dedupeKey)) {
      return {
        status: 'skipped_duplicate' as const,
        deliveredTo: 0,
        failed: 0,
      };
    }

    const rolesForQuery: UserRole[] =
      isCourseAudience
        ? [UserRole.STUDENT]
        : senderRole === 'student'
          ? [UserRole.TEACHER]
          : [UserRole.STUDENT];

    const targetMemberships = await this.prisma.courseMembership.findMany({
      where: {
        course: { lmsCourseId: input.courseId },
        role: { in: rolesForQuery },
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

    // For targeted teacher/admin messages, keep the recipient list scoped to
    // the selected student thread so one message creates one notification fan-out.
    const recipients =
      isCourseAudience
        ? targetMemberships
        : senderRole === 'student'
          ? targetMemberships // all teachers
          : targetMemberships.filter(
              (m) =>
                m.role === UserRole.STUDENT &&
                m.user.lmsUserId === input.threadId,
            );

    const recipientDeviceTokens = recipients
      .flatMap((membership) => membership.user.deviceTokens)
      .filter((token) => token.userId !== senderAppUserId);
    const latestRecipientTokenByUser = new Map<
      string,
      (typeof recipientDeviceTokens)[number]
    >();

    for (const deviceToken of recipientDeviceTokens) {
      const existingToken = latestRecipientTokenByUser.get(deviceToken.userId);
      if (
        existingToken === undefined ||
        deviceToken.lastSeenAt > existingToken.lastSeenAt
      ) {
        latestRecipientTokenByUser.set(deviceToken.userId, deviceToken);
      }
    }

    const uniqueRecipientDeviceTokens = [
      ...new Map(
        [...latestRecipientTokenByUser.values()].map((deviceToken) => [
          deviceToken.token,
          deviceToken,
        ]),
      ).values(),
    ];

    if (uniqueRecipientDeviceTokens.length === 0) {
      return { status: 'skipped' as const, deliveredTo: 0 };
    }

    const title = this.notificationTitle(input);
    const body = this.messageBody(input);
    const data = {
      type: 'chat_message',
      courseId: input.courseId,
      threadId: input.threadId,
      messageId: input.messageId ?? '',
      senderRole: input.senderRole,
      senderName: input.senderName,
      studentName: input.studentName ?? '',
      previewText: body,
      title,
      body,
    };
    const webTokens = uniqueRecipientDeviceTokens
      .filter((deviceToken) => deviceToken.platform === DevicePlatform.WEB)
      .map((deviceToken) => deviceToken.token);
    const nativeTokens = uniqueRecipientDeviceTokens
      .filter((deviceToken) => deviceToken.platform !== DevicePlatform.WEB)
      .map((deviceToken) => deviceToken.token);

    const invalidTokens: string[] = [];
    let successCount = 0;
    let failureCount = 0;
    const collapseKey = this.collapseKey(input);

    if (webTokens.length > 0) {
      const webResponse = await this.firebaseAuth
        .messaging()
        .sendEachForMulticast({
          tokens: webTokens,
          data,
          webpush: {
            headers: {
              Urgency: 'high',
            },
          },
        });

      successCount += webResponse.successCount;
      failureCount += webResponse.failureCount;
      invalidTokens.push(
        ...webResponse.responses
          .map((item, index) => ({ item, token: webTokens[index] }))
          .filter(({ item }) => !item.success)
          .map(({ token }) => token),
      );
    }

    if (nativeTokens.length > 0) {
      const nativeResponse = await this.firebaseAuth
        .messaging()
        .sendEachForMulticast({
          tokens: nativeTokens,
          notification: {
            title,
            body,
          },
          data,
          android: {
            collapseKey: collapseKey ?? undefined,
            priority: 'high',
            notification: {
              channelId: 'chat_messages',
            },
          },
          apns: {
            headers: {
              'apns-priority': '10',
              ...(collapseKey ? { 'apns-collapse-id': collapseKey } : {}),
            },
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        });

      successCount += nativeResponse.successCount;
      failureCount += nativeResponse.failureCount;
      invalidTokens.push(
        ...nativeResponse.responses
          .map((item, index) => ({ item, token: nativeTokens[index] }))
          .filter(({ item }) => !item.success)
          .map(({ token }) => token),
      );
    }

    if (invalidTokens.length > 0) {
      await this.prisma.deviceToken.updateMany({
        where: { token: { in: [...new Set(invalidTokens)] } },
        data: { active: false },
      });
    }

    return {
      status: 'sent' as const,
      deliveredTo: successCount,
      failed: failureCount,
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

  private readSenderRole(
    identity: DecodedIdToken,
  ): 'student' | 'teacher' | 'admin' {
    if (
      identity.role === 'student' ||
      identity.role === 'teacher' ||
      identity.role === 'admin'
    ) {
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

  private notificationTitle(input: SendChatNotificationDto): string {
    if (input.audience === 'course') {
      return `Announcement from ${input.senderName}`;
    }

    return input.senderName;
  }

  private notificationDedupeKey(input: SendChatNotificationDto): string | null {
    const messageId = input.messageId?.trim();
    if (!messageId) {
      return null;
    }

    return [input.courseId, input.threadId, messageId].join(':');
  }

  private reserveNotificationKey(key: string): boolean {
    const now = Date.now();
    this.pruneRecentNotificationKeys(now);

    const lastSentAt = this.recentNotificationKeys.get(key);
    const hasRecentlySent =
      lastSentAt !== undefined &&
      now - lastSentAt < NotificationsService.notificationDedupeTtlMs;
    if (hasRecentlySent) {
      return false;
    }

    this.recentNotificationKeys.set(key, now);
    return true;
  }

  private pruneRecentNotificationKeys(now: number): void {
    const cutoff = now - NotificationsService.notificationDedupeTtlMs;
    for (const [key, sentAt] of this.recentNotificationKeys.entries()) {
      if (sentAt < cutoff) {
        this.recentNotificationKeys.delete(key);
      }
    }
  }

  private collapseKey(input: SendChatNotificationDto): string | null {
    const messageId = input.messageId?.trim();
    if (!messageId) {
      return null;
    }

    const rawKey = [input.courseId, input.threadId, messageId].join('-');
    return rawKey.replace(/[^a-zA-Z0-9_-]/g, '-').substring(0, 64);
  }
}
