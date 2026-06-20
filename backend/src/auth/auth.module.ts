import { Module } from '@nestjs/common';
import { LmsModule } from '../lms/lms.module';
import { AuthController } from './auth.controller';
import { AuthSyncService } from './auth-sync.service';
import { AuthService } from './auth.service';

@Module({
  imports: [LmsModule],
  controllers: [AuthController],
  providers: [AuthService, AuthSyncService],
})
export class AuthModule {}
