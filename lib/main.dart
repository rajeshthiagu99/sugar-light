import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ink = Color(0xFF3B2440);
const panel = Color(0xFFFFF8EC);
const mint = Color(0xFFE94F7C);
const peach = Color(0xFFF4A62A);
const muted = Color(0xFF756472);

const corePromise = 'See your choices and estimated spend change.';

class AppAnalytics {
  static Future<void> log(
    String name, [
    Map<String, Object?> dimensions = const {},
  ]) async {
    final p = await SharedPreferences.getInstance();
    final events = p.getStringList('analytics_events') ?? <String>[];
    events.add(
      jsonEncode(<String, Object?>{
        'event': name,
        'at': DateTime.now().toUtc().toIso8601String(),
        'campaign_id': const String.fromEnvironment(
          'CAMPAIGN_ID',
          defaultValue: 'organic',
        ),
        'creative_id': const String.fromEnvironment(
          'CREATIVE_ID',
          defaultValue: 'organic',
        ),
        ...dimensions,
      }),
    );
    await p.setStringList(
      'analytics_events',
      events.length > 500 ? events.sublist(events.length - 500) : events,
    );
  }
}

bool hasRequiredTrial(List<({int priceMicros, String period})> phases) =>
    phases.any((phase) => phase.priceMicros == 0 && phase.period == 'P3D');

bool isExactRescueOffer({
  required String currency,
  required List<({int priceMicros, String period})> phases,
}) {
  final paid = phases.where((p) => p.priceMicros > 0).toList();
  if (paid.length < 2 || paid[0].period != 'P1Y' || paid[1].period != 'P1Y') {
    return false;
  }
  return (currency == 'INR' &&
          paid[0].priceMicros == 799000000 &&
          paid[1].priceMicros == 999000000) ||
      (currency == 'USD' &&
          paid[0].priceMicros == 11990000 &&
          paid[1].priceMicros == 14990000);
}

final notifications = FlutterLocalNotificationsPlugin();
Future<void> initNotifications() async {
  tz_data.initializeTimeZones();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (_) => openManageSubscription(),
  );
}

Future<void> openManageSubscription() async {
  await AppAnalytics.log('manage_subscription_opened');
  await launchUrl(
    Uri.parse(
      'https://play.google.com/store/account/subscriptions?sku=sugar_light_premium&package=com.rajesht.sugarlight',
    ),
    mode: LaunchMode.externalApplication,
  );
}

Future<void> scheduleTrialReminder() async {
  final android = notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  final granted = await android?.requestNotificationsPermission() ?? false;
  await AppAnalytics.log('trial_reminder_opt_in', {'granted': granted});
  if (!granted) return;
  await notifications.zonedSchedule(
    id: 199,
    title: 'Your trial renews tomorrow',
    body: 'Your Sugar Light trial renews tomorrow. Keep going or manage your subscription.',
    scheduledDate: tz.TZDateTime.now(tz.local).add(const Duration(days: 2)),
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'trial_reminder',
        'Trial reminder',
        channelDescription: 'Transparent subscription renewal reminder',
      ),
    ),
    payload: 'manage_subscription',
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initNotifications();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const EmberFree());
}

class EmberFree extends StatelessWidget {
  const EmberFree({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Sugar Light',
    theme: ThemeData.light(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(
        seedColor: mint,
        brightness: Brightness.light,
        surface: panel,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        fontFamily: 'Nunito',
        bodyColor: ink,
        displayColor: ink,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: mint,
        thumbColor: mint,
        inactiveTrackColor: Color(0xFFF0DDE2),
      ),
    ),
    builder: (context, child) => DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.75, -0.95),
          radius: 1.35,
          colors: [Color(0xFFFFD9A3), Color(0xFFFFF1DF), Color(0xFFFFFBF5)],
          stops: [0, .42, 1],
        ),
      ),
      child: Theme(
        data: Theme.of(context)
            .copyWith(scaffoldBackgroundColor: Colors.transparent),
        child: child!,
      ),
    ),
    home: const Gate(),
  );
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool loading = true, onboarded = false, premium = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted)
      setState(() {
        onboarded = p.getBool('onboarded') ?? false;
        premium = p.getBool('premium') ?? false;
        loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    const shot = String.fromEnvironment('SCREEN');
    if (shot == 'intro') return SugarIntro(onContinue: () {});
    if (shot.startsWith('onboarding')) return SugarOnboarding(onDone: () {});
    if (shot == 'paywall') return Paywall(onUnlocked: () {});
    if (shot == 'preview') return SugarOnboarding(onDone: () {});
    if (shot == 'home') return const Home();
    if (shot == 'sos') return const SosScreen();
    if (loading)
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: mint)),
      );
    if (!onboarded)
      return SugarWelcomeFlow(
        onDone: () async {
          final p = await SharedPreferences.getInstance();
          await p.setBool('onboarded', true);
          if (mounted) setState(() => onboarded = true);
        },
      );
    if (!premium)
      return Paywall(
        onUnlocked: () async {
          final p = await SharedPreferences.getInstance();
          await p.setBool('premium', true);
          if (mounted) setState(() => premium = true);
        },
      );
    return const Home();
  }
}

class _PipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final berry = Paint()..color = mint;
    final mango = Paint()..color = peach;
    final cream = Paint()..color = const Color(0xFFFFF8EC);
    final plum = Paint()..color = ink;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .16,
        size.height * .20,
        size.width * .68,
        size.height * .68,
      ),
      Radius.circular(size.width * .28),
    );
    canvas.drawRRect(body, berry);
    final leaf = Path()
      ..moveTo(size.width * .48, size.height * .23)
      ..quadraticBezierTo(
        size.width * .56,
        size.height * .01,
        size.width * .78,
        size.height * .09,
      )
      ..quadraticBezierTo(
        size.width * .67,
        size.height * .27,
        size.width * .48,
        size.height * .23,
      );
    canvas.drawPath(leaf, mango);
    for (final x in [size.width * .37, size.width * .63]) {
      canvas.drawCircle(Offset(x, size.height * .49), size.width * .09, cream);
      canvas.drawCircle(Offset(x, size.height * .50), size.width * .045, plum);
    }
    final smile = Path()
      ..moveTo(size.width * .39, size.height * .64)
      ..quadraticBezierTo(
        size.width * .50,
        size.height * .72,
        size.width * .61,
        size.height * .64,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .035
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(size.width * .21, size.height * .58),
      size.width * .035,
      mango,
    );
    canvas.drawCircle(
      Offset(size.width * .79, size.height * .58),
      size.width * .035,
      mango,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PipBuddy extends StatelessWidget {
  final double size;
  final String message;
  const PipBuddy({super.key, this.size = 88, this.message = ''});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PipPainter()),
      ),
      if (message.isNotEmpty) ...[
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: mint.withOpacity(.22)),
            ),
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.25),
            ),
          ),
        ),
      ],
    ],
  );
}

