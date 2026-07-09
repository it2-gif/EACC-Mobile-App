import { Module } from '@nestjs/common';
import { DatabaseModule } from '../database/database.module';
import { FirebaseModule } from '../firebase/firebase.module';
import { LmsModule } from '../lms/lms.module';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [DatabaseModule, FirebaseModule, LmsModule],
  controllers: [AdminController],
  providers: [AdminService],
})
export class AdminModule {}
