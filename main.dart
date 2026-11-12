
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const admobBanner = String.fromEnvironment('ADMOB_BANNER_ID');
const admobInterstitial = String.fromEnvironment('ADMOB_INTERSTITIAL_ID');
const admobRewarded = String.fromEnvironment('ADMOB_REWARDED_ID');
const mediaBucket = 'chat-media';
const maxUploadBytes = 45 * 1024 * 1024;

final supabase = Supabase.instance.client;
final auth = supabase.auth;

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await PushService.register();
  } catch (_) {}
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF0B1220),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ChatWaveApp());
}

class ChatWaveApp extends StatelessWidget {
  const ChatWaveApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ChatWave',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B1220),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF23D3B0),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF101B2D),
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFF172438),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: auth.onAuthStateChange,
        builder: (context, snapshot) =>
            auth.currentSession == null ? const SignInPage() : const HomePage(),
      );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool busy = false;
  String? error;

  Future<void> google() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.chatwave.app://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      setState(() => error = e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF15334A),
                Color(0xFF0B1220),
                Color(0xFF10172B),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF23D3B0).withOpacity(.14),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Icon(
                        Icons.forum_rounded,
                        size: 56,
                        color: Color(0xFF23D3B0),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'ChatWave',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Your people. Your conversations. One wave.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 42),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: busy ? null : google,
                        icon: const Icon(Icons.login),
                        label: Text(
                          busy ? 'Opening Google…' : 'Continue with Google',
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    const SizedBox(height: 32),
                    const Text(
                      'Developed by Majid Aslam',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class PushService {
  static Future<void> register() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null && auth.currentUser != null) await _save(token);
    messaging.onTokenRefresh.listen(_save);
    FirebaseMessaging.onMessage.listen((message) {});
  }

  static Future<void> _save(String token) async {
    final uid = auth.currentUser?.id;
    if (uid == null) return;
    await supabase.from('device_tokens').upsert(
      {
        'user_id': uid,
        'platform': 'android',
        'push_token': token,
      },
      onConflict: 'push_token',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  String peopleQuery = '';
  List<Map<String, dynamic>> conversations = [];
  List<Map<String, dynamic>> people = [];
  bool loading = true;
  RealtimeChannel? channel;
  BannerAd? banner;
  bool bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    _presence(true);
    _listen();
    _banner();
    PushService.register();
  }

  @override
  void dispose() {
    channel?.unsubscribe();
    banner?.dispose();
    _presence(false);
    super.dispose();
  }

  void _banner() {
    if (admobBanner.isEmpty) return;
    banner = BannerAd(
      adUnitId: admobBanner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          banner = null;
        },
      ),
    )..load();
  }

  void _listen() {
    channel = supabase.channel('home-${auth.currentUser!.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        callback: (_) {
          _load();
        },
      ).subscribe();
  }

  Future<void> _presence(bool online) async {
    final uid = auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('user_presence').upsert({
        'user_id': uid,
        'is_online': online,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final uid = auth.currentUser!.id;
      final memberships = await supabase
          .from('conversation_members')
          .select('conversation_id')
          .eq('user_id', uid);
      final settings = await supabase
          .from('conversation_user_settings')
          .select('conversation_id,hidden_at')
          .eq('user_id', uid);
      final hidden = settings
          .where((e) => e['hidden_at'] != null)
          .map((e) => e['conversation_id'] as String)
          .toSet();
      final ids = memberships
          .map((e) => e['conversation_id'] as String)
          .where((id) => !hidden.contains(id))
          .toList();

      if (ids.isEmpty) {
        conversations = [];
      } else {
        final rows = await supabase
            .from('conversations')
            .select()
            .inFilter('id', ids)
            .order('updated_at', ascending: false);
        final members = await supabase
            .from('conversation_members')
            .select('conversation_id,user_id,member_role')
            .inFilter('conversation_id', ids);
        final profileRows = await supabase
            .from('profiles')
            .select('id,username,display_name,avatar_url,about');
        final messages = await supabase
            .from('messages')
            .select('conversation_id,body,message_type,created_at,sender_id')
            .inFilter('conversation_id', ids)
            .order('created_at', ascending: false);

        final profiles = {for (final p in profileRows) p['id']: p};
        conversations = rows.map((c) {
          final cm = members
              .where((m) => m['conversation_id'] == c['id'])
              .toList();
          final others = cm
              .where((m) => m['user_id'] != uid)
              .map((m) => profiles[m['user_id']])
              .where((p) => p != null)
              .toList();
          final last = messages
              .where((m) => m['conversation_id'] == c['id'])
              .firstOrNull;
          final title = c['kind'] == 'group'
              ? (c['title'] ?? 'Group')
              : (others.isNotEmpty
                  ? (others.first['display_name'] ??
                      others.first['username'] ??
                      'Chat')
                  : 'Chat');
          return <String, dynamic>{
            ...c,
            'title_display': title,
            'avatar': others.isNotEmpty ? others.first['avatar_url'] : null,
            'members': cm,
            'last': last,
            'other_user': others.isNotEmpty ? others.first : null,
          };
        }).where((c) => true).toList();

        conversations.sort((a, b) {
          final aa = (a['last']?['created_at'] ?? a['updated_at']) as String;
          final bb = (b['last']?['created_at'] ?? b['updated_at']) as String;
          return bb.compareTo(aa);
        });
      }

      people = await supabase
          .from('profiles')
          .select('id,username,display_name,avatar_url,about')
          .neq('id', uid)
          .order('display_name')
          .limit(100);
    } catch (e) {
      if (mounted) _snack('Could not load chats: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _newDirect(Map<String, dynamic> person) async {
    try {
      final id = await supabase.rpc(
        'create_direct_conversation',
        params: {'recipient_id': person['id']},
      );
      await _load();
      if (!mounted) return;
      final c = conversations.firstWhere((x) => x['id'] == id);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(conversation: c)),
      );
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _newGroup() async {
    final title = TextEditingController();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Create a group'),
          content: SizedBox(
            width: 380,
            height: 430,
            child: Column(
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Group name'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: people
                        .map(
                          (p) => CheckboxListTile(
                            value: selected.contains(p['id']),
                            title: Text(
                              p['display_name'] ?? p['username'] ?? 'User',
                            ),
                            subtitle: Text('@${p['username'] ?? ''}'),
                            onChanged: (v) => setD(
                              () => v == true
                                  ? selected.add(p['id'])
                                  : selected.remove(p['id']),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    if (title.text.trim().length < 2 || selected.isEmpty) {
      _snack('Group name and at least one member required');
      return;
    }
    try {
      final id = await supabase.rpc(
        'create_group_conversation',
        params: {
          'group_title': title.text.trim(),
          'member_ids': selected.toList(),
        },
      );
      await _load();
      if (!mounted) return;
      final c = conversations.firstWhere((x) => x['id'] == id);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(conversation: c)),
      );
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _profile() async {
    final p = await supabase
        .from('profiles')
        .select()
        .eq('id', auth.currentUser!.id)
        .maybeSingle();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfilePage(profile: p ?? {})),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              const Icon(Icons.waves, color: Color(0xFF23D3B0)),
              const SizedBox(width: 9),
              const Text(
                'ChatWave',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                onPressed: _newGroup,
                icon: const Icon(Icons.group_add_outlined),
              ),
              IconButton(
                onPressed: _profile,
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(child: tab == 0 ? _chats() : _people()),
            if (banner != null && bannerLoaded)
              SizedBox(
                height: banner!.size.height.toDouble(),
                width: banner!.size.width.toDouble(),
                child: AdWidget(ad: banner!),
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (v) => setState(() => tab = v),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              label: 'People',
            ),
          ],
        ),
        floatingActionButton: tab == 0
            ? FloatingActionButton(
                onPressed: _newGroup,
                backgroundColor: const Color(0xFF23D3B0),
                foregroundColor: const Color(0xFF07151A),
                child: const Icon(Icons.group_add),
              )
            : null,
      );

  Widget _chats() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (conversations.isEmpty) {
      return const _EmptyState(
        icon: Icons.forum_outlined,
        title: 'Your chats start here',
        subtitle: 'Find someone in People or create a group.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (ctx, i) {
          final c = conversations[i];
          final last = c['last'];
          return Card(
            color: const Color(0xFF121F32),
            child: ListTile(
              leading: Avatar(url: c['avatar'], label: c['title_display']),
              title: Text(
                c['title_display'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                last == null
                    ? 'Start a conversation'
                    : (last['message_type'] == 'text'
                        ? last['body']
                        : '📎 ${last['message_type']}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatPage(conversation: c)),
              ).then((_) => _load()),
              onLongPress: () => _conversationMenu(c),
            ),
          );
        },
      ),
    );
  }

  Widget _people() {
    if (loading) return const Center(child: CircularProgressIndicator());
    final filtered = people
        .where(
          (p) =>
              ('${p['display_name'] ?? ''} ${p['username'] ?? ''}')
                  .toLowerCase()
                  .contains(peopleQuery.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            onChanged: (v) => setState(() => peopleQuery = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search people by name or @username',
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const _EmptyState(
                  icon: Icons.person_search,
                  title: 'No people found',
                  subtitle: 'Try another name or username.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return Card(
                      color: const Color(0xFF121F32),
                      child: ListTile(
                        leading: Avatar(
                          url: p['avatar_url'],
                          label: p['display_name'] ?? p['username'],
                        ),
                        title: Text(p['display_name'] ?? 'ChatWave user'),
                        subtitle: Text('@${p['username'] ?? 'new-user'}'),
                        trailing: const Icon(
                          Icons.chat_bubble_outline,
                          color: Color(0xFF23D3B0),
                        ),
                        onTap: () => _newDirect(p),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _conversationMenu(Map<String, dynamic> c) async {
    final group = c['kind'] == 'group';
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_off),
              title: const Text('Hide chat for me'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            if (group && c['created_by'] == auth.currentUser!.id)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete group'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'hide') {
        await supabase.rpc(
          'hide_conversation',
          params: {'p_conversation_id': c['id']},
        );
      } else {
        await supabase.rpc(
          'delete_group_conversation',
          params: {'p_conversation_id': c['id']},
        );
      }
      _load();
    } catch (e) {
      _snack('$e');
    }
  }
}

class ChatPage extends StatefulWidget {
  final Map<String, dynamic> conversation;
  const ChatPage({super.key, required this.conversation});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  List<Map<String, dynamic>> messages = [];
  bool loading = true, recording = false, sending = false;
  int sentCount = 0;
  String typing = '';
  Timer? typingTimer;
  RealtimeChannel? channel;
  InterstitialAd? interstitial;

  String get cid => widget.conversation['id'];
  String get uid => auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
    _markRead();
    if (admobInterstitial.isNotEmpty) {
      InterstitialAd.load(
        adUnitId: admobInterstitial,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (a) => interstitial = a,
          onAdFailedToLoad: (_) {},
        ),
      );
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    recorder.dispose();
    player.dispose();
    typingTimer?.cancel();
    channel?.unsubscribe();
    interstitial?.dispose();
    super.dispose();
  }

  void _subscribe() {
    channel = supabase.channel('chat-$cid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: cid,
        ),
        callback: (_) {
          _load();
          _markRead();
        },
      ).onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'typing_status',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: cid,
        ),
        callback: (_) {
          _typing();
        },
      ).subscribe();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from('messages')
          .select('*, message_receipts(user_id,read_at)')
          .eq('conversation_id', cid)
          .isFilter('deleted_at', null)
          .order('created_at');
      messages = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _snack('$e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _markRead() async {
    try {
      final others = await supabase
          .from('messages')
          .select('id,sender_id')
          .eq('conversation_id', cid)
          .neq('sender_id', uid)
          .isFilter('deleted_at', null);
      for (final m in others) {
        await supabase.from('message_receipts').upsert({
          'message_id': m['id'],
          'user_id': uid,
          'delivered_at': DateTime.now().toUtc().toIso8601String(),
          'read_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
    } catch (_) {}
  }

  Future<void> _typing() async {
    try {
      final rows = await supabase
          .from('typing_status')
          .select('user_id,is_typing')
          .eq('conversation_id', cid)
          .neq('user_id', uid)
          .eq('is_typing', true);
      final profiles = await supabase
          .from('profiles')
          .select('id,display_name')
          .inFilter('id', rows.map((e) => e['user_id']).toList());
      if (mounted) {
        setState(
          () => typing = profiles.isEmpty
              ? ''
              : '${profiles.first['display_name'] ?? 'Someone'} is typing…',
        );
      }
    } catch (_) {}
  }

  Future<void> _setTyping(bool v) async {
    try {
      await supabase.from('typing_status').upsert({
        'conversation_id': cid,
        'user_id': uid,
        'is_typing': v,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  void _snack(String s) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s)));
    }
  }

  Future<void> _sendText() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    setState(() => sending = true);
    input.clear();
    await _setTyping(false);
    try {
      final inserted = await supabase
          .from('messages')
          .insert({
            'conversation_id': cid,
            'sender_id': uid,
            'body': body,
            'message_type': 'text',
          })
          .select('id')
          .single();
      try {
        await supabase.functions.invoke(
          'send-chat-notification',
          body: {'conversation_id': cid, 'message_id': inserted['id']},
        );
      } catch (_) {}
      await _load();
      _toBottom();
      sentCount++;
      if (sentCount % 10 == 0 && interstitial != null) {
        final ad = interstitial!;
        interstitial = null;
        ad.show();
        if (admobInterstitial.isNotEmpty) {
          InterstitialAd.load(
            adUnitId: admobInterstitial,
            request: const AdRequest(),
            adLoadCallback: InterstitialAdLoadCallback(
              onAdLoaded: (next) => interstitial = next,
              onAdFailedToLoad: (_) {},
            ),
          );
        }
      }
    } catch (e) {
      input.text = body;
      _snack('Message not sent: $e');
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _upload(
    Uint8List bytes,
    String filename,
    String type,
  ) async {
    if (bytes.length > maxUploadBytes) {
      _snack('File limit is 45 MB');
      return;
    }
    setState(() => sending = true);
    try {
      final safe = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '$uid/$cid/${DateTime.now().microsecondsSinceEpoch}_$safe';
      await supabase.storage.from(mediaBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType:
                  lookupMimeType(filename) ?? 'application/octet-stream',
              upsert: false,
            ),
          );
      final inserted = await supabase
          .from('messages')
          .insert({
            'conversation_id': cid,
            'sender_id': uid,
            'body': filename,
            'message_type': type,
            'media_path': path,
          })
          .select('id')
          .single();
      try {
        await supabase.functions.invoke(
          'send-chat-notification',
          body: {'conversation_id': cid, 'message_id': inserted['id']},
        );
      } catch (_) {}
      await _load();
      _toBottom();
    } catch (e) {
      _snack('Upload failed: $e');
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> _pickFile({bool imageOnly = false}) async {
    try {
      if (imageOnly) {
        final x = await ImagePicker()
            .pickImage(source: ImageSource.gallery, imageQuality: 88);
        if (x == null) return;
        await _upload(await x.readAsBytes(), x.name, 'image');
      } else {
        final r = await FilePicker.platform.pickFiles(withData: true);
        if (r == null) return;
        final f = r.files.single;
        final b = f.bytes ??
            (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (b == null) return;
        final mt = lookupMimeType(f.name) ?? '';
        final type = mt.startsWith('video/')
            ? 'video'
            : mt.startsWith('image/')
                ? 'image'
                : 'file';
        await _upload(b, f.name, type);
      }
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _recordToggle() async {
    try {
      if (!recording) {
        if (!await recorder.hasPermission()) {
          _snack('Microphone permission is required');
          return;
        }
        final dir = Directory.systemTemp;
        final path =
            '${dir.path}/chatwave_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() => recording = true);
      } else {
        final path = await recorder.stop();
        setState(() => recording = false);
        if (path != null) {
          final bytes = await File(path).readAsBytes();
          await _upload(
            bytes,
            'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            'voice',
          );
          await File(path).delete();
        }
      }
    } catch (e) {
      setState(() => recording = false);
      _snack('Voice note error: $e');
    }
  }

  Future<void> _play(Map<String, dynamic> m) async {
    try {
      final url = await supabase.storage
          .from(mediaBucket)
          .createSignedUrl(m['media_path'], 3600);
      await player.stop();
      await player.play(UrlSource(url));
    } catch (e) {
      _snack('Cannot play media: $e');
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _messageMenu(Map<String, dynamic> m) async {
    if (m['sender_id'] != uid) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await supabase.from('messages').update({
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'body': 'Message deleted',
        'media_path': null,
      }).eq('id', m['id']);
      await _load();
    } catch (e) {
      _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.conversation['title_display'] ??
        widget.conversation['title'] ??
        'Chat';
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              typing.isEmpty
                  ? (widget.conversation['kind'] == 'group'
                      ? 'Group conversation'
                      : 'ChatWave chat')
                  : typing,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF23D3B0),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'hide') {
                await supabase.rpc(
                  'hide_conversation',
                  params: {'p_conversation_id': cid},
                );
                if (mounted) Navigator.pop(context);
              }
              if (v == 'delete') {
                try {
                  await supabase.rpc(
                    'delete_group_conversation',
                    params: {'p_conversation_id': cid},
                  );
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  _snack('$e');
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'hide', child: Text('Hide chat')),
              if (widget.conversation['kind'] == 'group' &&
                  widget.conversation['created_by'] == uid)
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete group'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0xFF12263A),
            child: const Text(
              '🔒 Messages and calls are protected in transit. This chat is not end-to-end encrypted.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const _EmptyState(
                        icon: Icons.mark_chat_unread_outlined,
                        title: 'Say hello',
                        subtitle: 'Your conversation begins with a message.',
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.all(14),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) => _bubble(messages[i]),
                      ),
          ),
          if (recording)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                '● Recording… tap microphone to send',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['sender_id'] == uid;
    final type = m['message_type'];
    final deleted = m['deleted_at'] != null;
    final receipts = (m['message_receipts'] as List? ?? []);
    final seen = receipts.any((r) => r['read_at'] != null);

    return GestureDetector(
      onLongPress: () => _messageMenu(m),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: mine
                ? const Color(0xFF145C58)
                : const Color(0xFF1A2A40),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(mine ? 17 : 4),
              bottomRight: Radius.circular(mine ? 4 : 17),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!deleted && type == 'image')
                _imagePreview(m)
              else if (!deleted &&
                  (type == 'voice' || type == 'video' || type == 'file'))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type == 'voice'
                          ? Icons.play_circle_fill
                          : type == 'video'
                              ? Icons.video_file
                              : Icons.insert_drive_file,
                      color: const Color(0xFF23D3B0),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        m['body'] ?? type,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          type == 'voice' ? _play(m) : _openMedia(m),
                      icon: Icon(
                        type == 'voice' ? Icons.play_arrow : Icons.open_in_new,
                        size: 19,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  deleted ? 'This message was deleted' : m['body'] ?? '',
                  style: TextStyle(
                    color: deleted ? Colors.white38 : Colors.white,
                    fontStyle:
                        deleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time(m['created_at']),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white54,
                    ),
                  ),
                  if (mine && type == 'text')
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        seen ? Icons.done_all : Icons.done,
                        size: 13,
                        color: seen
                            ? const Color(0xFF48B8FF)
                            : Colors.white54,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePreview(Map<String, dynamic> m) => FutureBuilder<String>(
        future: supabase.storage
            .from(mediaBucket)
            .createSignedUrl(m['media_path'], 3600),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              width: 180,
              height: 90,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return GestureDetector(
            onTap: () => launchUrl(
              Uri.parse(snapshot.data!),
              mode: LaunchMode.externalApplication,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                snapshot.data!,
                width: 220,
                height: 170,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image),
              ),
            ),
          );
        },
      );

  Future<void> _openMedia(Map<String, dynamic> m) async {
    try {
      final url = await supabase.storage
          .from(mediaBucket)
          .createSignedUrl(m['media_path'], 3600);
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      _snack('Could not open attachment: $e');
    }
  }

  Widget _composer() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 9),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _pickFile(imageOnly: true),
                icon: const Icon(
                  Icons.photo_outlined,
                  color: Color(0xFF23D3B0),
                ),
              ),
              IconButton(
                onPressed: () => _pickFile(),
                icon: const Icon(Icons.attach_file),
              ),
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) {
                    _setTyping(true);
                    typingTimer?.cancel();
                    typingTimer = Timer(
                      const Duration(seconds: 2),
                      () => _setTyping(false),
                    );
                  },
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _recordToggle,
                icon: Icon(
                  recording ? Icons.stop_circle : Icons.mic,
                  color: recording
                      ? Colors.redAccent
                      : const Color(0xFF23D3B0),
                ),
              ),
              IconButton(
                onPressed: sending ? null : _sendText,
                icon: const Icon(
                  Icons.send_rounded,
                  color: Color(0xFF23D3B0),
                ),
              ),
            ],
          ),
        ),
      );
}

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic> profile;
  const ProfilePage({super.key, required this.profile});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final name =
      TextEditingController(text: widget.profile['display_name'] ?? '');
  late final username =
      TextEditingController(text: widget.profile['username'] ?? '');
  late final about =
      TextEditingController(text: widget.profile['about'] ?? '');
  String? avatar;
  bool saving = false;
  RewardedAd? rewarded;

  @override
  void initState() {
    super.initState();
    avatar = widget.profile['avatar_url'];
    _loadRewarded();
  }

  void _loadRewarded() {
    if (admobRewarded.isEmpty) return;
    RewardedAd.load(
      adUnitId: admobRewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => rewarded = ad,
        onAdFailedToLoad: (_) => rewarded = null,
      ),
    );
  }

  void _watchAd() {
    final ad = rewarded;
    if (ad == null) {
      _snack('Ad is not ready yet');
      _loadRewarded();
      return;
    }
    rewarded = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadRewarded();
      },
    );
    ad.show(
      onUserEarnedReward: (_, __) =>
          _snack('Thanks for supporting ChatWave!'),
    );
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    about.dispose();
    rewarded?.dispose();
    super.dispose();
  }

  Future<void> _photo() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > maxUploadBytes) return;
    final uid = auth.currentUser!.id;
    final path = '$uid/avatars/profile.jpg';
    try {
      await supabase.storage.from(mediaBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      avatar = await supabase.storage
          .from(mediaBucket)
          .createSignedUrl(path, 60 * 60 * 24 * 365);
      setState(() {});
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _save() async {
    if (username.text.trim().isNotEmpty &&
        !RegExp(r'^[a-zA-Z0-9_]{3,24}$')
            .hasMatch(username.text.trim())) {
      _snack('Username: 3–24 letters, numbers or underscore');
      return;
    }
    setState(() => saving = true);
    try {
      await supabase.from('profiles').update({
        'display_name': name.text.trim(),
        'username': username.text.trim().isEmpty
            ? null
            : username.text.trim().toLowerCase(),
        'about': about.text.trim(),
        'avatar_url': avatar,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', auth.currentUser!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('Profile not saved: $e');
    }
    if (mounted) setState(() => saving = false);
  }

  void _snack(String s) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(s)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My profile')),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Center(
              child: GestureDetector(
                onTap: _photo,
                child: Stack(
                  children: [
                    Avatar(url: avatar, label: name.text, size: 104),
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        backgroundColor: Color(0xFF23D3B0),
                        child: Icon(Icons.camera_alt, color: Colors.black),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Display name'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: username,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: about,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'About'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save profile'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _watchAd,
              child: const Text('Watch a rewarded ad'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => auth.signOut(),
              child: const Text('Log out'),
            ),
          ],
        ),
      );
}

class Avatar extends StatelessWidget {
  final String? url;
  final String? label;
  final double size;
  const Avatar({super.key, this.url, this.label, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final letter = (label ?? 'C').trim();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFF1D4250),
      backgroundImage:
          url != null && url!.startsWith('http') ? NetworkImage(url!) : null,
      child: url == null || !url!.startsWith('http')
          ? Text(
              letter.isEmpty ? 'C' : letter.substring(0, 1).toUpperCase(),
              style: TextStyle(
                fontSize: size * .36,
                color: const Color(0xFF23D3B0),
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 60, color: const Color(0xFF23D3B0)),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
}

String _time(dynamic value) {
  if (value == null) return '';
  final d = DateTime.tryParse(value.toString())?.toLocal();
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
