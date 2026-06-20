const supportedEnvironments = ['development', 'test', 'production'] as const;

type NodeEnvironment = (typeof supportedEnvironments)[number];

export interface Environment {
  NODE_ENV: NodeEnvironment;
  PORT: number;
  DATABASE_URL: string;
  ALLOWED_ORIGINS: string[];
  LMS_BASE_URL: string;
  LMS_REQUEST_TIMEOUT_MS: number;
  FIREBASE_PROJECT_ID?: string;
  FIREBASE_CLIENT_EMAIL?: string;
  FIREBASE_PRIVATE_KEY?: string;
}

export function validateEnvironment(
  values: Record<string, unknown>,
): Environment {
  return {
    NODE_ENV: readNodeEnvironment(values.NODE_ENV),
    PORT: readPositiveInteger(values.PORT, 3000, 'PORT'),
    DATABASE_URL: readRequiredString(values.DATABASE_URL, 'DATABASE_URL'),
    ALLOWED_ORIGINS: readOrigins(values.ALLOWED_ORIGINS),
    LMS_BASE_URL:
      readOptionalUrl(values.LMS_BASE_URL, 'LMS_BASE_URL') ??
      'https://lms.eacc-egy.com',
    LMS_REQUEST_TIMEOUT_MS: readPositiveInteger(
      values.LMS_REQUEST_TIMEOUT_MS,
      10000,
      'LMS_REQUEST_TIMEOUT_MS',
    ),
    ...readFirebaseCredentials(values),
  };
}

function readFirebaseCredentials(
  values: Record<string, unknown>,
): Pick<
  Environment,
  'FIREBASE_PROJECT_ID' | 'FIREBASE_CLIENT_EMAIL' | 'FIREBASE_PRIVATE_KEY'
> {
  const projectId = readOptionalString(values.FIREBASE_PROJECT_ID);
  const clientEmail = readOptionalString(values.FIREBASE_CLIENT_EMAIL);
  const privateKey = readOptionalString(values.FIREBASE_PRIVATE_KEY);
  const configuredCount = [projectId, clientEmail, privateKey].filter(
    Boolean,
  ).length;

  if (configuredCount > 0 && configuredCount < 3) {
    throw new Error(
      'FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY must be configured together',
    );
  }

  return {
    FIREBASE_PROJECT_ID: projectId,
    FIREBASE_CLIENT_EMAIL: clientEmail,
    FIREBASE_PRIVATE_KEY: privateKey?.replace(/\\n/g, '\n'),
  };
}

function readNodeEnvironment(value: unknown): NodeEnvironment {
  const environment =
    typeof value === 'string' && value.length > 0 ? value : 'development';

  if (!supportedEnvironments.includes(environment as NodeEnvironment)) {
    throw new Error(
      `NODE_ENV must be one of: ${supportedEnvironments.join(', ')}`,
    );
  }

  return environment as NodeEnvironment;
}

function readRequiredString(value: unknown, name: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${name} is required`);
  }

  return value.trim();
}

function readOptionalString(value: unknown): string | undefined {
  if (typeof value !== 'string' || value.trim().length === 0) return undefined;
  return value.trim();
}

function readPositiveInteger(
  value: unknown,
  fallback: number,
  name: string,
): number {
  if (value === undefined || value === '') return fallback;

  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }

  return parsed;
}

function readOrigins(value: unknown): string[] {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return ['http://localhost:3000', 'http://localhost:58071'];
  }

  return value
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0)
    .map((origin) => {
      validateUrl(origin, 'ALLOWED_ORIGINS');
      return origin;
    });
}

function readOptionalUrl(value: unknown, name: string): string | undefined {
  if (typeof value !== 'string' || value.trim().length === 0) return undefined;

  const url = value.trim();
  validateUrl(url, name);
  return url;
}

function validateUrl(value: string, name: string): void {
  try {
    new URL(value);
  } catch {
    throw new Error(`${name} contains an invalid URL`);
  }
}
