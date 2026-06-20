import { Global, Module } from '@nestjs/common';
import { FirebaseAuthService } from './firebase-auth.service';
import { FirebaseTokenService } from './firebase-token.service';

@Global()
@Module({
  providers: [FirebaseAuthService, FirebaseTokenService],
  exports: [FirebaseAuthService, FirebaseTokenService],
})
export class FirebaseModule {}
