import { LmsLoginCredentials, NormalizedLmsUser } from './lms-types';

export const LMS_CLIENT = Symbol('LMS_CLIENT');

export interface LmsClient {
  authenticate(credentials: LmsLoginCredentials): Promise<NormalizedLmsUser>;
}
