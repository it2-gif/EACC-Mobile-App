import { Module } from '@nestjs/common';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { ConfigModule } from '@nestjs/config';
import { AdminModule } from './admin/admin.module';
import { AuthModule } from './auth/auth.module';
import { validateEnvironment } from './config/environment';
import { DatabaseModule } from './database/database.module';
import { FirebaseModule } from './firebase/firebase.module';
import { HealthModule } from './health/health.module';
import { LmsModule } from './lms/lms.module';
import { NotificationsModule } from './notifications/notifications.module';
const envFilePath = [
  join(process.cwd(), 'backend', '.env'),
  join(process.cwd(), '.env'),
].filter(existsSync);

@Module({
  imports: [
    ConfigModule.forRoot({
      envFilePath,
      isGlobal: true,
      cache: true,
      validate: validateEnvironment,
    }),
    AdminModule,
    AuthModule,
    DatabaseModule,
    FirebaseModule,
    HealthModule,
    LmsModule,
    NotificationsModule,
  ],
})
export class AppModule {}
