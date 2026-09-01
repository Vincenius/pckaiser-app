/// The Stammbaum (family tree) modal — the ruling house of one dynasty
/// drawn as a generational tree instead of a flat list.
///
/// The engine keeps only LIVING people (`handleDeath` removes the person and
/// every child link), so the tree always shows the house as it stands today:
/// couples share one box, their children hang below them. Parentage is
/// reconstructed from `Person.childrenIds` — the engine's only downward link
/// — inverted into a child → parents index here.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:game_core/game_core.dart' as gc;

import '../l10n/labels.dart';
import '../l10n/strings.dart';

// --- Layout metrics ---------------------------------------------------
// Layout units are logical pixels at zoom 1.0; the InteractiveViewer
// scales the whole canvas from there.

const double _cardW = 124;
const double _cardH = 60;

/// Gap between the two cards of a married couple (holds the ⚭ link).
const double _coupleGap = 16;

/// Horizontal gap between sibling subtrees, and between separate roots.
const double _siblingGap = 20;
const double _rootGap = 56;

/// Vertical gap between generations (the connector elbows live in it).
const double _rowGap = 46;
const double _rowPitch = _cardH + _rowGap;

/// Padding around the whole canvas so cards never touch the viewport edge.
const double _canvasPad = 32;

// --- Model ------------------------------------------------------------

/// One box of the tree: a member of the house plus, when married, their
/// spouse. The spouse may belong to a foreign dynasty (a political match)
/// or to the same one (a commoner wed into the house).
class FamilyNode {
  FamilyNode(this.person, this.spouse);

  final gc.Person person;
  final gc.Person? spouse;
  final List<FamilyNode> children = [];

  /// Left edge / top edge of the box in canvas coordinates.
  double x = 0;
  double y = 0;

  /// Width of the box itself (one card, or a couple plus its link gap).
  double get width => spouse == null ? _cardW : _cardW * 2 + _coupleGap;

  double get centerX => x + width / 2;

  /// Width of the whole subtree below (and including) this box — the
  /// scratch value of the two-pass tidy layout.
  double _subtreeW = 0;
}

/// A laid-out tree, ready to paint: the roots (a house can have several
/// once the common ancestor has died), every node flattened for painting,
/// and the canvas size in layout units.
class FamilyTree {
  FamilyTree(this.roots, this.nodes, this.size, this.generations);

  final List<FamilyNode> roots;
  final List<FamilyNode> nodes;
  final Size size;
  final int generations;

  bool get isEmpty => nodes.isEmpty;

  /// Total people drawn — members plus the spouses married into the house.
  int get personCount =>
      nodes.length + nodes.where((n) => n.spouse != null).length;
}

