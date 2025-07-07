import 'package:acent_messenger/constants/colors.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'views/splash/splash.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/group_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/global_event_provider.dart';
import 'package:acent_messenger/services/auth_service.dart';
import 'services/wallet_service.dart';
import 'services/fcm_service.dart';
import 'providers/contacts_provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'constants/env_config.dart';
import 'services/navigation_service.dart';
import 'services/permission_service.dart';

void main() async {
  print("App - main: Starting application");

  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment configuration
  await EnvConfig.initialize();
  print("App - main: Environment configuration loaded");

  // Initialize FCM service
  final fcmService = FCMService.instance;
  await fcmService.initialize();

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ContactsProvider()),
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        Provider<FCMService>(
          create: (_) => FCMService.instance,
        ),
        Provider<PermissionService>(
          create: (_) => PermissionService.instance,
        ),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProvider<GlobalEventProvider>(
          create: (_) => GlobalEventProvider(),
        ),
        ChangeNotifierProvider<ChatProvider>(
          create: (context) => ChatProvider(
            Provider.of<AuthService>(context, listen: false),
          ),
        ),
        ChangeNotifierProvider<GroupProvider>(
          create: (context) => GroupProvider(
            Provider.of<AuthService>(context, listen: false),
          ),
        ),
        ChangeNotifierProvider<WalletProvider>(
          create: (context) => WalletProvider(
            WalletService(Provider.of<AuthService>(context, listen: false)),
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Handle initial notification if app was opened from notification
    _handleInitialNotification();

    // Setup clear data callbacks after providers are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final walletProvider =
          Provider.of<WalletProvider>(context, listen: false);
      final groupProvider = Provider.of<GroupProvider>(context, listen: false);
      final contactsProvider =
          Provider.of<ContactsProvider>(context, listen: false);
      final globalEventProvider =
          Provider.of<GlobalEventProvider>(context, listen: false);

      // Set callback to clear all data when logout is called
      authProvider.setClearAllDataCallback(() {
        chatProvider.clearAllData();
        walletProvider.clearAllData();
        groupProvider.clearAllData();
        contactsProvider.clearAllData();
        globalEventProvider.disconnectGlobalEvents();
      });

      // Set callback to initialize global events when user logs in
      authProvider.setInitializeGlobalEventsCallback((String userId) {
        globalEventProvider.ensureInitialized(userId);
      });

      // Set callbacks for refreshing session lists when new messages arrive
      globalEventProvider.setRefreshSessionsCallbacks(
        refreshChatSessions: () {
          try {
            debugPrint('Main: Chat sessions refresh callback triggered');
            return chatProvider.refreshSessions();
          } catch (e) {
            debugPrint('Main: Error in chat sessions refresh callback: $e');
          }
        },
        refreshGroupSessions: () {
          try {
            debugPrint('Main: Group sessions refresh callback triggered');
            return groupProvider.refreshSessions();
          } catch (e) {
            debugPrint('Main: Error in group sessions refresh callback: $e');
          }
        },
      );

      // Set smart update callbacks for efficient session updates
      globalEventProvider.setSmartUpdateCallbacks(
        updateChatSession: (messageData) {
          try {
            debugPrint('Main: Smart chat session update triggered');
            chatProvider.updateSessionWithNewMessage(messageData);
          } catch (e) {
            debugPrint('Main: Error in smart chat session update: $e');
            // Fallback to full refresh on error
            chatProvider.refreshSessions();
          }
        },
        updateGroupSession: (messageData) {
          try {
            debugPrint('Main: Smart group session update triggered');
            groupProvider.updateSessionWithNewMessage(messageData);
          } catch (e) {
            debugPrint('Main: Error in smart group session update: $e');
            // Fallback to full refresh on error
            groupProvider.refreshSessions();
          }
        },
      );

      debugPrint(
          'Main: Session refresh callbacks and smart update callbacks have been set');

      // Initialize permissions after UI is loaded
      _initializePermissions();
    });
  }

  /// Initialize permissions after app is fully loaded
  void _initializePermissions() async {
    try {
      debugPrint('Main: Initializing permissions...');
      await PermissionService.instance.initializePermissions();
      debugPrint('Main: Permissions initialized successfully');
    } catch (e) {
      debugPrint('Main: Error initializing permissions: $e');
      // Don't block app startup if permissions fail
    }
  }

  /// Handle initial notification when app is opened from notification
  Future<void> _handleInitialNotification() async {
    try {
      debugPrint('Main: Checking for initial notification');

      // Get the initial notification that opened the app (if any)
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();

      if (initialMessage != null) {
        debugPrint(
            'Main: App opened from notification: ${initialMessage.messageId}');
        debugPrint('Main: Initial notification data: ${initialMessage.data}');

        // Wait a bit for the app to finish loading
        await Future.delayed(const Duration(seconds: 2));

        // Handle the notification navigation
        NavigationService.instance.handleNotificationData(initialMessage.data);
      } else {
        debugPrint('Main: No initial notification found');
      }
    } catch (e) {
      debugPrint('Main: Error handling initial notification: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final globalEventProvider =
        Provider.of<GlobalEventProvider>(context, listen: false);

    debugPrint('App lifecycle state changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        debugPrint('App resumed - checking global events connection');
        // App came to foreground - ensure global events are connected
        if (authProvider.isAuthenticated && authProvider.profile?.id != null) {
          globalEventProvider.handleAppResume();
          authProvider.updateUserStatus('online');
        }
        break;
      case AppLifecycleState.paused:
        debugPrint('App paused - updating user status to away');
        // App went to background - update status but keep connection
        if (authProvider.isAuthenticated) {
          globalEventProvider.handleAppPause();
          authProvider.updateUserStatus('away');
        }
        break;
      case AppLifecycleState.detached:
        debugPrint('App detached - updating user status to offline');
        // App is being terminated - update status to offline
        if (authProvider.isAuthenticated) {
          globalEventProvider.handleAppDetached();
          authProvider.updateUserStatus('offline');
        }
        break;
      case AppLifecycleState.inactive:
        debugPrint('App inactive - no action needed');
        // App is inactive (e.g., during a phone call)
        break;
      case AppLifecycleState.hidden:
        debugPrint('App hidden - no action needed');
        // App is hidden but still running
        break;
    }
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    print("App - MyApp: Building app widget");

    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey, // Add global navigator key
      debugShowCheckedModeBanner: false,
      title: 'Chat App',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.bgColor,
      ),
      home: const SplashScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, for example) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as the parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
