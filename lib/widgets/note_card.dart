import 'package:flutter/material.dart';

import '../models/note_model.dart';
import '../features/notes/note_details_screen.dart';

class NoteCard extends StatelessWidget {
  final NoteModel note;

  const NoteCard({
    super.key,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(note.title),

        subtitle: Text(
          note.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),

        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  NoteDetailsScreen(
                note: note,
              ),
            ),
          );  
        
      },
      ),
    );
  }
}