const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

initializeApp({
  credential: applicationDefault(),
  projectId: 'eacc-mobile-app',
  storageBucket: 'eacc-mobile-app.firebasestorage.app',
});

const db = getFirestore();
const bucket = getStorage().bucket();

async function deleteCollection(ref, batchSize = 100) {
  while (true) {
    const snapshot = await ref.limit(batchSize).get();
    if (snapshot.empty) return 0;

    const batch = db.batch();
    let count = 0;

    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
      count++;
    }

    await batch.commit();

    if (count < batchSize) return count;
  }
}

async function deleteThread(threadRef) {
  await deleteCollection(threadRef.collection('messages'), 100);
  await threadRef.delete();
}

async function main() {
  console.log('Deleting chat threads/messages from every course document...');

  const courseDocs = await db.collection('courses').listDocuments();

  for (const courseRef of courseDocs) {
    console.log(`Course ${courseRef.id}`);

    const threadRefs = await courseRef.collection('threads').listDocuments();

    for (const threadRef of threadRefs) {
      console.log(`  Thread ${threadRef.id}`);
      await deleteThread(threadRef);
    }
  }

  console.log('Deleting audit logs...');
  await deleteCollection(db.collection('audit_logs'), 100);

  console.log('Deleting uploaded chat files...');
  try {
    await bucket.deleteFiles({ prefix: 'chat_uploads/' });
  } catch (error) {
    if (error.code === 404) {
      console.log('Storage bucket or files not found. Skipping storage cleanup.');
    } else {
      throw error;
    }
  }

  console.log('Done. Chat threads/messages, audit logs, and uploaded files deleted.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});