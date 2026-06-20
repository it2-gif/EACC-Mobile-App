import { Module } from '@nestjs/common';
import { EaccLmsClient } from './eacc-lms.client';

@Module({
  providers: [EaccLmsClient],
  exports: [EaccLmsClient],
})
export class LmsModule {}
