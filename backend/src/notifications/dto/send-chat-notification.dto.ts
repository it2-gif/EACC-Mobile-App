import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

export class SendChatNotificationDto {
  @IsString()
  @MaxLength(100)
  courseId!: string;

  @IsString()
  @MaxLength(100)
  threadId!: string;

  @IsString()
  @IsIn(['student', 'teacher', 'admin'])
  senderRole!: 'student' | 'teacher' | 'admin';

  @IsString()
  @MaxLength(200)
  senderName!: string;

  @IsString()
  @IsIn(['text', 'image', 'video', 'voice'])
  messageType!: 'text' | 'image' | 'video' | 'voice';

  @IsOptional()
  @IsString()
  @MaxLength(200)
  messageId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  previewText?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  studentName?: string;

  @IsOptional()
  @IsString()
  @IsIn(['thread', 'course'])
  audience?: 'thread' | 'course';
}
