import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
  cert,
  getApps,
  initializeApp,
  type ServiceAccount,
} from 'firebase-admin/app';
import { getFirestore, type CollectionReference } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';

const CONFIRMATION_TOKEN = 'DELETE_CHAT_DATA_NOW';
const CHAT_UPLOAD_PREFIX = 'chat_uploads/';

async function main() {
  loadDotEnvIfPresent();

  if (process.env.CONFIRM_WIPE !== CONFIRMATION_TOKEN) {
    throw new Error(
      `Refusing to run. Set CONFIRM_WIPE=${CONFIRMATION_TOKEN} to confirm the wipe.`,
    );
  }

  const projectId = readRequiredEnv('FIREBASE_PROJECT_ID');
  const clientEmail = readRequiredEnv('FIREBASE_CLIENT_EMAIL');
  const privateKey = readRequiredEnv('FIREBASE_PRIVATE_KEY').replace(/\\n/g, '\n');
  const app =
    getApps().length > 0
      ? getApps()[0]
      : initializeApp({
          credential: cert({
            projectId,
            clientEmail,
            privateKey,
          } as ServiceAccount),
          projectId,
        });

  const db = getFirestore(app);
  const bucket = await resolveStorageBucket(getStorage(app), {
    projectId,
    configuredBucket: process.env.FIREBASE_STORAGE_BUCKET?.trim(),
  });

  console.log('Starting chat wipe...');
  console.log(`Project: ${projectId}`);
  console.log(`Bucket: ${bucket.name}`);

  const courseSnapshot = await db.collection('courses').get();
  let deletedThreads = 0;
  let deletedMessages = 0;

  for (const courseDoc of courseSnapshot.docs) {
    const threadsRef = courseDoc.ref.collection('threads');
    const threadsSnapshot = await threadsRef.get();

    for (const threadDoc of threadsSnapshot.docs) {
      const messagesRef = threadDoc.ref.collection('messages');
      const messagesSnapshot = await messagesRef.get();

      for (const messageDoc of messagesSnapshot.docs) {
        await messageDoc.ref.delete();
        deletedMessages++;
      }

      await threadDoc.ref.delete();
      deletedThreads++;
    }
  }

  const [files] = await bucket.getFiles({ prefix: CHAT_UPLOAD_PREFIX });
  let deletedFiles = 0;

  for (const file of files) {
    await file.delete();
    deletedFiles++;
  }

  console.log(`Deleted threads: ${deletedThreads}`);
  console.log(`Deleted messages: ${deletedMessages}`);
  console.log(`Deleted storage files: ${deletedFiles}`);
  console.log('Chat wipe complete.');
}

async function resolveStorageBucket(
  storage: ReturnType<typeof getStorage>,
  options: { projectId: string; configuredBucket?: string },
) {
  const candidates = [
    options.configuredBucket,
    `${options.projectId}.appspot.com`,
    `${options.projectId}.firebasestorage.app`,
  ].filter((value): value is string => Boolean(value));

  for (const candidate of candidates) {
    const bucket = storage.bucket(candidate);
    try {
      const [exists] = await bucket.exists();
      if (exists) {
        return bucket;
      }
    } catch {
      // Try the next candidate.
    }
  }

  throw new Error(
    `No Firebase Storage bucket was found. Tried: ${candidates.join(', ')}`,
  );
}

function readRequiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required`);
  }

  return value;
}

function loadDotEnvIfPresent() {
  const envPath = resolve(process.cwd(), '.env');
  if (!existsSync(envPath)) return;

  const lines = readFileSync(envPath, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;

    const equalsIndex = trimmed.indexOf('=');
    const key = trimmed.slice(0, equalsIndex).trim();
    let value = trimmed.slice(equalsIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

void main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
