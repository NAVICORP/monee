part of 'entry_page.dart';

// The small pieces the entry page is built from.

/// One part of a split: a category, an amount and its own note.
class _Part {
  _Part({this.categoryId, this.amount = 0, String text = ''}) : note = TextEditingController(text: text);
  String? categoryId;
  num amount;
  final TextEditingController note;
}

/// One account an entry is paid from (or received in), with its share. `id`
/// is the transaction already saved for it.
class _Pay {
  _Pay({this.id, this.accountId, this.amount = 0});
  String? id;
  String? accountId;
  num amount;
}

/// A photo on the entry: a saved one (id and path; its bytes load for the
/// thumbnail) or a new one (bytes, uploaded once the entry is saved).
class _Photo {
  _Photo({this.id, this.path, this.bytes, this.mime});
  final String? id;
  final String? path;
  Uint8List? bytes;
  final String? mime;
  bool failed = false;
}

/// Every month; Every 2 weeks, until 3 Mar 2027.
String _repeatLabel(String freq, int every, DateTime? until) {
  final unit = switch (freq) {
    'day' => 'day',
    'week' => 'week',
    'year' => 'year',
    _ => 'month',
  };
  final base = every <= 1 ? 'Every $unit' : 'Every $every ${unit}s';
  return until == null ? base : '$base, until ${dateLabel(until)}';
}

/// 0 as 12 am, 13 as 1 pm.
String _hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'am' : 'pm'}';

/// A name for a photo file that will not clash with another.
String _randomName() {
  final r = math.Random.secure();
  return List.generate(20, (_) => r.nextInt(16).toRadixString(16)).join();
}

/// A small row that opens a choice: a label over its value, like KChoice, with
/// room for something at the end. Compact rows are as wide as their words.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    this.onTap,
    this.icon,
    this.trailing,
    this.muted = false,
    this.compact = false,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? trailing;
  final bool muted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final texts = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tiny),
      const SizedBox(height: 1),
      Text(value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.bodyStrong.copyWith(fontSize: 14, color: muted ? K.muted : K.ink).merge(T.tabular)),
    ]);
    return Material(
      color: K.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: K.border2)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12, 7, trailing == null ? 12 : 6, 7),
            child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: K.ink2), const SizedBox(width: 10)],
              if (compact) texts else Expanded(child: texts),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A small pill: a note to fill in, a tag, a repeat. Can be tapped, and can
/// carry an x to take it away.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onTap, this.onClear, this.selected = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final bool selected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? K.brand600 : K.ink2;
    return Material(
      color: selected ? K.brand100 : K.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? K.brand200 : K.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(10, 5, onClear == null ? 10 : 3, 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label.copyWith(fontSize: 12.5, color: fg)),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 2),
              Semantics(
                button: true,
                label: 'Remove',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onClear,
                  child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.close_rounded, size: 15, color: fg)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// A small text action: Split, Add part, Repeat.
class _TinyButton extends StatelessWidget {
  const _TinyButton(this.label, {required this.onTap, this.icon, this.color = K.blue});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 4)],
          Text(label, maxLines: 1, style: T.label.copyWith(color: color)),
        ]),
      ),
    );
  }
}

/// Income, Expense, Transfer: the chosen one in its money colour.
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String>? onChanged;

  static const _items = [('income', 'Income'), ('expense', 'Expense'), ('transfer', 'Transfer')];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: K.surface2, borderRadius: BorderRadius.circular(999), border: Border.all(color: K.border)),
      child: Row(children: [
        for (final (k, label) in _items)
          Expanded(
            child: Semantics(
              button: true,
              selected: k == value,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onChanged == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onChanged!(k);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minHeight: 38),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: k == value ? K.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: k == value ? const [BoxShadow(color: Color(0x1A071C42), blurRadius: 6, offset: Offset(0, 2))] : null,
                  ),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.label.copyWith(
                        color: k == value ? moneyColor(k) : K.muted,
                        fontWeight: k == value ? FontWeight.w700 : FontWeight.w600,
                      )),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- time

/// A time of day from two short lists, hours and minutes: never the system picker.
Future<(int, int)?> _pickTime(BuildContext context, DateTime at) {
  return showKSheet<(int, int)>(
    context,
    title: 'Time',
    scroll: false,
    builder: (ctx) => _TimePicker(hour: at.hour, minute: at.minute, onDone: (v) => Navigator.of(ctx).pop(v)),
  );
}

class _TimePicker extends StatefulWidget {
  const _TimePicker({required this.hour, required this.minute, required this.onDone});
  final int hour;
  final int minute;
  final ValueChanged<(int, int)> onDone;

  @override
  State<_TimePicker> createState() => _TimePickerState();
}

class _TimePickerState extends State<_TimePicker> {
  static const _extent = 40.0;
  static const _view = 200.0;

  late int h = widget.hour;
  late int m = widget.minute;
  late final ScrollController hours = ScrollController(initialScrollOffset: _offset(widget.hour, 24));
  late final ScrollController minutes = ScrollController(initialScrollOffset: _offset(widget.minute, 60));

  /// Scrolled so the chosen one sits third from the top.
  static double _offset(int i, int count) => ((i - 2) * _extent).clamp(0.0, count * _extent - _view).toDouble();

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    super.dispose();
  }

  Widget _list(ScrollController c, int count, int selected, String Function(int) label, ValueChanged<int> pick) {
    return Container(
      decoration: BoxDecoration(color: K.surface, borderRadius: BorderRadius.circular(K.rMd), border: Border.all(color: K.border)),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        controller: c,
        padding: EdgeInsets.zero,
        itemExtent: _extent,
        itemCount: count,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Material(
            color: i == selected ? K.brand100 : Colors.transparent,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                pick(i);
              },
              child: Center(
                child: Text(label(i),
                    style: T.bodyStrong.copyWith(fontSize: 14, color: i == selected ? K.brand600 : K.ink2).merge(T.tabular)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Text(clock(DateTime(2000, 1, 1, h, m)), style: T.h1.merge(T.tabular))),
      const SizedBox(height: Sp.md),
      const Row(children: [
        Expanded(child: Center(child: Text('Hour', style: T.tiny))),
        SizedBox(width: Sp.md),
        Expanded(child: Center(child: Text('Minute', style: T.tiny))),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: _view,
        child: Row(children: [
          Expanded(child: _list(hours, 24, h, _hourLabel, (v) => setState(() => h = v))),
          const SizedBox(width: Sp.md),
          Expanded(child: _list(minutes, 60, m, (v) => v.toString().padLeft(2, '0'), (v) => setState(() => m = v))),
        ]),
      ),
      const SizedBox(height: Sp.lg),
      Row(children: [
        KButton(
          label: 'Now',
          kind: KButtonKind.ghost,
          small: true,
          onPressed: () {
            final n = DateTime.now();
            widget.onDone((n.hour, n.minute));
          },
        ),
        const Spacer(),
        KButton(label: 'Done', small: true, onPressed: () => widget.onDone((h, m))),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------- photos

/// A photo on its own, full screen, to zoom into.
class _PhotoView extends StatelessWidget {
  const _PhotoView(this.bytes);
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
            ),
          ),
        ),
      ),
    );
  }
}
