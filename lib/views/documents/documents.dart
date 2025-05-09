import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  DocumentScreenState createState() => DocumentScreenState();
}

class DocumentScreenState extends State<DocumentScreen> {
  // Dummy Document Data
  final List<Map<String, String>> _dummyDocuments = [
    {
      'name': 'Project Proposal.docx',
      'size': '2.5 MB',
      'icon': 'file-word',
    },
    {
      'name': 'Budget Spreadsheet.xlsx',
      'size': '1.8 MB',
      'icon': 'file-excel',
    },
    {
      'name': 'Meeting Minutes.pdf',
      'size': '900 KB',
      'icon': 'file-pdf',
    },
    {
      'name': 'Presentation Slides.pptx',
      'size': '3.2 MB',
      'icon': 'file-powerpoint',
    },
    {
      'name': 'Terms and Conditions.txt',
      'size': '10 KB',
      'icon': 'file-alt',
    },
  ];

  String? _selectedDocument;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select a Document'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _dummyDocuments.length,
        itemBuilder: (context, index) {
          final document = _dummyDocuments[index];
          final isSelected = _selectedDocument == document['name'];
          return Card(
            color: Colors.white,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: isSelected
                  ? const BorderSide(color: Colors.blue, width: 2)
                  : BorderSide.none,
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue[50],
                child: FaIcon(
                  getIconData(document['icon']!),
                  color: Colors.blue[400],
                  size: 20,
                ),
              ),
              title: Text(document['name']!),
              subtitle: Text('Size: ${document['size']!}'),
              onTap: () {
                setState(() {
                  _selectedDocument = document['name'];
                });
              },
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Colors.blue)
                  : null,
            ),
          );
        },
      ),
    );
  }

  // Helper function to get FontAwesome icons from the name
  IconData getIconData(String iconName) {
    switch (iconName) {
      case 'file-word':
        return FontAwesomeIcons.fileWord;
      case 'file-excel':
        return FontAwesomeIcons.fileExcel;
      case 'file-pdf':
        return FontAwesomeIcons.filePdf;
      case 'file-powerpoint':
        return FontAwesomeIcons.filePowerpoint;
      case 'file-alt':
        return FontAwesomeIcons.fileLines;
      default:
        return FontAwesomeIcons.file;
    }
  }
}