import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { LmsModule } from '../lms/lms.module';
import { AuthController } from './auth.controller';
import { AuthSyncService } from './auth-sync.service';
import { AuthService } from './auth.service';

@Module({
  imports: [LmsModule, DatabaseModule],
  controllers: [AuthController],
  providers: [AuthService, AuthSyncService],
})
export class AuthModule {}
