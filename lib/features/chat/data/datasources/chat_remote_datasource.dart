import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/error/exceptions.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

/// Remote data source for chat operations
abstract class ChatRemoteDataSource {
  /// Get all chats for a user
  Future<List<ChatModel>> getUserChats(String userId);

  /// Get messages for a specific chat
  Future<List<MessageModel>> getChatMessages({
    required String matchId,
    required String userId,
    int limit = 50,
    String? beforeId,
  });

  /// Send a message
  Future<MessageModel> sendMessage({
    required String matchId,
    required String senderId,
    required String receiverId,
    required String body,
    String? mediaUrl,
    String? mediaType,
  });

  /// Mark a specific message as read
  Future<void> markMessageAsRead({
    required String messageId,
    required String userId,
  });

  /// Mark all messages in a chat as read
  Future<int> markChatAsRead({
    required String matchId,
    required String userId,
  });

  /// Get total unread message count for a user
  Future<int> getUnreadMessageCount(String userId);

  /// Subscribe to realtime messages for a specific chat
  Stream<MessageModel> subscribeToMessages({
    required String matchId,
    required String userId,
  });
}

/// Implementation of ChatRemoteDataSource using Supabase
class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final SupabaseClient supabaseClient;

  ChatRemoteDataSourceImpl({required this.supabaseClient});

  @override
  Future<List<ChatModel>> getUserChats(String userId) async {
    try {
      // Get all matches for the user
      final matchesResponse = await supabaseClient
          .from('matches')
          .select('*, messages(*)')
          .or('user_id_1.eq.$userId,user_id_2.eq.$userId')
          .order('last_message_at', ascending: false);

      if (matchesResponse.isEmpty) {
        return [];
      }

      final List<ChatModel> chats = [];

      for (final matchData in matchesResponse as List) {
        // Get unread count for this match
        final unreadCount = await _getUnreadCountForMatch(
          matchId: matchData['id'] as String,
          userId: userId,
        );

        // Get last message
        final messagesData = matchData['messages'] as List?;
        MessageModel? lastMessage;

        if (messagesData != null && messagesData.isNotEmpty) {
          lastMessage = MessageModel.fromJson(
            messagesData.first as Map<String, dynamic>,
            userId,
          );
        }

        // Get other user info (this would normally come from a join with profiles)
        final userId1 = matchData['user_id_1'] as String;
        final userId2 = matchData['user_id_2'] as String;
        final otherUserId = userId1 == userId ? userId2 : userId1;

        chats.add(ChatModel(
          matchId: matchData['id'] as String,
          otherUserId: otherUserId,
          lastMessage: lastMessage,
          unreadCount: unreadCount,
          lastMessageAt: matchData['last_message_at'] != null
              ? DateTime.parse(matchData['last_message_at'] as String)
              : null,
        ));
      }

      return chats;
    } catch (e) {
      throw ServerException(message: 'Failed to fetch chats: $e');
    }
  }

  Future<int> _getUnreadCountForMatch({
    required String matchId,
    required String userId,
  }) async {
    try {
      final response = await supabaseClient
          .from('messages')
          .select('id')
          .eq('match_id', matchId)
          .eq('receiver_id', userId)
          .isFilter('read_at', null);

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<List<MessageModel>> getChatMessages({
    required String matchId,
    required String userId,
    int limit = 50,
    String? beforeId,
  }) async {
    try {
      dynamic response;

      if (beforeId != null) {
        // Get messages before a specific message (for pagination)
        final beforeMessage = await supabaseClient
            .from('messages')
            .select('created_at')
            .eq('id', beforeId)
            .single();

        response = await supabaseClient
            .from('messages')
            .select()
            .eq('match_id', matchId)
            .lt('created_at', beforeMessage['created_at'] as String)
            .order('created_at', ascending: false)
            .limit(limit);
      } else {
        response = await supabaseClient
            .from('messages')
            .select()
            .eq('match_id', matchId)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      if (response == null) {
        return [];
      }

      return (response as List)
          .map((json) => MessageModel.fromJson(
                json as Map<String, dynamic>,
                userId,
              ))
          .toList()
          .reversed
          .toList(); // Reverse to show oldest first
    } catch (e) {
      throw ServerException(message: 'Failed to fetch messages: $e');
    }
  }

  @override
  Future<MessageModel> sendMessage({
    required String matchId,
    required String senderId,
    required String receiverId,
    required String body,
    String? mediaUrl,
    String? mediaType,
  }) async {
    try {
      // Call the send_message database function
      final response = await supabaseClient.rpc(
        'send_message',
        params: {
          'p_match_id': matchId,
          'p_sender_id': senderId,
          'p_receiver_id': receiverId,
          'p_body': body,
          'p_media_url': mediaUrl,
          'p_media_type': mediaType,
        },
      );

      if (response == null) {
        throw ServerException(message: 'Failed to send message');
      }

      return MessageModel.fromJson(
        response as Map<String, dynamic>,
        senderId,
      );
    } catch (e) {
      throw ServerException(message: 'Failed to send message: $e');
    }
  }

  @override
  Future<void> markMessageAsRead({
    required String messageId,
    required String userId,
  }) async {
    try {
      await supabaseClient.rpc(
        'mark_message_as_read',
        params: {
          'p_message_id': messageId,
          'p_user_id': userId,
        },
      );
    } catch (e) {
      throw ServerException(message: 'Failed to mark message as read: $e');
    }
  }

  @override
  Future<int> markChatAsRead({
    required String matchId,
    required String userId,
  }) async {
    try {
      final response = await supabaseClient.rpc(
        'mark_chat_as_read',
        params: {
          'p_match_id': matchId,
          'p_user_id': userId,
        },
      );

      return response as int? ?? 0;
    } catch (e) {
      throw ServerException(message: 'Failed to mark chat as read: $e');
    }
  }

  @override
  Future<int> getUnreadMessageCount(String userId) async {
    try {
      final response = await supabaseClient.rpc(
        'get_unread_message_count',
        params: {
          'p_user_id': userId,
        },
      );

      return response as int? ?? 0;
    } catch (e) {
      throw ServerException(message: 'Failed to get unread count: $e');
    }
  }

  @override
  Stream<MessageModel> subscribeToMessages({
    required String matchId,
    required String userId,
  }) {
    return supabaseClient
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('match_id', matchId)
        .order('created_at')
        .map((data) {
          if (data.isEmpty) {
            throw ServerException(message: 'No message received');
          }
          return MessageModel.fromJson(
            data.last,
            userId,
          );
        });
  }
}
