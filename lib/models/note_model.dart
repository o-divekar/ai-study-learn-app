class NoteModel {
  final String id;
  final String title;
  final String content;
  final String userId;

  NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'userId': userId,
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      userId: map['userId'],
    );
  }
}