import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_message.dart';
import '../../models/conversation.dart';

/// Mirrors local chat records to the signed-in user's Supabase account.
///
/// Local SQLite remains the primary write path so offline chat keeps working;
/// cloud writes are attempted only while a Supabase session is active.
class SupabaseChatSyncService {
  SupabaseChatSyncService._();

  static SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> syncConversation(Conversation conversation) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;

    await client.from('conversations').upsert({
      'id': conversation.id,
      'user_id': userId,
      'title': conversation.title,
      'mode': conversation.mode,
      'data': conversation.toJson(),
      'created_at': conversation.createdAt.toUtc().toIso8601String(),
      'updated_at': conversation.updatedAt.toUtc().toIso8601String(),
    }, onConflict: 'id,user_id');
    return true;
  }

  static Future<bool> syncMessage(ChatMessage message) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return false;

    await client.from('messages').upsert({
      'id': message.id,
      'conversation_id': message.conversationId,
      'user_id': userId,
      'data': message.toJson(),
      'created_at': message.timestamp.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id,user_id');
    return true;
  }

  /// Returns this user's cloud conversations. Supabase RLS scopes the query to
  /// the active account; callers never supply a user id.
  static Future<List<Map<String, dynamic>>> fetchConversations({String? mode}) async {
    final client = _client;
    if (client?.auth.currentUser == null) return const [];
    var query = client!
        .from('conversations')
        .select('id,title,mode,data,created_at,updated_at');
    if (mode != null && mode.isNotEmpty) {
      query = query.eq('mode', mode);
    }
    final rows = await query.order('updated_at', ascending: false);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  /// Returns messages for a conversation through the authenticated RLS role.
  static Future<List<Map<String, dynamic>>> fetchMessages(
    String conversationId,
  ) async {
    final client = _client;
    if (client?.auth.currentUser == null) return const [];
    final rows = await client!
        .from('messages')
        .select('id,data,created_at,updated_at')
        .eq('conversation_id', conversationId)
        .order('created_at');
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  /// Reads the saved row back through the caller's authenticated RLS context.
  static Future<Map<String, dynamic>?> fetchMessage(String messageId) async {
    final client = _client;
    if (client?.auth.currentUser == null) return null;
    final row = await client!
        .from('messages')
        .select('data')
        .eq('id', messageId)
        .maybeSingle();
    final data = row?['data'];
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Future<void> deleteConversation(String conversationId) async {
    final client = _client;
    if (client?.auth.currentUser == null) return;
    await client!
        .from('conversations')
        .delete()
        .eq('id', conversationId)
        .eq('user_id', client.auth.currentUser!.id);
  }

  static Future<void> deleteMessages(Iterable<String> messageIds) async {
    final client = _client;
    final userId = client?.auth.currentUser?.id;
    final ids = messageIds.where((id) => id.isNotEmpty).toList();
    if (client == null || userId == null || ids.isEmpty) return;
    await client
        .from('messages')
        .delete()
        .eq('user_id', userId)
        .inFilter('id', ids);
  }
}
