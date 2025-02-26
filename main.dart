import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nbt_app/baseConfigs/app_base_config.dart';
import 'package:nbt_app/baseConfigs/global_variables.dart';
import 'package:nbt_app/gen/assets.gen.dart';
import 'package:nbt_app/ui/auth/auth.dart';
import 'package:nbt_app/ui/auth/authentication_helper.dart';
import 'package:nbt_app/ui/map_page/bus_lines_map.dart';
import 'package:nbt_app/ui/map_page/mainMapPage.dart';
import 'package:nbt_app/ui/map_page/stations_map_page.dart';
import 'package:nbt_app/ui/theme_config/theme_config.dart';
import 'package:nbt_app/utilities/api_helpers/http_client.dart';
import 'package:nbt_app/utilities/location_utilities/location_provider.dart';
import 'package:nbt_app/utilities/notification_system/notification_system.dart';
import 'package:nbt_app/utilities/secure_storage/secure_storage.dart';
import 'package:provider/provider.dart';
import 'app_settings.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

String? userId = '';
String? userType = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize settings before running the app
  final appSettings = AppSettings();
  await appSettings.initialize();

  userId = await SecureStorageMethods.getFromStorage('JWT:user_id');
  userType = await SecureStorageMethods.getFromStorage('JWT:user_type');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appSettings),
        ChangeNotifierProvider(
            create: (_) => LocationProvider()),
      ],
      child: MyApp(
        userId: userId,
        userType: userType,
      ),
    ),
  );
}


class MyApp extends StatefulWidget {
  final String? userId;
  final String? userType;
  const MyApp({super.key, this.userId, this.userType});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<bool> _isAuthenticated;

  @override
  void initState() {
    super.initState();
    _isAuthenticated = _checkUserAuthentication();
  }

  Future<bool> _checkUserAuthentication() async {
    return await isUserAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AppSettings, LocationProvider>(
      builder: (context, appSettings, locationProvider, child) {
        return MaterialApp(
          title: 'Mohammad App',
          theme: appSettings.themeMode == ThemeMode.dark
              ? ThemeConfig.dark().getTheme(appSettings.locale.languageCode)
              : ThemeConfig.light().getTheme(appSettings.locale.languageCode),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: appSettings.locale,
          home: FutureBuilder<bool>(
            future: _isAuthenticated,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              } else if (snapshot.hasError) {
                return const Scaffold(
                  body: Center(
                      child: Text('Error loading authentication status')),
                );
              } else {
                return snapshot.data == true
                    ? MainScreen(
                        userId: userId,
                        userType: userType,
                      )
                    : const AuthScreen();
              }
            },
          ),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  final String? userId;
  final String? userType;
  const MainScreen({super.key, this.userId, this.userType});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

const homeScreenIndex = 0;
const stationsScreenIndex = 1;
const linesScreenIndex = 2;

class _MainScreenState extends State<MainScreen> {
  int selectedTabIndex = homeScreenIndex;


  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            Positioned(
              child: IndexedStack(
                index: selectedTabIndex,
                children: [
                  MainMapPage(
                    userId: int.parse(userId!),
                    userType: userType!,
                  ),
                  StationsMapPage(
                    userId: int.parse(userId!),
                    userType: userType!,
                  ),
                  BusLinesMap(
                    userId: int.parse(userId!),
                    userType: userType!,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              left: 10,
              child: _BottomNavigation(
                onTap: (int index) {
                  setState(() {
                    selectedTabIndex = index;
                  });
                },
              ),
            ),
            const Positioned(
              top: 10,
              right: 10,
              left: 10,
              child: AppBar(),
            ),
          ],
        ),
      ),
    );
  }
}

class AppBar extends StatelessWidget {
  const AppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final appSettings =
        Provider.of<AppSettings>(context); // Listening for updates here
    final themeData = Theme.of(context);

