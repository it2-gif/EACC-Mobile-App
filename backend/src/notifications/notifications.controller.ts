import { Body, Controller, Headers, Post } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { SendChatNotificationDto } from './dto/send-chat-notification.dto';

@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Post('device-token')
  registerDeviceToken(
    @Headers('authorization') authorization: string | undefined,
    @Body() input: RegisterDeviceTokenDto,
  ) {
    return this.notifications.registerDeviceToken(
      this.readBearerToken(authorization),
      input,
    );
  }

  @Post('chat-message')
  notifyChatMessage(
    @Headers('authorization') authorization: string | undefined,
    @Body() input: SendChatNotificationDto,
  ) {
    return this.notifications.notifyChatMessage(
      this.readBearerToken(authorization),
      input,
    );
  }

  private readBearerToken(authorization: string | undefined): string {
    if (!authorization?.startsWith('Bearer ')) {
      return '';
    }

    return authorization.substring('Bearer '.length).trim();
  }
}
