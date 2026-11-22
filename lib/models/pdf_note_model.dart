class PdfNoteModel {
  final String id;
  final String fileName;
  final String extractedText;
  final String userId;

  PdfNoteModel({
    required this.id,
    required this.fileName,
    required this.extractedText,
    required this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'extractedText': extractedText,
      'userId': userId,
    };
  }
}
