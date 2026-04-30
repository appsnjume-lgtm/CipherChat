enum AppCallType { audio, video }

enum AppCallStatus { ringing, accepted, rejected, ended, missed }

class CallSessionModel {
  const CallSessionModel({
    required this.id,
    required this.chatId,
    required this.callerId,
    required this.calleeId,
    required this.type,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String chatId;
  final String callerId;
  final String calleeId;
  final AppCallType type;
  final AppCallStatus status;
  final DateTime createdAt;

  bool get isVideo => type == AppCallType.video;

  factory CallSessionModel.fromMap(Map<String, dynamic> map) {
    return CallSessionModel(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      callerId: map['caller_id'] as String,
      calleeId: map['callee_id'] as String,
      type: (map['call_type'] as String? ?? 'audio') == 'video'
          ? AppCallType.video
          : AppCallType.audio,
      status: _statusFromRaw(map['status'] as String? ?? 'ringing'),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  static AppCallStatus _statusFromRaw(String value) {
    switch (value) {
      case 'accepted':
        return AppCallStatus.accepted;
      case 'rejected':
        return AppCallStatus.rejected;
      case 'ended':
        return AppCallStatus.ended;
      case 'missed':
        return AppCallStatus.missed;
      case 'ringing':
      default:
        return AppCallStatus.ringing;
    }
  }
}

class CallSignalModel {
  const CallSignalModel({
    required this.id,
    required this.callId,
    required this.senderId,
    required this.eventType,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String callId;
  final String senderId;
  final String eventType;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  factory CallSignalModel.fromMap(Map<String, dynamic> map) {
    return CallSignalModel(
      id: map['id'] as String,
      callId: map['call_id'] as String,
      senderId: map['sender_id'] as String,
      eventType: map['event_type'] as String,
      payload: Map<String, dynamic>.from(map['payload'] as Map? ?? const {}),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}
