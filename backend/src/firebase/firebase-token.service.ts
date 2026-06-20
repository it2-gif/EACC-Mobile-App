import { Injectable } from '@nestjs/common';
import { FirebaseAuthService, FirebaseIdentity } from './firebase-auth.service';

@Injectable()
export class FirebaseTokenService {
  constructor(private readonly firebaseAuth: FirebaseAuthService) {}

  async createCustomToken(identity: FirebaseIdentity): Promise<string> {
    return this.firebaseAuth.createCustomToken(identity);
  }
}