/// Builds and lays out the tree of dynasty [slot].
///
/// Membership comes from `Dynasty.memberIds` (living members only, commoner
/// spouses included); foreign spouses are pulled in from `state.persons`
/// because they are drawn beside their partner but belong to their own house.
FamilyTree buildFamilyTree(gc.GameState state, int slot) {
  final members = <int, gc.Person>{
    for (final id in state.dynasty(slot).memberIds)
      if (state.persons[id] != null) id: state.persons[id]!,
  };

  // Invert the engine's downward links: child id → parent ids. Built over
  // ALL persons, since one parent of a member can be a foreign spouse.
  final parentsOf = <int, List<int>>{};
  for (final p in state.persons.values) {
    for (final childId in p.childrenIds) {
      (parentsOf[childId] ??= []).add(p.id);
    }
  }
  bool hasParentInHouse(int id) =>
      (parentsOf[id] ?? const []).any(members.containsKey);
  bool rules(int id) => state.realms.any((r) => r.rulerId == id);

  // --- Pair up the couples ------------------------------------------
  // Every married member is drawn beside their spouse. Exactly one of the
  // two anchors the box (carries the line); the other is absorbed into it.
  // Only a commoner marriage puts BOTH partners in this house — then the
  // partner born into it anchors (parent in the house, else the ruler,
  // else the older id, which is the earlier-created person).
  final absorbed = <int>{};
  final nodes = <int, FamilyNode>{};
  for (final entry in members.entries) {
    final person = entry.value;
    if (absorbed.contains(person.id)) continue;
    final spouse = state.persons[person.spouseId];
    if (spouse != null && members.containsKey(spouse.id)) {
      final anchor = _anchorOf(person, spouse, hasParentInHouse, rules);
      final partner = identical(anchor, person) ? spouse : person;
      absorbed.add(partner.id);
      nodes.remove(partner.id);
      nodes[anchor.id] = FamilyNode(anchor, partner);
    } else {
      nodes[person.id] = FamilyNode(person, spouse);
    }
  }

  // --- Hang the children under their parents --------------------------
  // A couple's children are listed on BOTH partners (the engine double-links
  // them for exactly this display), so the union is deduplicated.
  final claimed = <int>{};
  for (final node in nodes.values) {
    final childIds = <int>{
      ...node.person.childrenIds,
      ...?node.spouse?.childrenIds,
    };
    for (final childId in childIds) {
      final child = nodes[childId];
      // Missing: dead, absorbed as a spouse, or born into another house.
      if (child == null || child == node) continue;
      if (!claimed.add(childId)) continue; // already placed elsewhere
      node.children.add(child);
    }
  }
  // Defensive: a save with an odd link must never produce a cycle that
  // hangs the layout recursion.
  _breakCycles(nodes.values.toList(), claimed);

  final roots = [
    for (final node in nodes.values)
      if (!claimed.contains(node.person.id)) node,
  ]..sort(_bySeniority);
  for (final node in nodes.values) {
    node.children.sort(_bySeniority);
  }

  // --- Two-pass tidy layout ------------------------------------------
  for (final root in roots) {
    _measure(root);
  }
  var cursor = _canvasPad;
  for (final root in roots) {
    _place(root, cursor, 0);
    cursor += root._subtreeW + _rootGap;
  }
  final width = roots.isEmpty
      ? 0.0
      : cursor - _rootGap + _canvasPad;
  final all = nodes.values.toList();
  final generations = all.isEmpty
      ? 0
      : (all.map((n) => n.y).reduce(math.max) ~/ _rowPitch) + 1;
  final height = all.isEmpty
      ? 0.0
      : all.map((n) => n.y).reduce(math.max) + _cardH + _canvasPad;
  return FamilyTree(roots, all, Size(width, height), generations);
}

gc.Person _anchorOf(
  gc.Person a,
  gc.Person b,
  bool Function(int) hasParentInHouse,
  bool Function(int) rules,
) {
  if (hasParentInHouse(a.id) != hasParentInHouse(b.id)) {
    return hasParentInHouse(a.id) ? a : b;
  }
  if (rules(a.id) != rules(b.id)) return rules(a.id) ? a : b;
  return a.id <= b.id ? a : b;
}

/// Eldest first — the reading order the succession chain follows.
int _bySeniority(FamilyNode a, FamilyNode b) {
  final byAge = b.person.age.compareTo(a.person.age);
  return byAge != 0 ? byAge : a.person.id.compareTo(b.person.id);
}

/// Cuts any child link that would make a node its own ancestor, so the
/// layout recursion always terminates.
void _breakCycles(List<FamilyNode> nodes, Set<int> claimed) {
  for (final node in nodes) {
    node.children.removeWhere((child) {
      if (!_reaches(child, node, 0)) return false;
      claimed.remove(child.person.id);
      return true;
    });
  }
}

bool _reaches(FamilyNode from, FamilyNode target, int depth) {
  if (identical(from, target)) return true;
  if (depth > 64) return true; // pathological save — treat as a cycle
  for (final child in from.children) {
    if (_reaches(child, target, depth + 1)) return true;
  }
  return false;
}

/// Pass 1: the width every subtree needs.
void _measure(FamilyNode node) {
  if (node.children.isEmpty) {
    node._subtreeW = node.width;
    return;
  }
  var total = 0.0;
  for (final child in node.children) {
    _measure(child);
    total += child._subtreeW + _siblingGap;
  }
  total -= _siblingGap;
  node._subtreeW = math.max(node.width, total);
}

