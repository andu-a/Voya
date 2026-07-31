import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'config.dart';
import 'services/auth_service.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => AiChatPageState();
}

class AiChatPageState extends State<AiChatPage> {
  static const accent = Color(0xFF5B85AA);

  final storage = const FlutterSecureStorage();
  final scrollController = ScrollController();
  final textController = TextEditingController();
  final focusNode = FocusNode();

  final List<ChatMessage> messages = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    messages.add(
      const ChatMessage(
        text:
            'Hi! I\'m Voya, your travel assistant. I can help you with information about flights, hotels, destinations, and budget planning. How can I help you?',
        isUser: false,
      ),
    );
  }

  @override
  void dispose() {
    scrollController.dispose();
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<String?> getAccessToken() async {
    String? token = await storage.read(key: 'access_token');
    if (token == null) return null;
    return token;
  }

  Future<void> sendMessage() async {
    final text = textController.text.trim();
    if (text.isEmpty || isLoading) return;

    textController.clear();
    setState(() {
      messages.add(ChatMessage(text: text, isUser: true));
      isLoading = true;
    });
    scrollToBottom();

    try {
      String? token = await getAccessToken();
      if (token == null) {
        addBotMessage('Your session has expired. Please log in again.');
        return;
      }

      var response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/ai/chat/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'prompt': text}),
      );

      // Token expirat — încearcă refresh
      if (response.statusCode == 401) {
        token = await AuthService.refreshAccessToken();
        if (token == null) {
          addBotMessage('Your session has expired. Please log in again.');
          return;
        }
        response = await http.post(
          Uri.parse('${AppConfig.baseUrl}/ai/chat/'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'prompt': text}),
        );
      }

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        final reply =
            data['final_response'] as String? ??
            'Could not generate a response.';
        addBotMessage(reply, sources: parseSources(data['sources']));
      } else if (response.statusCode == 422) {
        final reason =
            data['error'] as String? ??
            'The question is not related to travel.';
        addBotMessage('❌ $reason');
      } else {
        addBotMessage('An error occurred. Please try again.');
      }
    } catch (e) {
      addBotMessage(
        'Could not reach the server. Please check your connection.',
      );
    }
  }

  void addBotMessage(String text, {List<Source> sources = const []}) {
    setState(() {
      isLoading = false;
      messages.add(ChatMessage(text: text, isUser: false, sources: sources));
    });
    scrollToBottom();
  }

  List<Source> parseSources(dynamic rawSources) {
    if (rawSources is! List) return const [];

    final seenUrls = <String>{};
    final sources = <Source>[];
    for (final item in rawSources) {
      if (item is! Map) continue;

      final source = Source.fromJson(item);
      if (source == null || seenUrls.contains(source.url)) continue;

      seenUrls.add(source.url);
      sources.add(source);
    }

    return sources;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: accent,
        elevation: 4,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voya AI',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Travel Assistant',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: messages.length + (isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (isLoading && index == messages.length) {
                  return const TypingIndicator();
                }
                return MessageBubble(message: messages[index]);
              },
            ),
          ),
          buildInputBar(),
        ],
      ),
    );
  }

  Widget buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F8),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: textController,
                  focusNode: focusNode,
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.poppins(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ask something about travel...',
                    hintStyle: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: sendMessage,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLoading ? Colors.grey[300] : accent,
                  shape: BoxShape.circle,
                  boxShadow: isLoading
                      ? []
                      : [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: isLoading ? Colors.grey[500] : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Message Model ───────────────────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final List<Source> sources;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.sources = const [],
  });
}

class Source {
  final String title;
  final String url;
  final String provider;

  const Source({
    required this.title,
    required this.url,
    required this.provider,
  });

  static Source? fromJson(Map<dynamic, dynamic> json) {
    final title = (json['title'] as String? ?? '').trim();
    final url = (json['url'] as String? ?? '').trim();
    final provider = (json['provider'] as String? ?? '').trim();
    if (title.isEmpty || url.isEmpty) return null;

    return Source(
      title: title,
      url: url,
      provider: provider.isEmpty ? 'web' : provider,
    );
  }

  String get displayTitle {
    final uri = Uri.tryParse(url);
    final host = uri?.host.replaceFirst('www.', '');
    if (host != null && host.isNotEmpty) return host;
    return title;
  }
}

// ─── Message Bubble ──────────────────────────────────────────────────────────

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF5B85AA);
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? accent : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    message.text,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: isUser ? Colors.white : const Color(0xFF333333),
                      height: 1.5,
                    ),
                  ),
                ),
                if (!isUser && message.sources.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SourceBar(sources: message.sources),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class SourceBar extends StatelessWidget {
  final List<Source> sources;

  const SourceBar({super.key, required this.sources});

  @override
  Widget build(BuildContext context) {
    final visibleSources = sources.take(4).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF0F5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD8E2EA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.travel_explore_rounded,
                size: 14,
                color: Color(0xFF5B6C7D),
              ),
              const SizedBox(width: 5),
              Text(
                'Sources',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF5B6C7D),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < visibleSources.length; i++)
          SourceChip(index: i + 1, source: visibleSources[i]),
      ],
    );
  }
}

class SourceChip extends StatelessWidget {
  final int index;
  final Source source;

  const SourceChip({super.key, required this.index, required this.source});

  Future<void> openSource() async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: openSource,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 28,
          constraints: const BoxConstraints(maxWidth: 210),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD8E2EA)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$index',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5B85AA),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  source.displayTitle,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF3E4B59),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.open_in_new_rounded,
                size: 12,
                color: Color(0xFF7C8A99),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Typing Indicator ────────────────────────────────────────────────────────

class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => TypingIndicatorState();
}

class TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF5B85AA),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i / 3;
                    final value = ((controller.value - delay) % 1.0);
                    final opacity = value < 0.5
                        ? 0.3 + value * 1.4
                        : 1.0 - (value - 0.5) * 1.4;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Opacity(
                        opacity: opacity.clamp(0.3, 1.0),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF5B85AA),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
