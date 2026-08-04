class MediaAsset {
  final String id;
  final String kind;
  final int sizeBytes;
  final bool hasThumbnail;

  MediaAsset({required this.id, required this.kind, required this.sizeBytes, required this.hasThumbnail});

  factory MediaAsset.fromJson(Map<String, dynamic> json) => MediaAsset(
        id: json['id'],
        kind: json['kind'],
        sizeBytes: json['size_bytes'] ?? 0,
        hasThumbnail: json['has_thumbnail'] ?? false,
      );
}

class Category {
  final String id;
  final String scope;
  final String encName;
  final String createdBy;
  final DateTime createdAt;
  String? decryptedName;

  Category({required this.id, required this.scope, required this.encName, required this.createdBy, required this.createdAt});

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'],
        scope: json['scope'],
        encName: json['enc_name'],
        createdBy: json['created_by'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class VaultEntry {
  final String id;
  final String contentType; // text | photo | video
  final String? categoryId;
  final String authorId;
  final String authorRole;
  final String encPayload;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavoriteMine;
  final int viewCount;
  final List<MediaAsset> mediaAssets;
  String? decryptedText;

  VaultEntry({
    required this.id,
    required this.contentType,
    required this.categoryId,
    required this.authorId,
    required this.authorRole,
    required this.encPayload,
    required this.createdAt,
    required this.updatedAt,
    required this.isFavoriteMine,
    required this.viewCount,
    required this.mediaAssets,
  });

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'],
        contentType: json['content_type'],
        categoryId: json['category_id'],
        authorId: json['author_id'],
        authorRole: json['author_role'],
        encPayload: json['enc_payload'],
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
        isFavoriteMine: json['is_favorite_mine'] ?? false,
        viewCount: json['view_count'] ?? 0,
        mediaAssets: (json['media_assets'] as List<dynamic>? ?? []).map((e) => MediaAsset.fromJson(e)).toList(),
      );
}

class ConsentRequestModel {
  final String id;
  final String entryId;
  final String action; // edit | delete
  final String requestedBy;
  final String status;
  final DateTime createdAt;

  ConsentRequestModel({required this.id, required this.entryId, required this.action, required this.requestedBy, required this.status, required this.createdAt});