/// Pass 2: place the subtree in [left], parent centred over its children.
void _place(FamilyNode node, double left, int depth) {
  node.x = left + (node._subtreeW - node.width) / 2;
  node.y = _canvasPad + depth * _rowPitch;
  if (node.children.isEmpty) return;
  var total = 0.0;
  for (final child in node.children) {
    total += child._subtreeW + _siblingGap;
  }
  total -= _siblingGap;
  var cursor = left + (node._subtreeW - total) / 2;
  for (final child in node.children) {
    _place(child, cursor, depth + 1);
    cursor += child._subtreeW + _siblingGap;
  }
}

// --- Entry point ------------------------------------------------------

/// Opens the Stammbaum of dynasty [slot] as a full-screen modal that can be
/// panned and pinch-zoomed. Dynasty composition is public information, so
/// foreign houses may be inspected too (Info → Dynastien).
Future<void> showFamilyTree(
  BuildContext context,
  gc.GameState state,
  int slot,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: FamilyTreeView(state: state, slot: slot),
    ),
  );
}

// --- View -------------------------------------------------------------

/// The modal's body: header, the pan/zoom canvas, and the legend.
class FamilyTreeView extends StatefulWidget {
  const FamilyTreeView({super.key, required this.state, required this.slot});

  final gc.GameState state;
  final int slot;

  @override
  State<FamilyTreeView> createState() => _FamilyTreeViewState();
}

