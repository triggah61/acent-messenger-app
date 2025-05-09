import 'package:flutter/material.dart';
import '../../../Constants/colors.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  CreateGroupScreenState createState() => CreateGroupScreenState();
}

class CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  List<Map<String, String>> selectedMembers = [];

  void _navigateToAddMembers() async {
    final result = await Navigator.push<List<Map<String, String>>>(
      context,
      MaterialPageRoute(builder: (context) => AddMembersScreen(selectedMembers)),
    );

    if (result != null && mounted) { // Check if widget is still mounted
      setState(() {
        selectedMembers = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.tabColor,
        elevation: 0,
        title: const Text('Create Group', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _groupNameController,
              decoration: InputDecoration(
                labelText: 'Group Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _navigateToAddMembers,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Add members to group', style: TextStyle(fontSize: 16)),
                    Icon(Icons.add, color: AppColors.buttonColor),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: selectedMembers.length,
                itemBuilder: (context, index) {
                  final member = selectedMembers[index];
                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: ListTile(
                      leading: CircleAvatar(backgroundImage: AssetImage(member['image']!)),
                      title: Text(member['name']!),
                      subtitle: Text(member['phone']!),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            selectedMembers.removeAt(index);
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.buttonColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  //Navigator.push( // Removed navigator here
                  //context,
                  //MaterialPageRoute(builder: (context) => AddMembersScreen(selectedMembers)),
                  //);
                },
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('Create Group', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }
}

class AddMembersScreen extends StatefulWidget {
  final List<Map<String, String>> selectedMembers;
  const AddMembersScreen(this.selectedMembers, {super.key});

  @override
  AddMembersScreenState createState() => AddMembersScreenState();
}

class AddMembersScreenState extends State<AddMembersScreen> {
  List<Map<String, String>> allMembers = [...friends];
  List<Map<String, String>> selected = [];

  @override
  void initState() {
    super.initState();
    selected = List.from(widget.selectedMembers);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.tabColor,
        title: const Text('Add Members', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Search',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (query) {
                  setState(() {
                    allMembers = friends
                        .where((member) => member['name']!.toLowerCase().contains(query.toLowerCase()))
                        .toList();
                  });
                },
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: allMembers.length,
                itemBuilder: (context, index) {
                  final member = allMembers[index];
                  final isSelected = selected.contains(member);
                  return Card(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    child: CheckboxListTile(
                      title: Text(member['name']!),
                      subtitle: Text(member['phone']!),
                      secondary: CircleAvatar(backgroundImage: AssetImage(member['image']!)),
                      value: isSelected,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            selected.add(member);
                          } else {
                            selected.remove(member);
                          }
                        });
                      },
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.buttonColor),
                onPressed: () {
                  Navigator.pop(context, selected);
                },
                child: const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text('Add Members', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            ),
            const SizedBox(height: 10)
          ],
        ),
      ),
    );
  }
}

final List<Map<String, String>> friends = [
  {"name": "David Wayne", "phone": "(+44) 905 326 3022", "image": "images/c2.png"},
  {"name": "Edward Mint", "phone": "(+44) 926 2322", "image": "images/c3.png"},
  {"name": "May HG. Kang", "phone": "(+44) 9288 214", "image": "images/c4.png"},
  {"name": "Lily Dare", "phone": "(+44) 905 5299", "image": "images/c5.png"},
  {"name": "Dennis Dang", "phone": "(+44) 923 939", "image": "images/c2.png"},
];