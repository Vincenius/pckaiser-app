import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_core/game_core.dart' as gc;
import 'package:pckaiser/widgets/family_tree.dart';

/// The Stammbaum modal (2026-09-01): the tree is reconstructed from the
/// engine's downward `childrenIds` links alone, so these tests pin the
/// shapes that reconstruction has to get right — couples in one box,
/// children under the RIGHT couple, and one root per orphaned line.
gc.GameState _game() => gc.startGame(
  gc.newGame(
    gc.GameSetup(
      humans: [
        gc.HumanPlayerSetup(
          founderName: 'Otto',
          gender: 0,
          countrySlot: 1,
          dorfName: 'Burg',
        ),
      ],
      reformationYear: 1020,
      ottomanYear: 1040,
      seed: 2026,
    ),
  ),
  gc.Rng(1),
).state;

gc.Person _add(
  gc.GameState state,
  int slot,
  String name,
  int gender,
  int age, {
  gc.Person? father,
  gc.Person? mother,
}) {
  final person = gc.Person(
    id: state.nextPersonId++,
    name: name,
    age: age,
    dynasty: slot,
    gender: gender,
  );
  state.persons[person.id] = person;
  state.dynasty(slot).memberIds.add(person.id);
  // The engine double-links a couple's children onto both parents; the
  // tree has to deduplicate that, so the fixtures reproduce it.
  father?.childrenIds.add(person.id);
  mother?.childrenIds.add(person.id);
  return person;
}

FamilyNode _nodeFor(FamilyTree tree, gc.Person person) =>
    tree.nodes.firstWhere((n) => n.person.id == person.id);

void main() {
  group('buildFamilyTree', () {
    test('a lone founder is a single childless root', () {
      final state = _game();
      final tree = buildFamilyTree(state, 1);
      expect(tree.nodes, hasLength(1));
      expect(tree.roots, hasLength(1));
      expect(tree.generations, 1);
      expect(tree.personCount, 1);
      expect(tree.size.width, greaterThan(0));
    });

    test('a couple shares one box and their children hang below it', () {
      final state = _game();
      final ruler = state.persons[state.realm(1).rulerId]!;
      final foreign = state.persons[state.realm(2).rulerId]!;
      gc.marry(state, ruler, foreign, <gc.GameEvent>[]);
      final son = _add(state, 1, 'Heinrich', 0, 18,
          father: ruler, mother: foreign);
      final daughter = _add(state, 1, 'Adelheid', 1, 22,
          father: ruler, mother: foreign);

      final tree = buildFamilyTree(state, 1);
      // The foreign wife is drawn, not counted as a node of her own.
      expect(tree.nodes, hasLength(3));
      expect(tree.personCount, 4);
      expect(tree.roots, hasLength(1));

      final root = tree.roots.single;
      expect(root.person.id, ruler.id);
      expect(root.spouse?.id, foreign.id);
      // Double-linked children appear exactly once, eldest first.
      expect(
        root.children.map((n) => n.person.id),
        [daughter.id, son.id],
      );
      expect(tree.generations, 2);
      // The parent box sits centred above its children's row.
      expect(_nodeFor(tree, son).y, greaterThan(root.y));
      expect(
        root.centerX,
        closeTo(
          (_nodeFor(tree, daughter).centerX + _nodeFor(tree, son).centerX) / 2,
          0.01,
        ),
      );
    });

    test('a commoner spouse joins the member\'s box, not a second root', () {
      final state = _game();
      final ruler = state.persons[state.realm(1).rulerId]!;
      final son = _add(state, 1, 'Heinrich', 0, 18, father: ruler);
      // §14.1: the commoner is created INTO the house, so both partners
      // are members — the one born into the line must anchor the box.
      final commoner = gc.createCommonerSpouse(state, son, gc.Rng(3));
      gc.marry(state, son, commoner, <gc.GameEvent>[]);

      final tree = buildFamilyTree(state, 1);
      expect(tree.roots, hasLength(1));
      expect(tree.roots.single.person.id, ruler.id);
      final sonNode = _nodeFor(tree, son);
      expect(sonNode.spouse?.id, commoner.id);
      expect(tree.nodes.any((n) => n.person.id == commoner.id), isFalse);
    });

    test('an orphaned generation forms its own root', () {
      final state = _game();
      final ruler = state.persons[state.realm(1).rulerId]!;
      final cousin = _add(state, 1, 'Kunigunde', 1, 40);
      expect(cousin.dynasty, 1);

      final tree = buildFamilyTree(state, 1);
      expect(tree.roots, hasLength(2));
      // Roots never overlap: the second starts right of the first.
      final a = _nodeFor(tree, ruler);
      final b = _nodeFor(tree, cousin);
      expect((a.centerX - b.centerX).abs(), greaterThan(a.width));
    });

    test('an extinct house yields an empty tree', () {
      final state = _game();
      state.dynasty(1).memberIds.clear();
      final tree = buildFamilyTree(state, 1);
      expect(tree.isEmpty, isTrue);
      expect(tree.size, Size.zero);
    });
  });

  testWidgets('the modal shows the house, the crown and pans/zooms', (
    tester,
  ) async {
    final state = _game();
    final ruler = state.persons[state.realm(1).rulerId]!;
    final heir = _add(state, 1, 'Heinrich', 0, 18, father: ruler);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6D4C2F),
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(body: FamilyTreeView(state: state, slot: 1)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(ruler.name), findsOneWidget);
    expect(find.text(heir.name), findsOneWidget);
    expect(find.text('2 Personen — 2 Generationen'), findsOneWidget);
    // The ruler wears the crown; the son is flagged as the Thronfolger
    // (card badge plus the legend entry).
    expect(find.byIcon(Icons.workspace_premium), findsNWidgets(2));
    // Once on the son's card ("18 Jahre · Thronfolger"), once in the legend.
    expect(find.textContaining('Thronfolger'), findsNWidgets(2));
    expect(find.text('Thronfolger'), findsOneWidget);

    // Pan and zoom go through one InteractiveViewer over the whole canvas.
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.constrained, isFalse);
    expect(viewer.maxScale, greaterThan(1));

    final before = viewer.transformationController!.value.clone();
    await tester.drag(find.byType(InteractiveViewer), const Offset(-60, -40));
    await tester.pump();
    expect(viewer.transformationController!.value, isNot(before));
  });
}
