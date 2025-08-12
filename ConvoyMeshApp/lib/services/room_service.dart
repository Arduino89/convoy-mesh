import 'package:uuid/uuid.dart';

class RoomService {
  final _uuid = const Uuid();

  bool isValidCode(String code) {
    return RegExp(r'^\d{6}\$').hasMatch(code);
  }

  String generateCode() {
    // Simple 6-digit code from UUID for demo
    final n = _uuid.v4().hashCode.abs() % 1000000;
    return n.toString().padLeft(6, '0');
  }
}
