import 'package:chatt_eacc/services/firestore_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('image upload validation', () {
    test('accepts supported image formats within the size limit', () {
      for (final extension in ['jpg', 'jpeg', 'png', 'webp', 'gif']) {
        expect(
          () => FirestoreChatService.validateImageUpload(
            fileName: 'photo.$extension',
            fileSize: 1024,
          ),
          returnsNormally,
        );
      }
    });

    test('rejects unsupported image formats', () {
      expect(
        () => FirestoreChatService.validateImageUpload(
          fileName: 'document.pdf',
          fileSize: 1024,
        ),
        throwsA(isA<ChatUploadException>()),
      );
    });

    test('rejects empty images', () {
      expect(
        () => FirestoreChatService.validateImageUpload(
          fileName: 'photo.jpg',
          fileSize: 0,
        ),
        throwsA(isA<ChatUploadException>()),
      );
    });

    test('rejects images larger than 5 MB', () {
      expect(
        () => FirestoreChatService.validateImageUpload(
          fileName: 'photo.png',
          fileSize: FirestoreChatService.maxImageSizeBytes + 1,
        ),
        throwsA(isA<ChatUploadException>()),
      );
    });
  });

  group('video upload validation', () {
    test('accepts supported videos within 50 MB', () {
      for (final extension in ['mp4', 'mov', 'm4v', 'webm']) {
        expect(
          () => FirestoreChatService.validateVideoUpload(
            fileName: 'video.$extension',
            fileSize: 1024,
          ),
          returnsNormally,
        );
      }
    });

    test('rejects videos larger than 50 MB', () {
      expect(
        () => FirestoreChatService.validateVideoUpload(
          fileName: 'video.mp4',
          fileSize: FirestoreChatService.maxVideoSizeBytes + 1,
        ),
        throwsA(isA<ChatUploadException>()),
      );
    });
  });

  group('voice upload validation', () {
    test('accepts supported voice recordings within 10 MB', () {
      for (final extension in ['aac', 'm4a', 'mp3', 'ogg', 'opus', 'wav']) {
        expect(
          () => FirestoreChatService.validateVoiceUpload(
            fileName: 'voice.$extension',
            fileSize: 1024,
          ),
          returnsNormally,
        );
      }
    });

    test('rejects voice recordings larger than 10 MB', () {
      expect(
        () => FirestoreChatService.validateVoiceUpload(
          fileName: 'voice.wav',
          fileSize: FirestoreChatService.maxVoiceSizeBytes + 1,
        ),
        throwsA(isA<ChatUploadException>()),
      );
    });
  });
}
