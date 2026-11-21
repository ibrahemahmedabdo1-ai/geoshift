import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'joystick.dart';
import 'services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GeoShiftApp());
}

class GeoShiftApp extends StatelessWidget {
  const GeoShiftApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GeoShift',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        builder: (c, w) =>
            Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _map = MapController();
  final _searchCtl = TextEditingController();
  LatLng _target = const LatLng(30.0444, 31.2357);
  LatLng _current = const LatLng(30.0444, 31.2357);
  bool _active = false;
  bool _locked = false;
  bool _ready = true;
  bool _mapReady = false;
  bool _searching = false;
  double _kmh = 5;
  Offset _stick = Offset.zero;
  Timer? _timer;
  List<Place> _favs = [];
  List<Place> _results = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final last = await Store.lastPoint();
    final favs = await Store.favorites();
    if (!mounted) return;
    setState(() {
      _favs = favs;
      if (last != null) {
        _target = last;
        _current = last;
      }
    });
    _moveMap(_target, 12);
    _checkReady();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkReady();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _moveMap(LatLng p, [double? zoom]) {
    if (!_mapReady) return;
    _map.move(p, zoom ?? _map.camera.zoom);
  }

  Future<void> _checkReady() async {
    final r = await MockChannel.isReady();
    if (mounted) setState(() => _ready = r);
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _send({double mps = 0, double bearing = 0}) =>
      MockChannel.update(_current, speed: mps, bearing: bearing);

  Future<void> _start() async {
    await _checkReady();
    if (!_ready) {
      _snack('اختار GeoShift من خيارات المطور ← Select mock location app');
      return;
    }
    _current = _target;
    await _send();
    Store.saveLast(_current);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    setState(() => _active = true);
  }

  Future<void> _stop() async {
    _timer?.cancel();
    await MockChannel.stop();
    if (mounted) {
      setState(() {
        _active = false;
        _locked = false;
        _stick = Offset.zero;
      });
    }
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      _stick = Offset.zero;
    });
    if (_locked) _send();
    _snack(_locked ? 'الموقع مثبّت' : 'تم فك التثبيت');
  }

  void _tick() {
    final mag = _stick.distance;
    if (!_active || _locked || mag < 0.05) return;
    final mps = _kmh / 3.6 * mag;
    final d = mps * 0.5;
    final b = math.atan2(_stick.dx, -_stick.dy);
    final lat = (_current.latitude + d * math.cos(b) / 111320).clamp(-85.0, 85.0);
    var lng = _current.longitude +
        d * math.sin(b) / (111320 * math.cos(lat * math.pi / 180));
    if (lng > 180) lng -= 360;
    if (lng < -180) lng += 360;
    setState(() {
      _current = LatLng(lat, lng);
      _target = _current;
    });
    _send(mps: mps, bearing: (b * 180 / math.pi + 360) % 360);
    Store.saveLast(_current);
    _moveMap(_current);
  }

  void _pick(LatLng p, {double? zoom}) {
    if (_active && _locked) {
      _snack('الموقع مثبّت، فك التثبيت الأول');
      return;
    }
    setState(() {
      _target = p;
      _results = [];
    });
    if (_active) {
      _current = p;
      _send();
    }
    Store.saveLast(p);
    if (zoom != null) _moveMap(p, zoom);
  }

  Future<void> _search() async {
    final q = _searchCtl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final r = await SearchService.search(q);
      if (!mounted) return;
      setState(() => _results = r);
      if (r.isEmpty) _snack('مفيش نتائج');
    } catch (_) {
      if (mounted) _snack('فشل البحث، اتأكد من النت');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _saveFavorite() async {
    final ctl = TextEditingController(
        text:
            '${_target.latitude.toStringAsFixed(4)}, ${_target.longitude.toStringAsFixed(4)}');
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حفظ في المفضلة'),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(c, ctl.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    setState(() => _favs = [..._favs, Place(name, _target)]);
    await Store.saveFavorites(_favs);
  }

  void _showFavorites() {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => _favs.isEmpty
            ? const SizedBox(
                height: 120, child: Center(child: Text('مفيش أماكن محفوظة')))
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final f in _favs)
                    ListTile(
                      leading: const Icon(Icons.star, color: Colors.amber),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.pop(c);
                        _pick(f.point, zoom: 13);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          setState(() => _favs = _favs.where((e) => e != f).toList());
                          setSheet(() {});
                          await Store.saveFavorites(_favs);
                        },
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = _active ? _current : _target;
    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _target,
            initialZoom: 12,
            minZoom: 2,
            onMapReady: () {
              _mapReady = true;
              _moveMap(_target, 12);
            },
            onTap: (_, p) => _pick(p),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.geoshift.geoshift',
            ),
            MarkerLayer(markers: [
              Marker(
                point: shown,
                width: 48,
                height: 48,
                alignment: Alignment.topCenter,
                child: Icon(Icons.location_pin,
                    size: 48,
                    color: !_active
                        ? Colors.red
                        : (_locked ? Colors.blue : Colors.green)),
              ),
            ]),
          ],
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(28),
                child: TextField(
                  controller: _searchCtl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن مكان أو اكتب lat, lng',
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2)))
                        : IconButton(
                            icon: const Icon(Icons.search), onPressed: _search),
                  ),
                ),
              ),
              if (_results.isNotEmpty)
                Card(
                  margin: const EdgeInsets.only(top: 6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView(shrinkWrap: true, children: [
                      for (final r in _results)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _pick(r.point, zoom: 13),
                        ),
                    ]),
                  ),
                ),
              if (!_ready)
                Card(
                  color: Colors.orange.shade100,
                  margin: const EdgeInsets.only(top: 6),
                  child: ListTile(
                    dense: true,
                    title: const Text('فعّل GeoShift كتطبيق موقع وهمي'),
                    subtitle: const Text('خيارات المطور ← Select mock location app'),
                    trailing: TextButton(
                        onPressed: MockChannel.openDeveloperSettings,
                        child: const Text('افتح')),
                  ),
                ),
            ]),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_active && !_locked)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Joystick(onChanged: (v) => _stick = v),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        '${shown.latitude.toStringAsFixed(5)}, ${shown.longitude.toStringAsFixed(5)}',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<double>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 5, label: Text('مشي')),
                          ButtonSegment(value: 15, label: Text('عجلة')),
                          ButtonSegment(value: 50, label: Text('عربية')),
                          ButtonSegment(value: 100, label: Text('سريع')),
                        ],
                        selected: {_kmh},
                        onSelectionChanged: (s) => setState(() => _kmh = s.first),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        IconButton.outlined(
                            tooltip: 'حفظ',
                            onPressed: _saveFavorite,
                            icon: const Icon(Icons.star_border)),
                        IconButton.outlined(
                            tooltip: 'المفضلة',
                            onPressed: _showFavorites,
                            icon: const Icon(Icons.list)),
                        if (_active)
                          IconButton.outlined(
                              tooltip: _locked ? 'فك التثبيت' : 'تثبيت',
                              onPressed: _toggleLock,
                              icon: Icon(_locked ? Icons.lock : Icons.lock_open)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: _active
                                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                                : null,
                            onPressed: _active ? _stop : _start,
                            icon: Icon(_active ? Icons.stop : Icons.play_arrow),
                            label: Text(_active ? 'إيقاف' : 'ابدأ الموقع الوهمي'),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
