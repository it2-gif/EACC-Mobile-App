import { validateEnvironment } from './environment';

describe('validateEnvironment', () => {
  const databaseUrl =
    'postgresql://postgres:postgres@localhost:5432/eacc_chat?schema=public';

  it('applies safe development defaults', () => {
    const environment = validateEnvironment({
      DATABASE_URL: databaseUrl,
    });

    expect(environment.NODE_ENV).toBe('development');
    expect(environment.PORT).toBe(3000);
    expect(environment.LMS_REQUEST_TIMEOUT_MS).toBe(10000);
    expect(environment.ALLOWED_ORIGINS).toContain('http://localhost:58071');
  });

  it('parses configured origins and numeric values', () => {
    const environment = validateEnvironment({
      DATABASE_URL: databaseUrl,
      NODE_ENV: 'production',
      PORT: '4000',
      LMS_REQUEST_TIMEOUT_MS: '5000',
      ALLOWED_ORIGINS: 'https://chat.eacc.example, https://admin.eacc.example',
    });

    expect(environment.PORT).toBe(4000);
    expect(environment.ALLOWED_ORIGINS).toEqual([
      'https://chat.eacc.example',
      'https://admin.eacc.example',
    ]);
  });

  it('rejects a missing database URL', () => {
    expect(() => validateEnvironment({})).toThrow('DATABASE_URL is required');
  });

  it('rejects an invalid allowed origin', () => {
    expect(() =>
      validateEnvironment({
        DATABASE_URL: databaseUrl,
        ALLOWED_ORIGINS: 'not-a-url',
      }),
    ).toThrow('ALLOWED_ORIGINS contains an invalid URL');
  });

  it('requires all Firebase credentials when any one is configured', () => {
    expect(() =>
      validateEnvironment({
        DATABASE_URL: databaseUrl,
        FIREBASE_PROJECT_ID: 'eacc-mobile-app',
      }),
    ).toThrow(
      'FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY must be configured together',
    );
  });

  it('normalizes escaped newlines in the Firebase private key', () => {
    const environment = validateEnvironment({
      DATABASE_URL: databaseUrl,
      FIREBASE_PROJECT_ID: 'eacc-mobile-app',
      FIREBASE_CLIENT_EMAIL: 'firebase@example.com',
      FIREBASE_PRIVATE_KEY: 'first\\nsecond',
    });

    expect(environment.FIREBASE_PRIVATE_KEY).toBe('first\nsecond');
  });
});
