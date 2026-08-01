import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:tjoerah_mobile/features/attendance/services/attendance_photo_optimizer.dart';

void main() {
  test('attendance photo encoder returns a compact JPEG without EXIF', () {
    final source = image.Image(width: 1400, height: 1050);
    image.fill(source, color: image.ColorRgb8(72, 90, 108));
    source.exif.imageIfd.orientation = 1;

    final encoded = AttendancePhotoOptimizer.encodeForUpload(
      image.encodeJpg(source, quality: 100),
    );

    expect(encoded, isNotNull);
    expect(encoded!.length, lessThanOrEqualTo(1024 * 1024));
    final decoded = image.decodeJpg(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(960));
    expect(decoded.height, lessThanOrEqualTo(960));
    expect(decoded.exif.isEmpty, isTrue);
  });

  test('attendance photo encoder rejects invalid bytes', () {
    expect(
      AttendancePhotoOptimizer.encodeForUpload(Uint8List.fromList([1, 2, 3])),
      isNull,
    );
  });
}