class Onboarding extends StatefulWidget {
  final VoidCallback onDone;
  const Onboarding({super.key, required this.onDone});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  late final PageController page;
  int index = () {
    const shot = String.fromEnvironment('SCREEN');
    if (shot == 'preview') return 7;
    if (shot.startsWith('onboarding'))
      return int.tryParse(shot.substring(10)) ?? 0;
    return 0;
  }();
  @override
  void initState() {
    super.initState();
    page = PageController(initialPage: index);
    AppAnalytics.log('onboarding_started');
  }

  double sugaryItems = 12, servingCost = 480;
  String brand = 'Sweetened chai';
  final Map<String, double> indianBrandPrices = const {
    'Sweetened chai': 480,
    'Biscuits / Milds': 480,
    'Classic Connect': 360,
    'Wills Ice cream': 240,
    'Marlboro': 440,
    'Four Square': 240,
    'Fruit juice': 140,
    'Other / enter my price': 220,
  };
  DateTime reset = DateTime.now();
  String reason = 'I want my life back';
  String trigger = 'After meals';
  final reasons = [
    'I want my life back',
    'For the people I love',
    'To feel lighter in my routine',
    'To feel in control',
  ];
  Future<void> next() async {
    if (index < 7) {
      await page.nextPage(
        duration: const Duration(milliseconds: 480),
        curve: Curves.easeOutCubic,
      );
    } else {
      final p = await SharedPreferences.getInstance();
      await p.setDouble('servings', sugaryItems);
      await p.setDouble('servingCost', servingCost);
      await p.setString('brand', brand);
      await p.setString('reset', reset.toIso8601String());
      await p.setString('reason', reason);
      await p.setString('trigger', trigger);
      await AppAnalytics.log('reset_profile_completed', {
        'trigger': trigger,
        'brand': brand,
      });
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
        child: Column(
          children: [
            Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Text(
                    '${index + 1}',
                    key: ValueKey(index),
                    style: const TextStyle(
                      color: mint,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOutCubic,
                      tween: Tween(end: (index + 1) / 8),
                      builder: (_, value, __) => Stack(
                        children: [
                          Container(height: 10, color: Color(0xFFE8CDD5)),
                          FractionallySizedBox(
                            widthFactor: value,
                            child: Container(
                              height: 10,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [mint, peach]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const LeafMark(small: true),
              ],
            ),
            const SizedBox(height: 28),
            Expanded(
              child: PageView(
                controller: page,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (v) {
                  setState(() => index = v);
                  if (v == 7) AppAnalytics.log('personalized_preview_seen');
                },
                children: [
                  _step(
                    'Let’s make this real.',
                    'Pick your usual sugary item.',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: brand,
                          isExpanded: true,
                          dropdownColor: panel,
                          decoration: const InputDecoration(
                            labelText: 'Your usual sugary item',
                            filled: true,
                          ),
                          items: indianBrandPrices.keys
                              .map(
                                (name) => DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(() {
                            brand = value ?? brand;
                            servingCost =
                                indianBrandPrices[brand] ?? servingCost;
                          }),
                        ),
                        const SizedBox(height: 24),
                        Center(child: big('${sugaryItems.round()}')),
                        const Center(
                          child: Text(
                            'sweet items a day',
                            style: TextStyle(color: muted, fontSize: 17),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Slider(
                          value: sugaryItems,
                          min: 1,
                          max: 50,
                          divisions: 49,
                          onChanged: (v) => setState(() => sugaryItems = v),
                        ),
                        rowLabel('1', '50+'),
                      ],
                    ),
                  ),
                  _step(
                    'What could one swap save?',
                    'A simple estimate from your usual routine.',
                    Column(
                      children: [
                        big(
                          '₹${(sugaryItems / 20 * servingCost * 30).round()}',
                        ),
                        Text(
                          'every month',
                          style: TextStyle(color: muted, fontSize: 17),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '₹${(sugaryItems / 20 * servingCost * 365).round()} every year',
                          style: const TextStyle(
                            color: peach,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: mint.withOpacity(.10),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: mint.withOpacity(.25)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded, color: mint),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'That is what a daily swap could keep.',
                                  style: TextStyle(
                                    color: mint,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$brand · about ₹${servingCost.round()} per 20',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Slider(
                          value: servingCost,
                          min: 50,
                          max: 1000,
                          divisions: 95,
                          onChanged: (v) => setState(() => servingCost = v),
                        ),
                        rowLabel('₹50', '₹1,000'),
                        const SizedBox(height: 12),
                        Text(
                          'Approximate retail prices vary by state, shop and servingCost size.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  _step(
                    'When do you want to begin?',
                    'Pick your starting line.',
                    Column(
                      children: [
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: card(),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.flag_rounded,
                                color: peach,
                                size: 38,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                DateFormat('EEEE').format(reset).toUpperCase(),
                                style: const TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              Text(
                                DateFormat('d MMMM').format(reset),
                                style: const TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final d in [0, 1, 2])
                                    ChoiceChip(
                                      label: Text(
                                        d == 0
                                            ? 'Today'
                                            : d == 1
                                            ? 'Tomorrow'
                                            : 'In 2 days',
                                      ),
                                      selected:
                                          reset.day ==
                                          DateTime.now()
                                              .add(Duration(days: d))
                                              .day,
                                      onSelected: (_) => setState(
                                        () => reset = DateTime.now().add(
                                          Duration(days: d),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _step(
                    'When do urges get loud?',
                    'Name the moments that feel hardest.',
                    Column(
                      children: [
                        for (final item in [
                          'After meals',
                          'With tea or coffee',
                          'When stressed',
                          'With friends',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ChoiceChip(
                              label: SizedBox(
                                width: 250,
                                child: Text(item, textAlign: TextAlign.left),
                              ),
                              selected: trigger == item,
                              onSelected: (_) => setState(() => trigger = item),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _step(
                    'Let’s plan for that moment.',
                    '$trigger is your cue. Let’s make the next choice easier.',
                    Column(
                      children: [
                        _personalCard(
                          Icons.schedule_rounded,
                          'Your hard moment',
                          trigger,
                          peach,
                        ),
                        const SizedBox(height: 14),
                        _personalCard(
                          Icons.favorite_rounded,
                          'What we’ll do',
                          'Open a 60-second reset right when the urge arrives.',
                          mint,
                        ),
                      ],
                    ),
                  ),
                  _step(
                    'What makes this worth it?',
                    'Pick the reason you want Pip to bring back.',
                    Column(
                      children: [
                        for (final r in reasons)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              onTap: () => setState(() => reason = r),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: reason == r
                                      ? mint.withOpacity(.12)
                                      : panel,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: reason == r
                                        ? mint
                                        : Color(0xFFE8CDD5),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      reason == r
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      color: reason == r ? mint : muted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _step(
                    'Built around you.',
                    'Your answers shape your support.',
                    Column(
                      children: [
                        _personalCard(
                          Icons.notifications_active_rounded,
                          'Ready for $trigger',
                          'A 60-second reset and a fast change of channel.',
                          peach,
                        ),
                        const SizedBox(height: 12),
                        _personalCard(
                          Icons.format_quote_rounded,
                          reason,
                          'Pip keeps this reason close for craving moments.',
                          mint,
                        ),
                        const SizedBox(height: 12),
                        _personalCard(
                          Icons.insights_rounded,
                          '${sugaryItems.round()} a day',
                          'Live time, money and body recovery.',
                          const Color(0xFF7BCBFF),
                        ),
                      ],
                    ),
                  ),
                  _step(
                    'Tomorrow, make one swap easier.',
                    corePromise,
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: card(),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.wb_sunny_outlined,
                                color: peach,
                                size: 38,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Tomorrow at 8:00 AM',
                                style: const TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'You’ll be ${DateTime(0, 0, 0, 8).difference(DateTime(0, 0, 0, 0)).inHours} hours sugar-light',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                'and have kept about ₹${(8 * sugaryItems / 24 / 20 * servingCost).round()}.',
                                style: const TextStyle(
                                  color: mint,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: card(),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.format_quote_rounded,
                                color: mint,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: index == 7
                  ? 'See my support plan'
                  : index == 1
                  ? 'I want this money back'
                  : 'Continue',
              onTap: next,
            ),
          ],
        ),
      ),
    ),
  );
  Widget _personalCard(IconData icon, String title, String line, Color color) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: card(),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(line, style: const TextStyle(color: muted, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _step(String title, String sub, Widget child) => ListView(
    children: [
      PipBuddy(
        size: 70,
        message: index == 0
            ? 'Hi, I’m Pip. Let’s make one easy swap.'
            : index == 1
            ? 'Small swaps can add up fast.'
            : index == 4
            ? 'That cue is real. Let’s prepare for it.'
            : index == 5
            ? 'I’ll bring this back when you need it.'
            : index == 6
            ? 'Here’s the plan your answers shaped.'
            : index == 7
            ? 'Tomorrow starts with one ready swap.'
            : '',
      ),
      const SizedBox(height: 18),
      Text(
        title,
        style: const TextStyle(
          fontSize: 46,
          height: .98,
          fontWeight: FontWeight.w900,
          letterSpacing: -2.1,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        sub,
        style: const TextStyle(
          color: muted,
          fontSize: 16.5,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 42),
      child,
    ],
  );
  Widget big(String s) => Text(
    s,
    style: const TextStyle(
      fontSize: 70,
      fontWeight: FontWeight.w800,
      letterSpacing: -3,
    ),
  );
  Widget rowLabel(String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(a, style: const TextStyle(color: muted)),
        Text(b, style: const TextStyle(color: muted)),
      ],
    ),
  );
}

class SugarWelcomeFlow extends StatefulWidget {
  final VoidCallback onDone;
  const SugarWelcomeFlow({super.key, required this.onDone});
  @override
  State<SugarWelcomeFlow> createState() => _SugarWelcomeFlowState();
}

class _SugarWelcomeFlowState extends State<SugarWelcomeFlow> {
  bool welcomed = false;
  @override
  Widget build(BuildContext context) => welcomed
      ? SugarOnboarding(onDone: widget.onDone)
      : SugarIntro(onContinue: () => setState(() => welcomed = true));
}

class SugarIntro extends StatelessWidget {
  final VoidCallback onContinue;
  const SugarIntro({super.key, required this.onContinue});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LeafMark(),
            const Spacer(),
            Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      peach.withOpacity(.36),
                      mint.withOpacity(.08),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: const Center(child: PipBuddy(size: 150)),
              ),
            ),
            const SizedBox(height: 42),
            Text(
              'One sweet moment.\nOne better swap.',
              style: TextStyle(
                fontSize: 46,
                height: .98,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.8,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onContinue,
              child: Container(
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB52E), Color(0xFFF14E78)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33F14E78),
                      blurRadius: 0,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: const Text(
                  'Choose my swap',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class SugarOnboarding extends StatefulWidget {
  final VoidCallback onDone;
  const SugarOnboarding({super.key, required this.onDone});
  @override
  State<SugarOnboarding> createState() => _SugarOnboardingState();
}

class _SugarOnboardingState extends State<SugarOnboarding> {
  late final PageController page;
  int index = () {
    const shot = String.fromEnvironment('SCREEN');
    if (shot == 'preview') return 5;
    if (shot.startsWith('onboarding')) {
      return math.min(5, int.tryParse(shot.substring(10)) ?? 0);
    }
    return 0;
  }();
  String moment = 'Evening sweet craving';
  String item = 'Sweetened chai';
  String swap = 'Chai with half the sugar';
  String tried = 'I go all-or-nothing';

  @override
  void initState() {
    super.initState();
    page = PageController(initialPage: index);
    AppAnalytics.log('sugar_pattern_started');
  }

  Future<void> next() async {
    if (index < 5) {
      await page.nextPage(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('sweet_moment', moment);
    await p.setString('usual_item', item);
    await p.setString('planned_swap', swap);
    await p.setString('previous_attempt', tried);
    await p.setString('today_commitment', swap);
    await AppAnalytics.log('first_swap_committed', {
      'moment': moment,
      'item': item,
      'swap': swap,
    });
    widget.onDone();
  }

  Widget choice(
    String value,
    String selected,
    ValueChanged<String> onPick, {
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: () => onPick(value),
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: selected == value ? mint.withOpacity(.10) : panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected == value ? mint : ink.withOpacity(.08),
            width: selected == value ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: selected == value ? mint : peach),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Icon(
              selected == value
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: selected == value ? mint : muted,
            ),
          ],
        ),
      ),
    ),
  );

  Widget step(String eyebrow, String title, String sub, Widget body) =>
      ListView(
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 43,
              height: .98,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            sub,
            style: const TextStyle(color: muted, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 28),
          body,
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        child: Column(
          children: [
            Row(
              children: [
                const PipBuddy(size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: (index + 1) / 6,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE8CDD5),
                      color: index.isEven ? mint : peach,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${index + 1}/6',
                  style: const TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: PageView(
                controller: page,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (v) => setState(() => index = v),
                children: [
                  step(
                    'Find the moment',
                    'When does sweet food call your name?',
                    'Sugar habits attach to moments. Pick the one you want to make easier first.',
                    Column(
                      children: [
                        choice(
                          'Morning chai',
                          moment,
                          (v) => setState(() => moment = v),
                          icon: Icons.wb_sunny_outlined,
                        ),
                        choice(
                          'After lunch',
                          moment,
                          (v) => setState(() => moment = v),
                          icon: Icons.lunch_dining_outlined,
                        ),
                        choice(
                          'Evening sweet craving',
                          moment,
                          (v) => setState(() => moment = v),
                          icon: Icons.nights_stay_outlined,
                        ),
                        choice(
                          'Late-night snacking',
                          moment,
                          (v) => setState(() => moment = v),
                          icon: Icons.bedtime_outlined,
                        ),
                      ],
                    ),
                  ),
                  step(
                    'Name the default',
                    'What usually shows up then?',
                    'No calorie maths. Just name the repeat choice you actually make.',
                    Column(
                      children: [
                        for (final v in [
                          'Sweetened chai',
                          'Biscuits',
                          'Dessert after a meal',
                          'Soft drink or juice',
                        ])
                          choice(
                            v,
                            item,
                            (x) => setState(() => item = x),
                            icon: Icons.cookie_outlined,
                          ),
                      ],
                    ),
                  ),
                  step(
                    'Learn, do not judge',
                    'What have you tried before?',
                    'This changes the plan. We will not ask you to repeat what already failed.',
                    Column(
                      children: [
                        for (final v in [
                          'I go all-or-nothing',
                          'I avoid buying sweets',
                          'I switch to “healthy” snacks',
                          'This is my first real try',
                        ])
                          choice(v, tried, (x) => setState(() => tried = x)),
                      ],
                    ),
                  ),
                  step(
                    'Pick a replacement',
                    'What would still feel satisfying?',
                    'Your plan needs a yes, not only a no.',
                    Column(
                      children: [
                        for (final v in [
                          'Chai with half the sugar',
                          'Fruit plus curd',
                          'Nuts and unsweetened tea',
                          'A smaller portion after food',
                        ])
                          choice(
                            v,
                            swap,
                            (x) => setState(() => swap = x),
                            icon: Icons.swap_horiz_rounded,
                          ),
                      ],
                    ),
                  ),
                  step(
                    'See the pattern',
                    'Your cue has a shape.',
                    'We will learn from the time and moment, not punish a streak.',
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: card(),
                      child: Column(
                        children: [
                          const _MomentRow(
                            time: '8 AM',
                            label: 'Morning',
                            level: .25,
                          ),
                          const _MomentRow(
                            time: '1 PM',
                            label: 'After lunch',
                            level: .42,
                          ),
                          _MomentRow(
                            time: '6 PM',
                            label: moment,
                            level: .92,
                            active: true,
                          ),
                          const _MomentRow(
                            time: '10 PM',
                            label: 'Late night',
                            level: .35,
                          ),
                        ],
                      ),
                    ),
                  ),
                  step(
                    'Tomorrow’s ritual',
                    'One swap. At one real moment.',
                    'In the morning, commit. At the moment, tap what happened. At night, learn.',
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: card(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MY ONE SWAP',
                                style: TextStyle(
                                  color: mint,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.3,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '$moment: $swap',
                                style: const TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Instead of $item',
                                style: const TextStyle(color: muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _RitualCard(
                                icon: Icons.wb_sunny_outlined,
                                title: 'Commit',
                                sub: 'Morning',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _RitualCard(
                                icon: Icons.touch_app_outlined,
                                title: 'Tap',
                                sub: 'At the moment',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _RitualCard(
                                icon: Icons.insights_outlined,
                                title: 'Learn',
                                sub: 'At night',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PrimaryButton(
              label: index == 5 ? 'Commit to my first swap' : 'Continue',
              onTap: next,
            ),
          ],
        ),
      ),
    ),
  );
}

class _MomentRow extends StatelessWidget {
  final String time, label;
  final double level;
  final bool active;
  const _MomentRow({
    required this.time,
    required this.label,
    required this.level,
    this.active = false,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            time,
            style: const TextStyle(color: muted, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: active ? mint : ink,
                ),
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: level,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF0DDE2),
                  color: active ? mint : peach,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _RitualCard extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  const _RitualCard({
    required this.icon,
    required this.title,
    required this.sub,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: card(radius: 16),
    child: Column(
      children: [
        Icon(icon, color: peach),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class SugarToday extends StatefulWidget {
  const SugarToday({super.key});
  @override
  State<SugarToday> createState() => _SugarTodayState();
}

class _SugarTodayState extends State<SugarToday> {
  String outcome = '';
  Future<void> log(String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'moment_outcome_${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
      value,
    );
    await AppAnalytics.log('sweet_moment_logged', {'outcome': value});
    setState(() => outcome = value);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SharedPreferences>(
    future: SharedPreferences.getInstance(),
    builder: (context, snap) {
      final p = snap.data;
      final moment = p?.getString('sweet_moment') ?? 'Evening sweet craving';
      final item = p?.getString('usual_item') ?? 'Sweetened chai';
      final swap =
          p?.getString('today_commitment') ?? 'Chai with half the sugar';
      final now = DateTime.now();
      final outcomePrefix = 'moment_outcome_';
      final totalSwapDays =
          p
              ?.getKeys()
              .where(
                (key) =>
                    key.startsWith(outcomePrefix) &&
                    p.getString(key) == 'swapped',
              )
              .length ??
          0;
      var currentStreak = 0;
      final todayValue = p?.getString(
        'moment_outcome_${DateFormat('yyyy-MM-dd').format(now)}',
      );
      var cursor = todayValue == 'swapped'
          ? now
          : now.subtract(const Duration(days: 1));
      for (var i = 0; i < 3650; i++) {
        final value = p?.getString(
          'moment_outcome_${DateFormat('yyyy-MM-dd').format(cursor)}',
        );
        if (value != 'swapped') break;
        currentStreak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            children: [
              const PipBuddy(size: 48),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GOOD MORNING',
                      style: TextStyle(
                        color: mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    Text(
                      'What is your one swap today?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: card(radius: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    color: peach,
                    size: 18,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$currentStreak day streak · $totalSwapDays total',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [mint.withOpacity(.13), peach.withOpacity(.16)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: mint.withOpacity(.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TODAY’S ONE SWAP',
                  style: TextStyle(
                    color: mint,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  swap,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.02,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '$moment · instead of $item',
                  style: const TextStyle(color: muted, height: 1.35),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => log('committed'),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('I’m in for this swap'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'WHEN THE MOMENT ARRIVES',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  moment,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text('One tap.', style: TextStyle(color: muted)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Made my swap'),
                      avatar: const Icon(Icons.swap_horiz_rounded, size: 18),
                      onPressed: () => log('swapped'),
                    ),
                    ActionChip(
                      label: const Text('Had the usual'),
                      avatar: const Icon(Icons.cookie_outlined, size: 18),
                      onPressed: () => log('usual'),
                    ),
                    ActionChip(
                      label: const Text('Moment didn’t happen'),
                      avatar: const Icon(Icons.remove_circle_outline, size: 18),
                      onPressed: () => log('absent'),
                    ),
                  ],
                ),
                if (outcome.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    outcome == 'usual'
                        ? 'Logged. The day is still yours. We’ll learn from this moment.'
                        : 'Got it. Tonight’s pattern will use this.',
                    style: const TextStyle(
                      color: mint,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'YOUR DAY BY MOMENT',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: card(),
            child: const Column(
              children: [
                _MomentRow(time: '8 AM', label: 'Morning chai', level: .25),
                _MomentRow(time: '1 PM', label: 'After lunch', level: .42),
                _MomentRow(
                  time: '6 PM',
                  label: 'Your focus moment',
                  level: .90,
                  active: true,
                ),
                _MomentRow(time: '10 PM', label: 'Late night', level: .30),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class Paywall extends StatefulWidget {
  final VoidCallback onUnlocked;
  const Paywall({super.key, required this.onUnlocked});
  @override
  State<Paywall> createState() => _PaywallState();
}

class _PaywallState extends State<Paywall> {
  bool busy = false;
  bool allowPop = false;
  GooglePlayProductDetails? annualTrialProduct;
  String? annualTrialOfferToken;
  GooglePlayProductDetails? monthlyTrialProduct;
  String? monthlyTrialOfferToken;
  bool annualSelected = true;
  String annualPrice = '₹999';
  String monthlyPrice = '₹200';
  GooglePlayProductDetails? rescueProduct;
  String? rescueOfferToken;
  String rescueFirstPrice = '₹799';
  String rescueRenewalPrice = '₹999';
  List<ProductDetails> products = [];
  late StreamSubscription sub;
  @override
  void initState() {
    super.initState();
    AppAnalytics.log('paywall_seen', {
      'placement': 'post_personalized_preview',
    });
    if (const String.fromEnvironment('SCREEN') == 'paywall') {
      sub = const Stream<List<PurchaseDetails>>.empty().listen(_purchases);
    } else {
      sub = InAppPurchase.instance.purchaseStream.listen(_purchases);
      _load();
    }
  }

  Future<void> _load() async {
    if (await InAppPurchase.instance.isAvailable()) {
      final r = await InAppPurchase.instance.queryProductDetails({
        'sugar_light_premium',
      });
      final androidProducts = r.productDetails
          .whereType<GooglePlayProductDetails>();
      for (final product in androidProducts) {
        final index = product.subscriptionIndex;
        if (index == null) continue;
        final offer = product.productDetails.subscriptionOfferDetails![index];
        final phases = offer.pricingPhases
            .map(
              (p) =>
                  (priceMicros: p.priceAmountMicros, period: p.billingPeriod),
            )
            .toList();
        if (isExactRescueOffer(
          currency: product.currencyCode,
          phases: phases,
        )) {
          final paid = offer.pricingPhases
              .where((p) => p.priceAmountMicros > 0)
              .toList();
          rescueProduct = product;
          rescueOfferToken = offer.offerIdToken;
          rescueFirstPrice = paid[0].formattedPrice;
          rescueRenewalPrice = paid[1].formattedPrice;
          continue;
        }
        if (hasRequiredTrial(phases)) {
          final recurring = offer.pricingPhases.where(
            (p) => p.priceAmountMicros > 0,
          );
          if (recurring.isEmpty) continue;
          if (offer.basePlanId == 'annual' &&
              recurring.first.billingPeriod == 'P1Y') {
            annualTrialProduct = product;
            annualTrialOfferToken = offer.offerIdToken;
            annualPrice = recurring.first.formattedPrice;
          } else if (offer.basePlanId == 'monthly' &&
              recurring.first.billingPeriod == 'P1M') {
            monthlyTrialProduct = product;
            monthlyTrialOfferToken = offer.offerIdToken;
            monthlyPrice = recurring.first.formattedPrice;
          }
          await AppAnalytics.log('trial_offer_available', {
            'offer_id': offer.offerId ?? 'trial',
            'base_plan_id': offer.basePlanId,
          });
        }
      }
      if (mounted) setState(() => products = r.productDetails);
    }
  }

  void _purchases(List<PurchaseDetails> ps) {
    for (final p in ps) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        AppAnalytics.log(
          p.status == PurchaseStatus.purchased
              ? 'trial_started'
              : 'purchase_restored',
        );
        scheduleTrialReminder();
        widget.onUnlocked();
      }
      if (p.pendingCompletePurchase) InAppPurchase.instance.completePurchase(p);
    }
  }

  Future<void> buy() async {
    final product = annualSelected ? annualTrialProduct : monthlyTrialProduct;
    final token = annualSelected
        ? annualTrialOfferToken
        : monthlyTrialOfferToken;
    if (product == null || token == null) {
      await AppAnalytics.log('trial_offer_unavailable_blocked');
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The 3-day free trial is temporarily unavailable. No purchase was started.',
            ),
          ),
        );
      return;
    }
    setState(() => busy = true);
    await AppAnalytics.log('paywall_offer_selected', {
      'plan': annualSelected ? 'annual' : 'monthly',
      'offer_token_present': true,
      'placement': 'post_personalized_preview',
    });
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: product,
        offerToken: token,
      ),
    );
    if (mounted) setState(() => busy = false);
  }

  Future<void> _tryBackOut() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('rescue_offer_seen') == true ||
        rescueOfferToken == null) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    await prefs.setBool('rescue_offer_seen', true);
    await AppAnalytics.log('rescue_offer_seen', {'placement': 'paywall_back'});
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _RescueDialog(
        firstPrice: rescueFirstPrice,
        renewalPrice: rescueRenewalPrice,
        onAccept: _buyRescue,
      ),
    );
  }

  Future<void> _buyRescue() async {
    final product = rescueProduct;
    final token = rescueOfferToken;
    if (product == null || token == null) return;
    Navigator.of(context).pop();
    await AppAnalytics.log('rescue_offer_selected');
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: product,
        offerToken: token,
      ),
    );
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _tryBackOut();
    },
    child: Scaffold(
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 8, 24, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: busy
                  ? 'Opening Google Play…'
                  : 'Start my 3-day free trial',
              onTap: busy ? null : buy,
            ),
            const SizedBox(height: 8),
            Text(
              annualSelected
                  ? 'Then $annualPrice/year. Cancel anytime in Google Play.'
                  : 'Then $monthlyPrice/month. Cancel anytime in Google Play.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -110,
              right: -80,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [mint.withOpacity(.22), Colors.transparent],
                  ),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              children: [
                const Center(child: LeafMark()),
                const SizedBox(height: 26),
                Text(
                  'Make the next sweet moment easier.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 46,
                    height: .98,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Commit in the morning. Log the moment. Learn at night.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 17),
                ),
                const SizedBox(height: 30),
                ...[
                  [
                    'A time-of-day pattern map',
                    'See your choices and estimated spend change.',
                  ],
                  [
                    'One satisfying swap ready',
                    'Simple swaps, distractions and your reason, ready.',
                  ],
                  [
                    'Moment logging, not streak policing',
                    'Log it, learn from it, and choose again.',
                  ],
                ].map(
                  (x) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: mint.withOpacity(.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: mint,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Text(
                            x[0],
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _SugarPlanCard(
                  title: 'Annual',
                  price: '$annualPrice / year',
                  detail: 'Best value',
                  selected: annualSelected,
                  onTap: () => setState(() => annualSelected = true),
                ),
                const SizedBox(height: 10),
                _SugarPlanCard(
                  title: 'Monthly',
                  price: '$monthlyPrice / month',
                  detail: 'Flexible billing',
                  selected: !annualSelected,
                  onTap: () => setState(() => annualSelected = false),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: card(radius: 18),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: muted, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No charge today. Reminder before renewal.',
                          style: TextStyle(color: muted, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: openManageSubscription,
                  child: const Text(
                    'Manage subscription',
                    style: TextStyle(color: ink),
                  ),
                ),
                TextButton(
                  onPressed: () => InAppPurchase.instance.restorePurchases(),
                  child: const Text(
                    'Restore purchase',
                    style: TextStyle(color: ink),
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

class _SugarPlanCard extends StatelessWidget {
  final String title, price, detail;
  final bool selected;
  final VoidCallback onTap;
  const _SugarPlanCard({
    required this.title,
    required this.price,
    required this.detail,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: selected ? mint.withOpacity(.10) : Colors.white.withOpacity(.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? mint : const Color(0x22000000),
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: mint,
            size: 28,
          ),
        ],
      ),
    ),
  );
}

class _RescueDialog extends StatelessWidget {
  final String firstPrice, renewalPrice;
  final VoidCallback onAccept;
  const _RescueDialog({
    required this.firstPrice,
    required this.renewalPrice,
    required this.onAccept,
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('One last option'),
    content: Text('$firstPrice for year one. Then $renewalPrice/year.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Not now'),
      ),
      FilledButton(onPressed: onAccept, child: const Text('Choose yearly')),
    ],
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  Timer? timer;
  String billingState = 'active';
  Future<void> _refreshEntitlement() async {
    final p = await SharedPreferences.getInstance();
    final state = p.getString('billing_state') ?? 'active';
    if (mounted) setState(() => billingState = state);
    await AppAnalytics.log('entitlement_rechecked', {'billing_state': state});
  }

  String _dayKey([DateTime? value]) =>
      DateFormat('yyyy-MM-dd').format(value ?? DateTime.now());

  Map<String, int> _sugarLog(SharedPreferences? p) {
    if (p == null) return <String, int>{};
    try {
      final raw = jsonDecode(p.getString('daily_sugar_log') ?? '{}');
      if (raw is Map) {
        return raw.map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        );
      }
    } catch (_) {}
    return <String, int>{};
  }

  Future<void> _changeTodaySugar(int delta) async {
    final p = await SharedPreferences.getInstance();
    final log = _sugarLog(p);
    final key = _dayKey();
    final next = math.max(0, (log[key] ?? 0) + delta);
    if (next == 0) {
      log.remove(key);
    } else {
      log[key] = next;
    }
    await p.setString('daily_sugar_log', jsonEncode(log));
    await AppAnalytics.log(
      delta > 0 ? 'sugary item_logged' : 'sugary item_log_undone',
      {'day': key, 'today_count': next},
    );
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    AppAnalytics.log('first_home_seen');
    AppAnalytics.log('personal_why_viewed');
    _refreshEntitlement();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: tab,
        children: [const SugarToday(), _progress(), const SosScreen(), _you()],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      backgroundColor: const Color(0xFFFFF4E2),
      indicatorColor: mint.withOpacity(.15),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded, color: mint),
          label: 'Today',
        ),
        NavigationDestination(
          icon: Icon(Icons.insights_outlined),
          selectedIcon: Icon(Icons.insights, color: mint),
          label: 'Progress',
        ),
        NavigationDestination(
          icon: Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite, color: peach),
          label: 'SOS',
        ),
        NavigationDestination(icon: Icon(Icons.person_outline), label: 'You'),
      ],
    ),
  );
  Widget _today() => FutureBuilder<SharedPreferences>(
    future: SharedPreferences.getInstance(),
    builder: (c, s) {
      final p = s.data;
      final reset =
          DateTime.tryParse(p?.getString('reset') ?? '') ??
          DateTime.now().subtract(
            const Duration(days: 3, hours: 14, minutes: 27),
          );
      final elapsed = DateTime.now().difference(reset);
      final servings = p?.getDouble('servings') ?? 12;
      final servingCost = p?.getDouble('servingCost') ?? 220;
      final sugarLog = _sugarLog(p);
      final todayLogged = sugarLog[_dayKey()] ?? 0;
      final loggedSinceReset = sugarLog.entries.fold<int>(0, (total, entry) {
        final day = DateTime.tryParse(entry.key);
        return day != null &&
                !day.isBefore(DateTime(reset.year, reset.month, reset.day))
            ? total + entry.value
            : total;
      });
      final expectedSinceReset = math.max(
        0.0,
        elapsed.inMinutes / 1440 * servings,
      );
      final avoided = math.max(
        0,
        (expectedSinceReset - loggedSinceReset).round(),
      );
      final saved = avoided / 20 * servingCost;
      return ListView(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
        children: [
          Row(
            children: [
              const LeafMark(small: true),
              const SizedBox(width: 10),
              Text(
                'Sugar Light',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: card(radius: 20),
                child: const Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: peach,
                      size: 18,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Steady',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (billingState == 'grace' || billingState == 'hold') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: peach.withOpacity(.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: peach.withOpacity(.32)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_off_rounded, color: peach),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      billingState == 'grace'
                          ? 'Google Play could not renew yet. Your support stays open.'
                          : 'Your plan is paused, but your reset data is safe.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: openManageSubscription,
                    child: const Text('Fix'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 15),
          const Text(
            'ONE CHOICE AT A TIME.\nSUGAR-LIGHT FOR',
            style: TextStyle(
              color: muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.7,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            elapsed.isNegative
                ? 'Your reset starts soon'
                : '${math.max(0, elapsed.inDays)} days',
            style: const TextStyle(
              fontSize: 68,
              fontWeight: FontWeight.w900,
              letterSpacing: -3,
            ),
          ),
          Text(
            '${elapsed.inHours.remainder(24).abs()} hours  ${elapsed.inMinutes.remainder(60).abs()} minutes',
            style: const TextStyle(
              fontSize: 20,
              color: mint,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              Expanded(
                child: Metric(
                  icon: Icons.currency_rupee_rounded,
                  value: '₹${saved.round()}',
                  label: 'kept by you',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Metric(
                  icon: Icons.air_rounded,
                  value: '$avoided',
                  label: 'swaps made',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.edit_note_rounded, color: mint),
                    SizedBox(width: 8),
                    Text(
                      'Today’s sugar log',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Log it. Your totals adjust instantly.',
                  style: TextStyle(color: muted, height: 1.35),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      '$todayLogged logged today',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (todayLogged > 0)
                      IconButton(
                        tooltip: 'Undo last sugary item',
                        onPressed: () => _changeTodaySugar(-1),
                        icon: const Icon(Icons.undo_rounded, color: muted),
                      ),
                    FilledButton.icon(
                      onPressed: () => _changeTodaySugar(1),
                      style: FilledButton.styleFrom(
                        backgroundColor: peach,
                        foregroundColor: ink,
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Log one',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: card(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.favorite_rounded, color: peach),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your pattern is changing',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Small choices are adding up',
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: const LinearProgressIndicator(
                    value: .72,
                    minHeight: 7,
                    backgroundColor: Color(0xFF26332F),
                    color: mint,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'Next: plan one satisfying swap',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: mint.withOpacity(.09),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: mint.withOpacity(.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: mint, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today’s tiny win',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'You came back to your plan today.',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: card(radius: 18),
            child: const Row(
              children: [
                Icon(Icons.format_quote_rounded, color: mint),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'I want my life back.',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => setState(() => tab = 2),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFFFE0A6), peach.withOpacity(.12)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: peach.withOpacity(.25)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.favorite_rounded, color: peach, size: 28),
                  SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A craving hit?',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'Take a 60-second reset.',
                          style: TextStyle(
                            color: Color(0xFFCDB5A9),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: peach),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _progress() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Text(
        'Your body\nremembers how.',
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Healing happens quietly. These are the changes already underway.',
        style: TextStyle(color: muted, fontSize: 16, height: 1.4),
      ),
      const SizedBox(height: 26),
      for (final x in [
        ['20 min', 'Pulse settles', 'done'],
        ['8 hours', 'Oxygen returns to normal', 'done'],
        ['48 hours', 'Taste and smell sharpen', 'now'],
        ['2–12 weeks', 'Circulation gets stronger', 'later'],
        ['1 year', 'Heart risk falls by half', 'later'],
      ])
        TimelineItem(time: x[0], title: x[1], state: x[2]),
    ],
  );
  Widget _you() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const Text(
        'Your reset,\nyour rules.',
        style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 25),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: card(),
        child: const Column(
          children: [
            ListTile(
              leading: Icon(Icons.format_quote, color: mint),
              title: Text('My reason'),
              subtitle: Text('I want my life back'),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.notifications_none, color: mint),
              title: Text('Daily support'),
              subtitle: Text('9:00 AM'),
            ),
            Divider(),
            ListTile(
              leading: Icon(Icons.receipt_long_outlined, color: mint),
              title: Text('Manage subscription'),
            ),
          ],
        ),
      ),
    ],
  );
}

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});
  @override
  State<SosScreen> createState() => _SosState();
}

class _SosState extends State<SosScreen> {
  bool breathing = false;
  int seconds = 60;
  Timer? t;
  void start() {
    AppAnalytics.log('first_sos_started');
    setState(() => breathing = true);
    t = Timer.periodic(const Duration(seconds: 1), (x) {
      if (seconds <= 0) {
        x.cancel();
        setState(() => breathing = false);
      } else
        setState(() => seconds--);
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
        children: [
          const PipBuddy(
            size: 72,
            message: 'I’m here. Let’s stay with this minute together.',
          ),
          const SizedBox(height: 18),
          const Text(
            'This feeling\nwill pass.',
            style: TextStyle(
              fontSize: 50,
              height: .96,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Stay with this moment.',
            style: TextStyle(color: muted, fontSize: 17, height: 1.45),
          ),
          const SizedBox(height: 30),
          Center(
            child: GestureDetector(
              onTap: start,
              child: Tweener(active: breathing, seconds: seconds),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            breathing ? 'Follow the circle' : 'Tap to begin a 60-second reset',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 32),
          const Text(
            'OR CHANGE THE CHANNEL',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ActionCard(
                  icon: Icons.water_drop_outlined,
                  title: 'Drink cold\nwater',
                  color: const Color(0xFF7BCBFF),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionCard(
                  icon: Icons.directions_walk_rounded,
                  title: 'Walk for\n2 minutes',
                  color: mint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionCard(
                  icon: Icons.sms_outlined,
                  title: 'Text\nsomeone',
                  color: peach,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: card(),
            child: const Row(
              children: [
                Icon(Icons.format_quote_rounded, color: mint, size: 31),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remember why you started',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '“I want my life back.”',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Tweener extends StatefulWidget {
  final bool active;
  final int seconds;
  const Tweener({super.key, required this.active, required this.seconds});
  @override
  State<Tweener> createState() => _TweenerState();
}

class _TweenerState extends State<Tweener> with SingleTickerProviderStateMixin {
  late AnimationController c;
  @override
  void initState() {
    super.initState();
    c = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (x, _) {
      final scale = widget.active ? .85 + .15 * c.value : 1.0;
      return Transform.scale(
        scale: scale,
        child: Container(
          width: 205,
          height: 205,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                mint.withOpacity(.42),
                mint.withOpacity(.10),
                Colors.transparent,
              ],
              stops: const [.12, .68, 1],
            ),
            border: Border.all(color: mint.withOpacity(.55), width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.active ? Icons.air_rounded : Icons.touch_app_rounded,
                  color: mint,
                  size: 33,
                ),
                const SizedBox(height: 7),
                Text(
                  widget.active
                      ? '${widget.seconds ~/ 60}:${(widget.seconds % 60).toString().padLeft(2, '0')}'
                      : 'RESET',
                  style: const TextStyle(
                    color: mint,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const PrimaryButton({super.key, required this.label, required this.onTap});
  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? .985 : 1,
    duration: const Duration(milliseconds: 90),
    child: GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => pressed = true),
      onTapCancel: () => setState(() => pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => pressed = false);
              widget.onTap!();
            },
      child: AnimatedOpacity(
        opacity: widget.onTap == null ? .55 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          height: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFB5FFDF), Color(0xFF62EBB4), Color(0xFF20BFA1)],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(14),
              bottomLeft: Radius.circular(14),
              bottomRight: Radius.circular(24),
            ),
            border: Border.all(color: ink.withOpacity(.24)),
            boxShadow: [
              BoxShadow(
                color: mint.withOpacity(.24),
                blurRadius: pressed ? 10 : 28,
                offset: Offset(0, pressed ? 3 : 10),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: ink,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: -.15,
            ),
          ),
        ),
      ),
    ),
  );
}

class LeafMark extends StatelessWidget {
  final bool small;
  const LeafMark({super.key, this.small = false});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: small ? 30 : 38,
        height: small ? 30 : 38,
        decoration: BoxDecoration(
          color: mint,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(Icons.eco_rounded, color: ink, size: small ? 19 : 24),
      ),
      if (!small) ...[
        const SizedBox(width: 10),
        const Text(
          'Sugar Light',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 19,
            letterSpacing: -.5,
          ),
        ),
      ],
    ],
  );
}

class PlanCard extends StatelessWidget {
  final String title, price, caption;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;
  const PlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.caption,
    this.badge,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: selected ? mint.withOpacity(.1) : panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? mint : Color(0xFFE8CDD5),
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 4),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: mint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            price,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          Text(caption, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      ),
    ),
  );
}

class Metric extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const Metric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [mint.withOpacity(.10), panel, panel],
      ),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(26),
        topRight: Radius.circular(16),
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(26),
      ),
      border: Border.all(color: mint.withOpacity(.14)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: mint, size: 22),
        const SizedBox(height: 14),
        Text(
          value,
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
        ),
        Text(label, style: const TextStyle(color: muted, fontSize: 13)),
      ],
    ),
  );
}

class TimelineItem extends StatelessWidget {
  final String time, title, state;
  const TimelineItem({
    super.key,
    required this.time,
    required this.title,
    required this.state,
  });
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state == 'done' ? mint : panel,
                  border: Border.all(
                    color: state == 'later' ? Color(0xFFCBA9B4) : mint,
                    width: 2,
                  ),
                ),
                child: state == 'done'
                    ? const Icon(Icons.check, color: ink, size: 14)
                    : null,
              ),
              Expanded(child: Container(width: 2, color: Color(0xFFE8CDD5))),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time.toUpperCase(),
                    style: TextStyle(
                      color: state == 'later' ? muted : mint,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: 140,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(.075),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(22),
        topRight: Radius.circular(10),
        bottomLeft: Radius.circular(10),
        bottomRight: Radius.circular(22),
      ),
      border: Border.all(color: color.withOpacity(.16)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const Spacer(),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2),
        ),
      ],
    ),
  );
}

BoxDecoration card({double radius = 22}) => BoxDecoration(
  color: panel,
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(radius + 3),
    topRight: Radius.circular(radius - 5),
    bottomLeft: Radius.circular(radius - 5),
    bottomRight: Radius.circular(radius + 3),
  ),
  border: Border.all(color: ink.withOpacity(.08)),
  boxShadow: const [
    BoxShadow(color: Color(0x26000000), blurRadius: 18, offset: Offset(0, 8)),
  ],
);