  factory ConsentRequestModel.fromJson(Map<String, dynamic> json) => ConsentRequestModel(
        id: json['id'],
        entryId: json['entry_id'],
        action: json['action'],
        requestedBy: json['requested_by'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class ReactionBreakdown {
  final String emoji;
  final int husbandCount;
  final int wifeCount;
  final bool reactedByMe;

  ReactionBreakdown({required this.emoji, required this.husbandCount, required this.wifeCount, required this.reactedByMe});

  factory ReactionBreakdown.fromJson(Map<String, dynamic> json) => ReactionBreakdown(
        emoji: json['emoji'],
        husbandCount: json['husband_count'],
        wifeCount: json['wife_count'],
        reactedByMe: json['reacted_by_me'],
      );
}

class CommentModel {
  final String id;
  final String targetType;
  final String targetId;
  final String authorId;
  final String authorRole;
  final String encPayload;
  final DateTime createdAt;
  final int heartCount;
  final bool heartedByMe;
  String? decryptedText;

  CommentModel({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.authorId,
    required this.authorRole,
    required this.encPayload,
    required this.createdAt,
    required this.heartCount,
    required this.heartedByMe,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) => CommentModel(
        id: json['id'],
        targetType: json['target_type'],
        targetId: json['target_id'],
        authorId: json['author_id'],
        authorRole: json['author_role'],
        encPayload: json['enc_payload'],
        createdAt: DateTime.parse(json['created_at']),
        heartCount: json['heart_count'] ?? 0,
        heartedByMe: json['hearted_by_me'] ?? false,
      );
}

class ChatMessageModel {
  final String id;
  final String senderId;
  final String senderRole;
  final String contentType;
  final String? encPayload;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final String? mediaAssetId;
  String? decryptedText;

  ChatMessageModel({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.contentType,
    required this.encPayload,
    required this.createdAt,
    required this.deliveredAt,
    required this.readAt,
    required this.mediaAssetId,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) => ChatMessageModel(
        id: json['id'],
        senderId: json['sender_id'],
        senderRole: json['sender_role'],
        contentType: json['content_type'],
        encPayload: json['enc_payload'],
        createdAt: DateTime.parse(json['created_at']),
        deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at']) : null,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at']) : null,
        mediaAssetId: json['media_asset_id'],
      );
}

class WishlistItemModel {
  final String id;
  final String ownerId;
  final String? categoryId;
  final String encPayload;
  final bool isFulfilled;
  final DateTime createdAt;
  String? decryptedText;

  WishlistItemModel({required this.id, required this.ownerId, required this.categoryId, required this.encPayload, required this.isFulfilled, required this.createdAt});

  factory WishlistItemModel.fromJson(Map<String, dynamic> json) => WishlistItemModel(
        id: json['id'],
        ownerId: json['owner_id'],
        categoryId: json['category_id'],
        encPayload: json['enc_payload'],
        isFulfilled: json['is_fulfilled'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class PhraseModel {
  final String id;
  final String direction; // husband_to_wife | wife_to_husband
  final String authorId;
  final String encPayload;
  final int? ratingHusband;
  final int? ratingWife;
  final DateTime createdAt;
  String? decryptedText;

  PhraseModel({
    required this.id,
    required this.direction,
    required this.authorId,
    required this.encPayload,
    required this.ratingHusband,
    required this.ratingWife,
    required this.createdAt,
  });

  factory PhraseModel.fromJson(Map<String, dynamic> json) => PhraseModel(
        id: json['id'],
        direction: json['direction'],
        authorId: json['author_id'],
        encPayload: json['enc_payload'],
        ratingHusband: json['rating_husband'],
        ratingWife: json['rating_wife'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class ProfileModel {
  final String spouseId;
  final String role;
  final String? encDisplayName;
  final String? encBio;
  final String? encAnniversaryDates;
  final String? profilePhotoAssetId;
  String? decryptedName;
  String? decryptedBio;

  ProfileModel({required this.spouseId, required this.role, this.encDisplayName, this.encBio, this.encAnniversaryDates, this.profilePhotoAssetId});

  factory ProfileModel.fromJson(Map<String, dynamic> json) => ProfileModel(
        spouseId: json['spouse_id'],
        role: json['role'],
        encDisplayName: json['enc_display_name'],
        encBio: json['enc_bio'],
        encAnniversaryDates: json['enc_anniversary_dates'],
        profilePhotoAssetId: json['profile_photo_asset_id'],
      );
}

class AuditLogEntryModel {
  final String id;
  final String? actorId;
  final String action;
  final String? targetType;
  final String? targetId;
  final String? detail;
  final DateTime createdAt;

  AuditLogEntryModel({required this.id, this.actorId, required this.action, this.targetType, this.targetId, this.detail, required this.createdAt});

  factory AuditLogEntryModel.fromJson(Map<String, dynamic> json) => AuditLogEntryModel(
        id: json['id'],
        actorId: json['actor_id'],
        action: json['action'],
        targetType: json['target_type'],
        targetId: json['target_id'],
        detail: json['detail'],
        createdAt: DateTime.parse(json['created_at']),
      );
}

class DeviceModel {
  final String id;
  final String deviceName;
  final String role;
  final bool isThisDevice;
  final DateTime createdAt;
  final DateTime lastSeenAt;

  DeviceModel({
    required this.id,
    required this.deviceName,
    required this.role,
    required this.isThisDevice,
    required this.createdAt,
    required this.lastSeenAt,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) => DeviceModel(
        id: json['id'],
        deviceName: json['device_name'],
        role: json['role'],
        isThisDevice: json['is_this_device'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        lastSeenAt: DateTime.parse(json['last_seen_at']),
      );
}