class _FamilyTreeViewState extends State<FamilyTreeView> {
  final TransformationController _controller = TransformationController();
  late final FamilyTree _tree = buildFamilyTree(widget.state, widget.slot);
  late final int? _heirId =
      gc.presumptiveHeir(widget.state, widget.slot)?.id;
  Size? _viewport;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Frames the tree in [viewport].
  ///
  /// The opening view never shrinks below [_readableScale] — a wide house
  /// squeezed into a phone would be unreadable — and then anchors on the
  /// ruler's box at the top, which is where the eye starts. [whole] (the
  /// "fit" button) drops that floor and centres the entire tree instead.
  /// Neither ever zooms IN past 1.0: a two-person house is not a billboard.
  void _fit(Size viewport, {bool whole = false}) {
    if (_tree.isEmpty) return;
    final fit = math.min(
      viewport.width / _tree.size.width,
      viewport.height / _tree.size.height,
    );
    final scale = whole
        ? fit.clamp(_minScale, 1.0)
        : fit.clamp(_readableScale, 1.0);
    final treeW = _tree.size.width * scale;
    final treeH = _tree.size.height * scale;

    final anchor = whole ? null : _rulerNode;
    double dx;
    if (treeW <= viewport.width || anchor == null) {
      dx = (viewport.width - treeW) / 2;
    } else {
      // Centre on the ruler, but never past either edge of the canvas.
      dx = (viewport.width / 2 - anchor.centerX * scale)
          .clamp(viewport.width - treeW, 0.0);
    }
    // A tree taller than the viewport starts at its oldest generation.
    final dy = treeH <= viewport.height ? (viewport.height - treeH) / 2 : 0.0;

    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// The box holding the realm's ruler — the natural anchor of the view.
  FamilyNode? get _rulerNode {
    final rulerId = widget.state.realm(widget.slot).rulerId;
    for (final node in _tree.nodes) {
      if (node.person.id == rulerId || node.spouse?.id == rulerId) return node;
    }
    return _tree.roots.isEmpty ? null : _tree.roots.first;
  }

  /// Hard floor for pinch-zoom (a 30-member house must still fit on screen).
  static const double _minScale = 0.15;

  /// Floor for the OPENING view — below this the card text stops reading.
  static const double _readableScale = 0.55;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Column(
        children: [
          _header(theme, scheme),
          Expanded(
            child: DecoratedBox(
              // A soft glow under the tree so the pan area reads as a
              // canvas rather than as empty screen.
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.9,
                  colors: [
                    Color.alphaBlend(
                      scheme.primary.withValues(alpha: 0.10),
                      scheme.surface,
                    ),
                    scheme.surface,
                  ],
                ),
              ),
              child: _tree.isEmpty
                  ? Center(child: Text(tr('menus.familyTreeEmpty')))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final viewport = constraints.biggest;
                        if (_viewport != viewport) {
                          _viewport = viewport;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _fit(viewport);
                          });
                        }
                        return InteractiveViewer(
                          transformationController: _controller,
                          // Unconstrained: the canvas is bigger than the
                          // viewport and pans freely in both axes.
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(600),
                          minScale: _minScale,
                          maxScale: 3,
                          child: SizedBox(
                            width: _tree.size.width,
                            height: _tree.size.height,
                            child: _canvas(scheme),
                          ),
                        );
                      },
                    ),
            ),
          ),
          _legend(theme, scheme),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('menus.familyTreeOf', {
                      'realm': realmName(widget.slot),
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('menus.familyTreeStats', {
                      'n': _tree.personCount,
                      'g': _tree.generations,
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('menus.familyTreeFit'),
              icon: const Icon(Icons.fit_screen),
              onPressed: () {
                final viewport = _viewport;
                if (viewport != null) _fit(viewport, whole: true);
              },
            ),
            IconButton(
              tooltip: tr('menus.back'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _canvas(ColorScheme scheme) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ConnectorPainter(
              _tree,
              scheme.onSurfaceVariant.withValues(alpha: 0.5),
              scheme.primary.withValues(alpha: 0.7),
            ),
          ),
        ),
        for (final node in _tree.nodes) ..._boxOf(node, scheme),
      ],
    );
  }

  /// The one or two cards of [node], plus the ⚭ glyph between a couple.
  List<Widget> _boxOf(FamilyNode node, ColorScheme scheme) {
    final spouse = node.spouse;
    return [
      Positioned(
        left: node.x,
        top: node.y,
        child: _PersonCard(
          person: node.person,
          state: widget.state,
          houseSlot: widget.slot,
          isRuler: _rulesSomewhere(node.person.id),
          isHeir: node.person.id == _heirId,
          isSpouse: false,
        ),
      ),
      if (spouse != null) ...[
        Positioned(
          left: node.x + _cardW,
          top: node.y + _cardH / 2 - 9,
          width: _coupleGap,
          child: Icon(
            Icons.favorite,
            size: 13,
            color: scheme.primary.withValues(alpha: 0.8),
          ),
        ),
        Positioned(
          left: node.x + _cardW + _coupleGap,
          top: node.y,
          child: _PersonCard(
            person: spouse,
            state: widget.state,
            houseSlot: widget.slot,
            isRuler: _rulesSomewhere(spouse.id),
            isHeir: spouse.id == _heirId,
            isSpouse: true,
          ),
        ),
      ],
    ];
  }

  bool _rulesSomewhere(int personId) =>
      widget.state.realms.any((r) => r.rulerId == personId);

  Widget _legend(ThemeData theme, ColorScheme scheme) {
    final style = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    Widget item(IconData icon, Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                item(
                  Icons.workspace_premium,
                  _rulerGold,
                  tr('menus.legendRuler'),
                ),
                item(Icons.star, _heirColor(scheme), tr('menus.legendHeir')),
                item(
                  Icons.favorite,
                  scheme.primary,
                  tr('menus.legendSpouse'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('menus.familyTreeHint'), style: style),
          ],
        ),
      ),
    );
  }
}

/// The crown gold — a fixed accent (not from the scheme) so the ruler reads
/// as gilded against the brown-seeded dark palette.
const Color _rulerGold = Color(0xFFE0B44C);

Color _heirColor(ColorScheme scheme) => scheme.tertiary;

// --- Cards ------------------------------------------------------------

