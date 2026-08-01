import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AttendancePhotoOptimizationException implements Exception {
  const AttendancePhotoOptimizationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OptimizedAttendancePhoto {
  const OptimizedAttendancePhoto(this.path);

  final String path;

  Future<void> delete() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

class AttendancePhotoOptimizer {
  static const int _targetBytes = 900 * 1024;
  static const int _maximumBytes = 1024 * 1024;

  Future<OptimizedAttendancePhoto> optimize(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const AttendancePhotoOptimizationException(
        'Foto absensi tidak ditemukan. Ambil foto kembali.',
      );
    }

    final directory = Directory(
      path.join((await getTemporaryDirectory()).path, 'attendance_uploads'),
    );
    await directory.create(recursive: true);
    final id = const Uuid().v4();
    final targetPath = path.join(directory.path, '$id.jpg');
    final sourceBytes = await source.readAsBytes();
    final encoded = await Isolate.run(
      () => AttendancePhotoOptimizer.encodeForUpload(sourceBytes),
    );
    if (encoded == null) {
      throw const AttendancePhotoOptimizationException(
        'Foto belum dapat diproses. Ambil foto kembali.',
      );
    }
    if (encoded.length > _maximumBytes) {
      throw const AttendancePhotoOptimizationException(
        'Ukuran foto masih terlalu besar. Ambil foto di tempat yang lebih terang.',
      );
    }

    await File(targetPath).writeAsBytes(encoded, flush: true);
    return OptimizedAttendancePhoto(targetPath);
  }

  static Uint8List? encodeForUpload(Uint8List sourceBytes) {
    image.Image? decoded;
    try {
      decoded = image.decodeImage(sourceBytes);
    } catch (_) {
      return null;
    }
    if (decoded == null) return null;

    decoded = image.bakeOrientation(decoded);
    decoded.exif.clear();
    decoded = _resizeToMaximum(decoded, 960);
    var encoded = image.encodeJpg(
      decoded,
      quality: 72,
      chroma: image.JpegChroma.yuv420,
    );
    if (encoded.length <= _targetBytes) return encoded;

    decoded = _resizeToMaximum(decoded, 720);
    encoded = image.encodeJpg(
      decoded,
      quality: 58,
      chroma: image.JpegChroma.yuv420,
    );
    return encoded;
  }
}

image.Image _resizeToMaximum(image.Image source, int maximumDimension) {
  if (source.width <= maximumDimension && source.height <= maximumDimension) {
    return source;
  }
  return source.width >= source.height
      ? image.copyResize(
          source,
          width: maximumDimension,
          interpolation: image.Interpolation.average,
        )
      : image.copyResize(
          source,
          height: maximumDimension,
          interpolation: image.Interpolation.average,
        );
}
