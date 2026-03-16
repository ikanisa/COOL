import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/supabase_client_provider.dart';

class ChatMessage {
  const ChatMessage({required this.role, required this.content});
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class AssistantState {
  const AssistantState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;

  AssistantState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
  }) {
    return AssistantState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class AssistantNotifier extends StateNotifier<AssistantState> {
  AssistantNotifier(this._client) : super(const AssistantState());

  final SupabaseClient _client;

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(role: 'user', content: text.trim());
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      error: null,
    );

    try {
      final response = await _client.functions.invoke(
        'chat-with-finances',
        body: {
          'message': text.trim(),
          'history': state.messages.map((m) => m.toJson()).toList(),
        },
      );

      if (response.data != null && response.data['success'] == true) {
        final reply = response.data['data']['reply'] as String;
        final assistantMessage = ChatMessage(role: 'assistant', content: reply);
        state = state.copyWith(
          messages: [...state.messages, assistantMessage],
          isLoading: false,
        );
      } else {
        throw Exception('Failed to get response from assistant');
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Assistant is currently offline. Please try again.',
      );
    }
  }

  void clearHistory() {
    state = const AssistantState();
  }
}

final assistantProvider = StateNotifierProvider<AssistantNotifier, AssistantState>((ref) {
  return AssistantNotifier(ref.read(supabaseClientProvider));
});
