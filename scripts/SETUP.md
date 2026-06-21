# Firebase setup for EACC Chat

Run these steps once to enable secure student and teacher chat access.

## 1. Create backend credentials

1. Open Firebase Console -> Project settings -> Service accounts.
2. Select **Generate new private key**.
3. Open the downloaded JSON file locally.
4. Add these values to `backend/.env`:

```dotenv
FIREBASE_PROJECT_ID=eacc-mobile-app
FIREBASE_CLIENT_EMAIL=value_from_client_email
FIREBASE_PRIVATE_KEY="value_from_private_key_with_\n_line_breaks"
```

Keep the private key on one quoted line. Never add the downloaded JSON file or
`backend/.env` to source control.

## 2. Restart and verify the backend

```powershell
cd backend
npm.cmd run build
node dist\src\main.js
```

After a valid student or teacher login, `/v1/auth/lms-login` now returns
`firebase.customToken` and `nextStep: "ready"`.

## 3. Deploy secure rules

From the project root:

```powershell
& "$env:APPDATA\npm\firebase.cmd" deploy --only firestore:rules,storage --project eacc-mobile-app
```

These rules intentionally support only authenticated students and teachers.
Admin Firebase access remains disabled until the admin LMS flow is implemented.

## 4. Storage CORS

Chrome blocks uploads to Firebase Storage from `localhost` unless CORS is configured.

### Option A: Google Cloud Shell

1. Open: https://console.cloud.google.com/
2. Select project: `eacc-mobile-app`
3. Open **Cloud Shell** from the terminal icon
4. Upload `storage.cors.json` from this project, or create it in Cloud Shell
5. Run:

```bash
gsutil cors set storage.cors.json gs://eacc-mobile-app.firebasestorage.app
gsutil cors get gs://eacc-mobile-app.firebasestorage.app
```

### Option B: Local script

Use this only if your local Google credentials can access the Storage bucket:

```powershell
cd scripts
npm install
$env:GOOGLE_APPLICATION_CREDENTIALS = "path\to\service-account.json"
node set-storage-cors.js
```

## 5. Test the app

```powershell
flutter run -d chrome
```

1. Sign in as a student and send text and an image in an assigned course.
2. Sign out and sign in as that course's teacher.
3. Confirm the teacher sees the student thread and can reply.
4. Restart Chrome and confirm the signed-in course screen is restored.
5. Sign out and confirm the app returns to login.

## 6. Enable web push notifications

Web push requires a VAPID key from Firebase:

1. Open Firebase Console -> Project settings -> Cloud Messaging.
2. Under **Web Push certificates**, copy the **Key pair** value.
3. For local web builds:

```powershell
flutter run -d chrome `
  --dart-define=EACC_FCM_VAPID_KEY=YOUR_VAPID_KEY_HERE
```

4. For GitHub Pages, add a repository secret named `EACC_FCM_VAPID_KEY`
   with the same value. The deploy workflow passes it into the web build.

5. After login, allow notifications when the browser asks.

Without the VAPID key, the app can still chat in real time through Firestore,
but browser pop-up notifications will not be delivered on web.
