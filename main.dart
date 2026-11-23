import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------
final FlutterLocalNotificationsPlugin notif = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  tzdata.initializeTimeZones();
  const init = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await notif.initialize(init);
  final android = notif.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  try {
    await android?.requestNotificationsPermission();
  } catch (_) {}
  try {
    await android?.requestExactAlarmsPermission();
  } catch (_) {}
}

Future<void> scheduleNotif(Part p) async {
  if (p.done || p.start.isBefore(DateTime.now())) return;
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'study_reminders',
      'یادآور مطالعه',
      channelDescription: 'یادآور شروع بخش‌های مطالعه',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );
  final when = tz.TZDateTime.from(p.start, tz.local);
  final body = '${p.title} • ${p.subject} • ${fa(p.plannedMin)} دقیقه';
  try {
    await notif.zonedSchedule(
      p.id,
      'وقت مطالعه است 📚',
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  } catch (_) {
    try {
      await notif.zonedSchedule(
        p.id,
        'وقت مطالعه است 📚',
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Helpers (Persian digits, Jalali dates)
// ---------------------------------------------------------------------------
String fa(Object n) {
  const e = '0123456789';
  const p = '۰۱۲۳۴۵۶۷۸۹';
  var s = n.toString();
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(e[i], p[i]);
  }
  return s;
}

int toInt(String s, int def) {
  const p = '۰۱۲۳۴۵۶۷۸۹';
  const a = '٠١٢٣٤٥٦٧٨٩';
  var t = s.trim();
  for (var i = 0; i < 10; i++) {
    t = t.replaceAll(p[i], '$i').replaceAll(a[i], '$i');
  }
  return int.tryParse(t) ?? def;
}

String fmtTime(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

List<int> toJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 +
      (365 * gy) +
      ((gy2 + 3) ~/ 4) -
      ((gy2 + 99) ~/ 100) +
      ((gy2 + 399) ~/ 400) +
      gd +
      gdm[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  int jm, jd;
  if (days < 186) {
    jm = 1 + days ~/ 31;
    jd = 1 + days % 31;
  } else {
    jm = 7 + (days - 186) ~/ 30;
    jd = 1 + (days - 186) % 30;
  }
  return [jy, jm, jd];
}

const jMonths = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
];
const wdName = {
  6: 'شنبه',
  7: 'یکشنبه',
  1: 'دوشنبه',
  2: 'سه‌شنبه',
  3: 'چهارشنبه',
  4: 'پنجشنبه',
  5: 'جمعه',
};

String dateTitle(DateTime d) {
  final j = toJalali(d.year, d.month, d.day);
  return '${wdName[d.weekday]} ${fa(j[2])} ${jMonths[j[1] - 1]} ${fa(j[0])}';
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime daysAgo(int k) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - k);
}

String fmtMinShort(double m) {
  if (m < 60) return '${fa(m.round())}د';
  return '${fa((m / 60).toStringAsFixed(1)).replaceAll('.', '٫')}س';
}

String fmtMinLong(double m) {
  final mm = m.round();
  if (mm < 60) return '${fa(mm)} دقیقه';
  return '${fa(mm ~/ 60)} ساعت و ${fa(mm % 60)} دقیقه';
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------
class Part {
  int id;
  String title;
  String subject;
  DateTime start;
  int plannedMin;
  bool done;
  int actualMin;
  int tests;

  Part({
    required this.id,
    required this.title,
    required this.subject,
    required this.start,
    required this.plannedMin,
    this.done = false,
    this.actualMin = 0,
    this.tests = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subject': subject,
        'start': start.millisecondsSinceEpoch,
        'planned': plannedMin,
        'done': done,
        'actual': actualMin,
        'tests': tests,
      };

  factory Part.fromJson(Map<String, dynamic> j) => Part(
        id: j['id'],
        title: j['title'],
        subject: j['subject'],
        start: DateTime.fromMillisecondsSinceEpoch(j['start']),
        plannedMin: j['planned'],
        done: j['done'],
        actualMin: j['actual'],
        tests: j['tests'],
      );
}

// ---------------------------------------------------------------------------
// Simple bar chart
// ---------------------------------------------------------------------------
class BarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final String Function(double) fmt;
  final Color color;

  const BarChart({
    super.key,
    required this.values,
    required this.labels,
    required this.fmt,
    this.color = Colors.indigo,
  });

  @override
  Widget build(BuildContext context) {
    final mx = values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (i) {
          final v = values[i];
          final h = mx == 0 ? 0.0 : (v / mx) * 120;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (values.length <= 14)
                    Text(
                      v == 0 ? '' : fmt(v),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(fontSize: 10),
                    ),
                  const SizedBox(height: 2),
                  Container(
                    height: (h < 2 && v > 0) ? 2 : h,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 30,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initNotifications();
  } catch (_) {}
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'برنامه‌ریز مطالعه',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final List<Part> parts = [];
  bool loaded = false;
  int tab = 0;
  DateTime day = dayOnly(DateTime.now());
  int testRange = 7;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('parts');
    if (raw != null) {
      final list = (jsonDecode(raw) as List)
          .map((e) => Part.fromJson(e as Map<String, dynamic>))
          .toList();
      parts
        ..clear()
        ..addAll(list);
    }
    setState(() => loaded = true);
    for (final p in parts) {
      await scheduleNotif(p);
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        'parts', jsonEncode(parts.map((e) => e.toJson()).toList()));
  }

  // ----- actions -----------------------------------------------------------
  Future<void> addPart() async {
    final title = TextEditingController();
    final subject = TextEditingController();
    final planned = TextEditingController(text: '60');
    TimeOfDay time = TimeOfDay.now();
    final subjects = parts.map((e) => e.subject).toSet().toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('بخش جدید مطالعه'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(
                      labelText: 'عنوان (مثلاً فصل ۳ زیست)'),
                ),
                TextField(
                  controller: subject,
                  decoration: const InputDecoration(labelText: 'درس'),
                ),
                if (subjects.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      children: subjects
                          .map((s) => ActionChip(
                                label: Text(s),
                                onPressed: () => subject.text = s,
                              ))
                          .toList(),
                    ),
                  ),
                TextField(
                  controller: planned,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'مدت برنامه‌ریزی‌شده (دقیقه)'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(
                      'ساعت شروع: ${fa(fmtTime(time.hour, time.minute))}'),
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: ctx, initialTime: time);
                    if (t != null) setS(() => time = t);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('افزودن')),
          ],
        ),
      ),
    );

    if (ok != true || title.text.trim().isEmpty) return;
    final p = Part(
      id: DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF,
      title: title.text.trim(),
      subject: subject.text.trim().isEmpty ? 'عمومی' : subject.text.trim(),
      start: DateTime(day.year, day.month, day.day, time.hour, time.minute),
      plannedMin: toInt(planned.text, 60),
    );
    setState(() => parts.add(p));
    await save();
    await scheduleNotif(p);
  }

  Future<List<int>?> askDone(Part p) async {
    final a = TextEditingController(text: p.plannedMin.toString());
    final t = TextEditingController(text: '0');
    return showDialog<List<int>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('این بخش تموم شد؟ 🎉'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: a,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'مدت واقعی مطالعه (دقیقه)'),
            ),
            TextField(
              controller: t,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'تعداد تست زده‌شده'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, [toInt(a.text, p.plannedMin), toInt(t.text, 0)]),
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
  }

  Future<void> toggle(Part p, bool? v) async {
    if (v == true) {
      final res = await askDone(p);
      if (res == null) return;
      setState(() {
        p.done = true;
        p.actualMin = res[0];
        p.tests = res[1];
      });
      await notif.cancel(p.id);
    } else {
      setState(() {
        p.done = false;
        p.actualMin = 0;
        p.tests = 0;
      });
      await scheduleNotif(p);
    }
    await save();
  }

  Future<void> remove(Part p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف این بخش؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('خیر')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await notif.cancel(p.id);
    setState(() => parts.remove(p));
    await save();
  }

  // ----- stats -------------------------------------------------------------
  List<double> minutesPerDay(int n) {
    return List.generate(n, (i) {
      final d = daysAgo(n - 1 - i);
      return parts
          .where((p) => p.done && sameDay(p.start, d))
          .fold<double>(0, (a, p) => a + p.actualMin);
    });
  }

  List<double> testsPerDay(int n) {
    return List.generate(n, (i) {
      final d = daysAgo(n - 1 - i);
      return parts
          .where((p) => p.done && sameDay(p.start, d))
          .fold<double>(0, (a, p) => a + p.tests);
    });
  }

  List<String> dayLabels(int n) {
    return List.generate(n, (i) {
      final d = daysAgo(n - 1 - i);
      final j = toJalali(d.year, d.month, d.day);
      if (n <= 7) return wdName[d.weekday]!;
      if (n <= 14) return fa(j[2]);
      return (i % 5 == 0 || i == n - 1) ? fa(j[2]) : '';
    });
  }

  Map<String, int> testsBySubject(int range) {
    final m = <String, int>{};
    final lim = range == 0 ? null : daysAgo(range - 1);
    for (final p in parts) {
      if (!p.done || p.tests == 0) continue;
      if (lim != null && p.start.isBefore(lim)) continue;
      m[p.subject] = (m[p.subject] ?? 0) + p.tests;
    }
    return m;
  }

  // ----- pages -------------------------------------------------------------
  Widget sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget partTile(Part p) {
    final sub = p.done
        ? 'انجام شد: ${fa(p.actualMin)} دقیقه • ${fa(p.tests)} تست'
        : '${fa(fmtTime(p.start.hour, p.start.minute))} • ${fa(p.plannedMin)} دقیقه';
    return Card(
      child: ListTile(
        leading: Checkbox(value: p.done, onChanged: (v) => toggle(p, v)),
        title: Text(
          p.title,
          style: TextStyle(
              decoration: p.done ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text('${p.subject} • $sub'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => remove(p),
        ),
      ),
    );
  }

  Widget planPage() {
    final list = parts.where((p) => sameDay(p.start, day)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final planned = list.fold<int>(0, (a, p) => a + p.plannedMin);
    final doneMin =
        list.where((p) => p.done).fold<int>(0, (a, p) => a + p.actualMin);
    final isToday = sameDay(day, DateTime.now());
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                  () => day = DateTime(day.year, day.month, day.day - 1)),
            ),
            Expanded(
              child: InkWell(
                onTap: () => setState(() => day = dayOnly(DateTime.now())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Text(dateTitle(day),
                          style: Theme.of(context).textTheme.titleMedium),
                      if (isToday)
                        const Text('امروز', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                  () => day = DateTime(day.year, day.month, day.day + 1)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
              'برنامه: ${fmtMinLong(planned.toDouble())}  •  انجام‌شده: ${fmtMinLong(doneMin.toDouble())}'),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const Center(
                  child: Text('برای این روز بخشی ثبت نشده.\nدکمه «بخش جدید» رو بزن.',
                      textAlign: TextAlign.center))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  children: list.map(partTile).toList(),
                ),
        ),
      ],
    );
  }

  Widget hoursPage() {
    final w = minutesPerDay(7);
    final m = minutesPerDay(30);
    final wt = w.fold<double>(0, (a, b) => a + b);
    final mt = m.fold<double>(0, (a, b) => a + b);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        sectionTitle('۷ روز اخیر'),
        Text('مجموع: ${fmtMinLong(wt)}  •  میانگین روزانه: ${fmtMinLong(wt / 7)}'),
        const SizedBox(height: 12),
        BarChart(values: w, labels: dayLabels(7), fmt: fmtMinShort),
        const Divider(height: 40),
        sectionTitle('۳۰ روز اخیر'),
        Text('مجموع: ${fmtMinLong(mt)}  •  میانگین روزانه: ${fmtMinLong(mt / 30)}'),
        const SizedBox(height: 12),
        BarChart(
            values: m,
            labels: dayLabels(30),
            fmt: fmtMinShort,
            color: Colors.teal),
      ],
    );
  }

  Widget testsPage() {
    final total = parts.where((p) => p.done).fold<int>(0, (a, p) => a + p.tests);
    final week = testsPerDay(7).fold<double>(0, (a, b) => a + b).round();
    final daily = testsPerDay(14);
    final by = testsBySubject(testRange).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final mx = by.isEmpty ? 1 : by.first.value;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('مجموع کل تست‌ها: ${fa(total)}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text('۷ روز اخیر: ${fa(week)} تست'),
        const Divider(height: 36),
        sectionTitle('تعداد تست در هر روز (۱۴ روز اخیر)'),
        const SizedBox(height: 8),
        BarChart(
          values: daily,
          labels: dayLabels(14),
          fmt: (v) => fa(v.round()),
          color: Colors.deepOrange,
        ),
        const Divider(height: 36),
        sectionTitle('تست‌ها به تفکیک درس'),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('هفته')),
            ButtonSegment(value: 30, label: Text('ماه')),
            ButtonSegment(value: 0, label: Text('کل')),
          ],
          selected: {testRange},
          onSelectionChanged: (s) => setState(() => testRange = s.first),
        ),
        const SizedBox(height: 12),
        if (by.isEmpty) const Text('هنوز تستی ثبت نشده.'),
        ...by.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [Text(e.key), Text(fa(e.value))],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: e.value / mx,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = [planPage(), hoursPage(), testsPage()];
    const titles = ['برنامه مطالعه', 'آمار ساعت مطالعه', 'آمار تست‌ها'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[tab])),
      body: pages[tab],
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: addPart,
              icon: const Icon(Icons.add),
              label: const Text('بخش جدید'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'برنامه'),
          NavigationDestination(
              icon: Icon(Icons.bar_chart), label: 'ساعت مطالعه'),
          NavigationDestination(icon: Icon(Icons.quiz), label: 'تست‌ها'),
        ],
      ),
    );
  }
}
