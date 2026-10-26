import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';

/// A quick list button, for example "Hospitals".
class PlaceChip {
  final String label;
  final String category; // hospital | police | transport | market | religious | education | landmark | area
  final Color color;
  const PlaceChip(this.label, this.category, this.color);
}

const List<List<String>> kPlaceTypes = [
  ['hospital', 'Hospital'],
  ['police', 'Police station / post'],
  ['transport', 'Railway / Bus stand'],
  ['market', 'Chowk / Market'],
  ['religious', 'Temple / Mosque / Church'],
  ['education', 'School / College'],
  ['landmark', 'Famous place'],
  ['area', 'Area / Colony'],
];

IconData _iconFor(String category) {
  switch (category) {
    case 'hospital':
      return Icons.local_hospital;
    case 'police':
      return Icons.local_police;
    case 'transport':
      return Icons.directions_railway;
    case 'market':
      return Icons.storefront;
    case 'religious':
      return Icons.temple_hindu;
    case 'education':
      return Icons.school;
    case 'landmark':
      return Icons.flag;
    case 'area':
      return Icons.location_city;
    default:
      return Icons.place_outlined;
  }
}

Color _colorFor(String category) {
  switch (category) {
    case 'hospital':
      return Colors.red;
    case 'police':
      return Colors.blue;
    case 'transport':
      return Colors.indigo;
    case 'market':
      return Colors.brown;
    case 'religious':
      return Colors.orange;
    case 'education':
      return Colors.teal;
    default:
      return Colors.blueGrey;
  }
}

String _distText(int? m) {
  if (m == null) return '';
  if (m < 1000) return '$m m away';
  return '${(m / 1000).toStringAsFixed(1)} km away';
}

/// Search a saved place, pick one from the list, or tap on the map.
class PlacePickerScreen extends StatefulWidget {
  final String title;
  final String hint;
  final LatLng? initial;
  final List<PlaceChip> chips;
  const PlacePickerScreen({
    super.key,
    required this.title,
    required this.chips,
    this.hint = 'Type a place name',
    this.initial,
  });

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final TextEditingController _q = TextEditingController();
  final MapController _map = MapController();
  Timer? _debounce;
  List<PlaceResult> _results = [];
  List<PlaceResult> _nearby = [];
  int _chip = 0;
  bool _loading = false;
  bool _loadingNearby = false;
  String? _error;
  LatLng? _picked;
  String _pickedName = '';
  bool _pickedSaved = true; // true = already in the saved places list

  @override
  void initState() {
    super.initState();
    if (widget.chips.isNotEmpty) _loadNearby(0);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadNearby(int i) async {
    setState(() {
      _chip = i;
      _loadingNearby = true;
    });
    try {
      final r = await Api.I.nearby(widget.chips[i].category, near: widget.initial);
      if (!mounted) return;
      setState(() => _nearby = r);
    } catch (_) {
      if (mounted) setState(() => _nearby = []);
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    if (v.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 600), _search);
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.I.geocode(q, near: widget.initial);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) {
          _error = 'No place found. Try another name, or tap on the map and save the place.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(LatLng p, String name, {required bool saved}) {
    setState(() {
      _picked = p;
      _pickedName = name;
      _pickedSaved = saved;
      _results = [];
    });
    FocusScope.of(context).unfocus();
    try {
      _map.move(p, 16);
    } catch (_) {}
  }

  Future<void> _savePlace() async {
    final p = _picked;
    if (p == null) return;
    final nameCtrl = TextEditingController();
    String type = widget.chips.isNotEmpty ? widget.chips[0].category : 'landmark';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Save this place'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('It will show up in search for everyone.'),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Place name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Type of place', border: OutlineInputBorder()),
                items: kPlaceTypes
                    .map((t) => DropdownMenuItem(value: t[0], child: Text(t[1])))
                    .toList(),
                onChanged: (v) => setD(() => type = v ?? type),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: textColor(BtnColors.teal),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: solidButton(BtnColors.purple),
              onPressed: () {
                if (nameCtrl.text.trim().length < 2) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    if (ok != true || name.length < 2 || !mounted) return;
    try {
      await Api.I.savePlace(name, type, p);
      if (!mounted) return;
      setState(() {
        _pickedName = name;
        _pickedSaved = true;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved. This place will now show in search.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _row(PlaceResult r) {
    final sub = <String>[];
    if (r.distance != null) sub.add(_distText(r.distance));
    sub.add(r.local ? 'Saved place' : 'From map search');
    return ListTile(
      dense: true,
      leading: Icon(_iconFor(r.category), color: _colorFor(r.category)),
      title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub.join(' • '), style: const TextStyle(fontSize: 12)),
      onTap: () => _pick(r.point, r.name, saved: r.local),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initial ?? AppConfig.indiaCenter;
    final typing = _q.text.trim().isNotEmpty;
    final List<PlaceResult> shown = _results.isNotEmpty ? _results : (typing ? <PlaceResult>[] : _nearby);
    final String heading = _results.isNotEmpty
        ? 'Search results'
        : (typing || widget.chips.isEmpty ? '' : 'Saved places: ${widget.chips[_chip].label}');

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        style: IconButton.styleFrom(backgroundColor: BtnColors.cyan, foregroundColor: Colors.white),
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _search,
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (widget.chips.isNotEmpty)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.chips.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final c = widget.chips[i];
                  final on = _chip == i;
                  return FilledButton.icon(
                    style: solidButton(c.color, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6))
                        .copyWith(side: WidgetStatePropertyAll(BorderSide(color: on ? Colors.black87 : Colors.transparent, width: 2))),
                    onPressed: () {
                      _q.clear();
                      setState(() {
                        _results = [];
                        _error = null;
                      });
                      _loadNearby(i);
                    },
                    icon: Icon(_iconFor(c.category), size: 18),
                    label: Text(c.label),
                  );
                },
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
            ),
          if (heading.isNotEmpty || _loadingNearby)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(children: [
                Expanded(child: Text(heading, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                if (_loadingNearby && _results.isEmpty)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
            ),
          if (shown.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 230),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: shown.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _row(shown[i]),
              ),
            )
          else if (!typing && !_loadingNearby && widget.chips.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text('No saved places in this list yet. Search by name, or tap on the map.',
                  style: TextStyle(color: Colors.black54, fontSize: 13)),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: widget.initial == null ? 5 : 14,
                onTap: (tapPos, point) => _pick(
                  point,
                  'Point on map (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})',
                  saved: false,
                ),
              ),
              children: [
                TileLayer(urlTemplate: AppConfig.tileUrl, userAgentPackageName: AppConfig.packageName),
                if (_picked != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _picked!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 44),
                    ),
                  ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_picked != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_pickedName, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  if (_picked != null && !_pickedSaved)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: solidButton(BtnColors.purple),
                          onPressed: _savePlace,
                          icon: const Icon(Icons.bookmark_add),
                          label: const Text('SAVE THIS PLACE FOR NEXT TIME'),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: solidButton(BtnColors.green),
                      onPressed: _picked == null
                          ? null
                          : () => Navigator.pop(context, PlaceResult(_pickedName, _picked!)),
                      icon: const Icon(Icons.check),
                      label: const Text('SELECT THIS PLACE'),
                    ),
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
