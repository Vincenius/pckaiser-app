/// A dynasty member (ORIGINAL_GAME.md §2). The original uses raw pointers;
/// here every person has a stable integer [id] and references are by id.
class Person {
  Person({
    required this.id,
    required this.name,
    required this.age,
    required this.dynasty,
    required this.gender,
    this.spouseId,
    List<int>? childrenIds,
  }) : childrenIds = childrenIds ?? [];

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as int,
        name: json['name'] as String,
        age: json['age'] as int,
        dynasty: json['dynasty'] as int,
        gender: json['gender'] as int,
        spouseId: json['spouseId'] as int?,
        childrenIds: (json['childrenIds'] as List?)?.cast<int>(),
      );

  final int id;
  String name;
  int age;

  /// Dynasty slot index (1–30).
  int dynasty;

  /// 0 = male, 1 = female.
  final int gender;

  int? spouseId;

  /// Created lazily in the original; insertion order matters for succession.
  final List<int> childrenIds;

  bool get isMale => gender == 0;

  Person copy() => Person(
        id: id,
        name: name,
        age: age,
        dynasty: dynasty,
        gender: gender,
        spouseId: spouseId,
        childrenIds: List.of(childrenIds),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'dynasty': dynasty,
        'gender': gender,
        'spouseId': spouseId,
        'childrenIds': childrenIds,
      };
}
