import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../api.dart';
import '../config.dart';
import '../models.dart';

/// Search, or tap on the map, to choose a place.
class PlacePickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initial;
  const PlacePickerScreen({super.key, required this.title, this.initial});

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  final TextEditingController _q = TextEditingController();
  final MapController _map = MapController();
  Timer? _debounce;
  List<PlaceResult> _results = [];
  bool _loading = false;
  String? _error;
  LatLng? _picked;
  String _pickedName = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 800), _search);
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
        if (r.isEmpty) _error = 'No results. Try another name or tap on the map.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(LatLng p, String name) {
    setState(() {
      _picked = p;
      _pickedName = name;
      _results = [];
    });
    FocusScope.of(context).unfocus();
    try {
      _map.move(p, 16);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initial ?? AppConfig.indiaCenter;
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
                hintText: 'Type a hospital / place name',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Text(_error!, style: const TextStyle(color: Colors.deepOrange)),
            ),
          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _results[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.place_outlined),
                    title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _pick(r.point, r.name),
                  );
                },
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: center,
                initialZoom: widget.initial == null ? 5 : 14,
                onTap: (tapPos, point) => _pick(
                  point,
                  'Location picked on map (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})',
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
                RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _picked == null
                          ? null
                          : () => Navigator.pop(context, PlaceResult(_pickedName, _picked!)),
                      icon: const Icon(Icons.check),
                      label: const Text('Select this place'),
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