    return Container(
      height: 65,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: context.themeData.colorScheme.surface,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          appSettings.locale.languageCode == 'fa'
              ? appSettings.themeMode == ThemeMode.light
                  ? Assets.img.icons.logoWhite.image(height: 45)
                  : Assets.img.icons.logoDarkMode.image(height: 45)
              : appSettings.themeMode == ThemeMode.light
                  ? Assets.img.icons.logoWhiteEn.image(height: 45)
                  : Assets.img.icons.logoDarkModeEn.image(height: 45),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () {
                    // Use listen: false here
                    Provider.of<AppSettings>(context, listen: false)
                        .toggleThemeMode();
                  },
                  child: Icon(
                    appSettings.themeMode == ThemeMode.dark
                        ? CupertinoIcons.sun_haze_fill
                        : CupertinoIcons.moon_fill,
                    color: themeData.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoSlidingSegmentedControl<Language>(
                  groupValue: appSettings.locale.languageCode == 'fa'
                      ? Language.fa
                      : Language.en,
                  thumbColor: themeData.brightness == Brightness.light
                      ? Colors.grey.shade400
                      : Colors.grey.shade700,
                  children: {
                    Language.en: SizedBox(
                      width: 20,
                      child: Assets.img.flags.enFlagPng
                          .image(width: 24, height: 24),
                    ),
                    Language.fa: SizedBox(
                      width: 20,
                      child: Assets.img.flags.iranFlagPng
                          .image(width: 24, height: 24),
                    ),
                  },
                  onValueChanged: (value) {
                    if (value != null) {
                      // Use listen: false here
                      Provider.of<AppSettings>(context, listen: false)
                          .changeLocale(
                        value == Language.en
                            ? const Locale('en')
                            : const Locale('fa'),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  final Function(int index) onTap;

  const _BottomNavigation({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      height: 85,
      child: Stack(
        children: [
          Positioned(
            right: 10,
            left: 10,
            bottom: 10,
            child: Container(
              height: 65,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: context.themeData.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 20,
                      color: const Color(0xff9b8487).withOpacity(0.3),
                    ),
                  ]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  BottomNavigationItem(
                    normalIcon: Icon(
                      CupertinoIcons.map_fill,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    activeIcon: Icon(
                      CupertinoIcons.map_fill,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: context.localization.mapPage,
                    onTap: () {
                      onTap(homeScreenIndex);
                    },
                  ),
                  BottomNavigationItem(
                    normalIcon: Icon(
                      CupertinoIcons.bus,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    activeIcon: Icon(
                      CupertinoIcons.bus,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: context.localization.stationsMap,
                    onTap: () {
                      onTap(1);
                    },
                  ),
                  BottomNavigationItem(
                    normalIcon: Icon(
                      CupertinoIcons.arrow_branch,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    activeIcon: Icon(
                      CupertinoIcons.arrow_branch,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: context.localization.busLinesMap,
                    onTap: () {
                      onTap(2);
                    },
                  ),
                  BottomNavigationItem(
                    normalIcon: Icon(
                      Icons.logout,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    activeIcon: Icon(
                      Icons.logout,
                      size: 24,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    title: context.localization.logOut,
                    onTap: () async {
                      final ApiService _apiService = ApiService();
                      try {
                        var result = await _apiService.logOut();

                        if (result) {
                          showSnackBar(
                              context.localization.logedOutSuccessfully,
                              context,
                              SnackBarStatus.success);

                          Future.delayed(const Duration(seconds: 2), () {
                            Navigator.pushReplacement(
                                context,
                                CupertinoPageRoute(
                                    builder: (context) => const AuthScreen()));
                          });
                        } else {
                          showSnackBar(context.localization.error, context,
                              SnackBarStatus.failed);
                        }
                      } catch (e) {
                        showSnackBar(context.localization.error, context,
                            SnackBarStatus.failed);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BottomNavigationItem extends StatelessWidget {
  final Icon normalIcon;
  final Icon activeIcon;
  final String title;
  final Function() onTap;

  const BottomNavigationItem(
      {super.key,
      required this.normalIcon,
      required this.activeIcon,
      required this.title,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          normalIcon,
          const SizedBox(
            height: 4,
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}