/// One person's card. Members of the displayed house get the solid look;
/// people married into it are drawn lighter with their home realm.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.state,
    required this.houseSlot,
    required this.isRuler,
    required this.isHeir,
    required this.isSpouse,
  });

  final gc.Person person;
  final gc.GameState state;
  final int houseSlot;
  final bool isRuler;
  final bool isHeir;
  final bool isSpouse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = isRuler
        ? _rulerGold
        : isHeir
        ? _heirColor(scheme)
        : isSpouse
        ? scheme.outlineVariant
        : scheme.outline;
    return Container(
      width: _cardW,
      height: _cardH,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isSpouse
            ? scheme.surfaceContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: border,
          width: isRuler || isHeir ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                person.isMale ? Icons.male : Icons.female,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isRuler)
                const Icon(
                  Icons.workspace_premium,
                  size: 14,
                  color: _rulerGold,
                )
              else if (isHeir)
                Icon(Icons.star, size: 13, color: _heirColor(scheme)),
            ],
          ),
          const SizedBox(height: 3),
          // Age and role share one line so the card stays two rows tall at
          // every text scale; the role yields first when space runs short.
          Row(
            children: [
              Text(
                tr('menus.ageYears', {'n': person.age}),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Flexible(
                child: Text(
                  ' · ${_roleLine()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isRuler
                        ? _rulerGold
                        : isHeir
                        ? _heirColor(scheme)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Bottom line: the strongest fact about this person — their crown, their
  /// place in the succession, or where they married in from.
  String _roleLine() {
    if (isRuler) {
      final realm = state.realms.firstWhere((r) => r.rulerId == person.id);
      final title = titleName(realm.titleClass);
      // A ruler of a FOREIGN realm (a spouse, or a member who inherited
      // elsewhere) is named with their realm, so the crown is not mistaken
      // for the one on display.
      return realm.slot == houseSlot
          ? title
          : '$title${tr('menus.ofRealm', {'realm': realmName(realm.slot)})}';
    }
    if (isHeir) return tr('menus.legendHeir');
    if (isSpouse) {
      return person.dynasty == houseSlot
          ? tr('menus.commonerTag')
          : realmName(person.dynasty);
    }
    if (state.kurfuerstenIds.contains(person.id)) {
      return tr('menus.legendElector');
    }
    return person.spouseId == null ? tr('menus.single') : tr('menus.married');
  }
}

// --- Connectors -------------------------------------------------------

/// Draws the descent lines: a stem down from each couple, a horizontal bus
/// across their children, and a drop into every child's top edge. Elbows
/// are rounded so the tree reads as drawn rather than as a wire diagram.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter(this.tree, this.lineColor, this.marriageColor);

  final FamilyTree tree;
  final Color lineColor;
  final Color marriageColor;

  static const double _radius = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final marriage = Paint()
      ..color = marriageColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    for (final node in tree.nodes) {
      // The marriage bar between the two cards of a couple.
      if (node.spouse != null) {
        final y = node.y + _cardH / 2;
        canvas.drawLine(
          Offset(node.x + _cardW, y),
          Offset(node.x + _cardW + _coupleGap, y),
          marriage,
        );
      }
      if (node.children.isEmpty) continue;

      final stemX = node.centerX;
      final top = node.y + _cardH;
      final busY = top + _rowGap / 2;
      canvas.drawLine(Offset(stemX, top), Offset(stemX, busY - 1), line);

      final path = Path();
      for (final child in node.children) {
        final cx = child.centerX;
        final cy = child.y;
        if ((cx - stemX).abs() < 0.5) {
          path
            ..moveTo(cx, busY)
            ..lineTo(cx, cy);
          continue;
        }
        // Bus out to the child's column, then a rounded elbow down.
        final dir = cx > stemX ? 1.0 : -1.0;
        path
          ..moveTo(stemX, busY)
          ..lineTo(cx - dir * _radius, busY)
          ..quadraticBezierTo(cx, busY, cx, busY + _radius)
          ..lineTo(cx, cy);
      }
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.tree != tree ||
      old.lineColor != lineColor ||
      old.marriageColor != marriageColor;
}
