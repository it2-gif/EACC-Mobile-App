const { Storage } = require('@google-cloud/storage');

const bucketName = 'eacc-mobile-app.firebasestorage.app';

const corsConfiguration = [
  {
    origin: ['*'],
    method: ['GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'OPTIONS'],
    responseHeader: [
      'Content-Type',
      'Authorization',
      'Content-Length',
      'User-Agent',
      'x-goog-resumable',
      'x-goog-meta-*',
    ],
    maxAgeSeconds: 3600,
  },
];

async function main() {
  const storage = new Storage({ projectId: 'eacc-mobile-app' });
  const bucket = storage.bucket(bucketName);

  await bucket.setMetadata({ cors: corsConfiguration });

  console.log(`CORS configured for gs://${bucketName}`);
}

main().catch((error) => {
  console.error('Failed to set CORS:', error.message);
  console.error('');
  console.error('If auth failed, run in Google Cloud Shell:');
  console.error(`  gsutil cors set storage.cors.json gs://${bucketName}`);
  process.exit(1);
});
