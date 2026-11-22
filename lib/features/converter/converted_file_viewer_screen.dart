import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';
import 'dart:convert';

import '../../core/services/document_text_service.dart';

class ConvertedFileViewerScreen extends StatefulWidget {
  final String filePath;

  const ConvertedFileViewerScreen({
    super.key,
    required this.filePath,
  });

  @override
  State<ConvertedFileViewerScreen> createState() =>
      _ConvertedFileViewerScreenState();
}

class _SheetPreview {
  final String name;
  final List<List<String>> rows;

  const _SheetPreview({
    required this.name,
    required this.rows,
  });
}

class _FilePreview {
  final String? text;
  final List<_SheetPreview> sheets;

  const _FilePreview({
    this.text,
    this.sheets = const [],
  });
}

class _ConvertedFileViewerScreenState
    extends State<ConvertedFileViewerScreen> {
  late Future<_FilePreview> _preview;
  int _selectedSheet = 0;

  String get _fileName =>
      widget.filePath.replaceAll('\\', '/').split('/').last;

  @override
  void initState() {
    super.initState();
    _preview = _load();
  }

  Future<_FilePreview> _load() async {
    final file = File(widget.filePath);

    if (!await file.exists()) {
      throw StateError('The converted file is no longer available.');
    }

    final extension = DocumentTextService.extension(_fileName);

    if (extension == 'docx') {
      final text = await DocumentTextService().extractText(
        widget.filePath,
        'docx',
      );

      return _FilePreview(text: text);
    }

    if (extension == 'xlsx') {
      return _readExcel(await file.readAsBytes());
    }

    throw StateError('This preview supports converted DOCX and XLSX files.');
  }

  _FilePreview _readExcel(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    XmlDocument readXml(String path) {
      final entry = archive.findFile(path);

      if (entry == null) {
        throw StateError('A required spreadsheet component is missing.');
      }

      if (entry.size > 10 * 1024 * 1024) {
        throw StateError('This spreadsheet is too large to preview.');
      }

      return XmlDocument.parse(utf8.decode(entry.content));
    }

    Iterable<XmlElement> elements(XmlNode node, String name) {
      return node.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == name);
    }

    // Excel may store text in a shared string table.
    final sharedStrings = <String>[];

    if (archive.findFile('xl/sharedStrings.xml') != null) {
      final sharedXml = readXml('xl/sharedStrings.xml');

      for (final item in elements(sharedXml, 'si')) {
        sharedStrings.add(
          elements(item, 't').map((part) => part.innerText).join(),
        );
      }
    }

    final workbook = readXml('xl/workbook.xml');
    final relationships = readXml('xl/_rels/workbook.xml.rels');

    final targets = <String, String>{};

    for (final relation in elements(relationships, 'Relationship')) {
      final id = relation.getAttribute('Id');
      final target = relation.getAttribute('Target');

      if (id != null &&
          target != null &&
          relation.getAttribute('TargetMode') != 'External') {
        targets[id] = target;
      }
    }

    final sheets = <_SheetPreview>[];

    for (final sheet in elements(workbook, 'sheet')) {
      String? relationshipId;

      for (final attribute in sheet.attributes) {
        if (attribute.name.local == 'id') {
          relationshipId = attribute.value;
          break;
        }
      }

      final target = targets[relationshipId];

      if (target == null) {
        throw StateError('A worksheet reference is missing.');
      }

      final resolved = Uri.parse('xl/workbook.xml').resolve(target);
      final path = resolved.path.replaceFirst(RegExp(r'^/'), '');

      if (resolved.hasScheme || !path.startsWith('xl/')) {
        throw StateError('Unsupported worksheet location.');
      }

      final sheetXml = readXml(path);
      final values = <int, Map<int, String>>{};

      var maxRow = -1;
      var maxColumn = -1;
      var cellCount = 0;

      for (final cell in elements(sheetXml, 'c')) {
        final reference = cell.getAttribute('r') ?? '';
        final match = RegExp(r'^([A-Z]+)([1-9][0-9]*)$')
            .firstMatch(reference.toUpperCase());

        if (match == null) {
          throw StateError('A spreadsheet cell reference is invalid.');
        }

        var column = 0;
        for (final letter in match.group(1)!.codeUnits) {
          column = column * 26 + letter - 64;
        }
        column--;

        final row = int.parse(match.group(2)!) - 1;

        if (row >= 1000 || column >= 100 || ++cellCount > 10000) {
          throw StateError(
            'Preview supports up to 1,000 rows, 100 columns, '
            'and 10,000 populated cells per worksheet.',
          );
        }

        final valueNodes = elements(cell, 'v').toList();
        final raw = valueNodes.isEmpty ? '' : valueNodes.first.innerText;
        final type = cell.getAttribute('t');

        String value;

        if (type == 's') {
          final index = int.tryParse(raw);

          if (index == null ||
              index < 0 ||
              index >= sharedStrings.length) {
            throw StateError('A spreadsheet text reference is invalid.');
          }

          value = sharedStrings[index];
        } else if (type == 'inlineStr') {
          value = elements(cell, 't')
              .map((part) => part.innerText)
              .join();
        } else if (type == 'b') {
          value = raw == '1' ? 'TRUE' : 'FALSE';
        } else {
          value = raw;
        }

        values.putIfAbsent(row, () => <int, String>{})[column] = value;

        if (row > maxRow) maxRow = row;
        if (column > maxColumn) maxColumn = column;
      }

      if ((maxRow + 1) * (maxColumn + 1) > 20000) {
        throw StateError('This worksheet is too large for the table preview.');
      }

      final rows = List.generate(
        maxRow + 1,
        (row) => List.generate(
          maxColumn + 1,
          (column) => values[row]?[column] ?? '',
        ),
      );

      sheets.add(
        _SheetPreview(
          name: sheet.getAttribute('name') ?? 'Sheet ${sheets.length + 1}',
          rows: rows,
        ),
      );
    }

    if (sheets.isEmpty) {
      throw StateError('No worksheets were found.');
    }

    return _FilePreview(sheets: sheets);
  }

  String _columnName(int index) {
    var number = index + 1;
    var label = '';

    while (number > 0) {
      number--;
      label = String.fromCharCode(65 + number % 26) + label;
      number ~/= 26;
    }

    return label;
  }

  Widget _spreadsheet(List<_SheetPreview> sheets) {
    final sheet = sheets[_selectedSheet];
    final rows = sheet.rows;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButton<int>(
            value: _selectedSheet,
            isExpanded: true,
            items: List.generate(
              sheets.length,
              (index) => DropdownMenuItem(
                value: index,
                child: Text(sheets[index].name),
              ),
            ),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSheet = value);
              }
            },
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('This worksheet is empty.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 56 + rows.first.length * 180.0,
                    child: ListView.builder(
                      itemCount: rows.length + 1,
                      itemBuilder: (context, index) {
                        final header = index == 0;

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _cell(
                                header ? '#' : '$index',
                                width: 56,
                                header: true,
                              ),
                              for (var column = 0;
                                  column < rows.first.length;
                                  column++)
                                _cell(
                                  header
                                      ? _columnName(column)
                                      : rows[index - 1][column],
                                  width: 180,
                                  header: header,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _cell(
    String text, {
    required double width,
    required bool header,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: header
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 0.5,
        ),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<_FilePreview>(
        future: _preview,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final message = error is StateError
                ? error.message.toString()
                : 'This file could not be previewed.';

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _selectedSheet = 0;
                          _preview = _load();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final preview = snapshot.data!;

          if (preview.text != null) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Text preview • Original Word layout is not shown',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    preview.text!,
                    style: const TextStyle(fontSize: 16, height: 1.6),
                  ),
                ],
              ),
            );
          }

          return _spreadsheet(preview.sheets);
        },
      ),
    );
  }
}