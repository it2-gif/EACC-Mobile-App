const { initializeApp, applicationDefault } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');

initializeApp({
  credential: applicationDefault(),
  storageBucket: 'eacc-mobile-app.firebasestorage.app',
});

const db = getFirestore();
const bucket = getStorage().bucket();

async function deleteCollection(ref, batchSize = 100) {
  while (true) {
    const snapshot = await ref.limit(batchSize).get();
    if (snapshot.empty) return;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

async function main() {
  console.log('Deleting all chat messages and threads...');

  const courses = await db.collection('courses').get();

  for (const course of courses.docs) {
    console.log(`Course ${course.id}`);

    const threads = await course.ref.collection('threads').get();

    for (const thread of threads.docs) {
      console.log(`  Deleting thread ${thread.id}`);

      await deleteCollection(thread.ref.collection('messages'), 100);
      await thread.ref.delete();
    }
  }

  console.log('Deleting uploaded chat files...');

  await bucket.deleteFiles({
    prefix: 'chat_uploads/',
  });

  console.log('Done. All chat history and uploaded chat files deleted.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});