import 'package:flutter/material.dart';
import 'package:intl/intl.dart';



class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121829), // Dark background color
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white),
                    onPressed: () {},
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                    ),
                  ),
                  const Text('Calls',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                  IconButton(
                    icon: const Icon(Icons.add_call, color: Colors.white),
                    onPressed: () {},
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue[400],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87)),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView(
                          children: [
                            _buildCallItem(
                                name: 'Team Align',
                                time: DateTime.now(),
                                type: CallType.team),
                            _buildCallItem(
                                name: 'Jhon Abraham',
                                time: DateTime.now()
                                    .subtract(const Duration(hours: 2)),
                                type: CallType.individual),
                            _buildCallItem(
                                name: 'Sabilah Sayma',
                                time: DateTime.now().subtract(const Duration(days: 1)),
                                type: CallType.individual),
                            _buildCallItem(
                                name: 'Alex Linderson',
                                time: DateTime.now().subtract(const Duration(days: 2)),
                                type: CallType.individual),
                            _buildCallItem(
                                name: 'Jhon Abraham',
                                time: DateTime(2022, 7, 3),
                                type: CallType.individual),
                            _buildCallItem(
                                name: 'John Borino',
                                time: DateTime.now().subtract(const Duration(days: 3)),
                                type: CallType.individual),
                            _buildCallItem(
                                name: 'Alice Wonderland',
                                time: DateTime.now()
                                    .subtract(const Duration(days: 4)),
                                type: CallType.individual),
                            _buildCallItem(
                                name: 'Bob The Builder',
                                time: DateTime.now()
                                    .subtract(const Duration(days: 5)),
                                type: CallType.team),
                            _buildCallItem(
                                name: 'Charlie Chaplin',
                                time: DateTime.now()
                                    .subtract(const Duration(days: 6)),
                                type: CallType.individual),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallItem({
    required String name,
    required DateTime time,
    required CallType type,
  }) {
    Color timeColor;
    IconData icon;

    if (type == CallType.individual) {
      timeColor = Colors.purple;
      icon = Icons.call_received;
    } else {
      timeColor = Colors.green;
      icon = Icons.call;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: NetworkImage(
              type == CallType.team
                  ? 'https://images.assetsdelivery.com/compings_v2/fizkes/fizkes2011/fizkes201102042.jpg'
                  : 'https://media.istockphoto.com/id/1386479313/photo/happy-millennial-afro-american-business-woman-posing-isolated-on-white.jpg?s=612x612&w=0&k=20&c=8ssXDNTp1XAPan8Bg6mJRwG7EXHshFO5o0v9SIj96nY=',
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
                Row(
                  children: [
                    Icon(
                      icon,
                      color: timeColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MM/dd/yy').format(time),
                      style: TextStyle(fontSize: 14, color: timeColor),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('hh:mm a').format(time),
                      style: TextStyle(fontSize: 14, color: timeColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.call_outlined, color: Colors.green[600]), // Green for call
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: Colors.green[100], // Lighter green background
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(8),
            ),
          ),
          IconButton(
            icon: Icon(Icons.videocam_outlined, color: Colors.blue[600]), // Blue for video
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue[100], // Lighter blue background
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }
}

enum CallType {
  individual,
  team,
}