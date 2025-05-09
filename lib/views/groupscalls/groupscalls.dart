import 'package:flutter/material.dart';



// Screen 1: Groups_Call
class GroupsCallScreen extends StatelessWidget {
  const GroupsCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              //Back button and Calling...
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {},
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 16.0),
                      child: Text(
                        'Calling...',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),

              // Circular Avatars
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(
                      'https://media.istockphoto.com/id/1437816897/photo/business-woman-manager-or-human-resources-portrait-for-career-success-company-we-are-hiring.jpg?s=612x612&w=0&k=20&c=tyLvtzutRh22j9GqSGI33Z4HpIwv9vL_MZw_xOE19NQ=',
                    ), // Replace with actual image asset/URL
                  ),
                  const SizedBox(width: 20),
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(
                      'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSfdsbtZ-Y1ZAkR4yUO-LIEfpw724ImxyQPXQ&s',
                    ), // Replace with actual image asset/URL
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Game',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                '3 members',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const Spacer(flex: 3),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  _buildCallButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupsCallingScreen(),
                        ),
                      );
                    },
                  ),
                  _buildCallButton(
                    icon: Icons.phone,
                    color: Colors.green,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupsCallingScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildCallButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton(
      backgroundColor: color,
      onPressed: onPressed,
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

// Screen 2: Groups_Calling
class GroupsCallingScreen extends StatelessWidget {
  const GroupsCallingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => GroupsVideoCallingScreen()),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.grey[850],
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                //Back button and Calling...
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {},
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 16.0),
                        child: Text(
                          'Calling...',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),

                // Circular Avatars
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: NetworkImage(
                        'https://t4.ftcdn.net/jpg/03/64/21/11/360_F_364211147_1qgLVxv1Tcq0Ohz3FawUfrtONzz8nq3e.jpg',
                      ), // Replace with actual image asset/URL
                    ),
                    const SizedBox(width: 20),
                    CircleAvatar(
                      radius: 60,
                      backgroundImage: NetworkImage(
                        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTGw-sz_ynsO6fK1gee7Kz13-xZHInABzJrXw&s',
                      ), // Replace with actual image asset/URL
                    ),
                  ],
                ),

                const Spacer(flex: 3),

                // Calling Time
                const Text(
                  '03:45',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                // Action Buttons
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupsVideoCallingScreen(),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupsVideoCallingScreen(),
                            ),
                          );
                        },
                        child: _buildActionButton(icon: Icons.mic_off),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupsVideoCallingScreen(),
                            ),
                          );
                        },
                        child: _buildActionButton(icon: Icons.volume_up),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupsVideoCallingScreen(),
                            ),
                          );
                        },
                        child: _buildActionButton(icon: Icons.speaker),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => GroupsVideoCallingScreen(),
                            ),
                          );
                        },
                        child: _buildCallButton(
                          icon: Icons.call_end,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildActionButton({required IconData icon}) {
    return FloatingActionButton(
      backgroundColor: Colors.grey[700],
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }

  Widget _buildCallButton({required IconData icon, required Color color}) {
    return FloatingActionButton(
      backgroundColor: color,
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

// Screen 3: Groups_Video_Calling
class GroupsVideoCallingScreen extends StatelessWidget {
  const GroupsVideoCallingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[850],
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                // Main Video
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupsCallingScreen2(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(
                            'images/bgprofile.png',
                          ), // Replace with actual image asset/URL
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Color.fromARGB((0.5 * 255).toInt(), 0, 0, 0),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Calling...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GroupsCallingScreen2(),
                        ),
                      );
                    },
                    child: Container(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: NetworkImage(
                            'https://images.assetsdelivery.com/compings_v2/fizkes/fizkes2011/fizkes201102042.jpg',
                          ), // Replace with actual image asset/URL
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Small Video Overlay
            Positioned(
              bottom: 100,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupsCallingScreen2(),
                    ),
                  );
                },
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(8),
                    image: const DecorationImage(
                      image: NetworkImage(
                        'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQjl7xYqho8VFxvJSR9heh8UTerI6FW4KDbxA&s',
                      ), // Replace with actual image asset/URL
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GroupsCallingScreen2(),
                    ),
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    _buildActionButton(icon: Icons.mic_off),
                    _buildActionButton(icon: Icons.volume_up),
                    _buildActionButton(icon: Icons.videocam_off),
                    _buildCallButton(icon: Icons.call_end, color: Colors.red),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '03:45',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon}) {
    return FloatingActionButton(
      backgroundColor: Colors.grey[700],
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }

  Widget _buildCallButton({required IconData icon, required Color color}) {
    return FloatingActionButton(
      backgroundColor: color,
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

// Screen 4: Groups_Calling 2
class GroupsCallingScreen2 extends StatelessWidget {
  const GroupsCallingScreen2({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (){
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupsVideoCallingScreen2(),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.grey[850],
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                //Back button and Calling...
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () {},
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 16.0),
                        child: Text(
                          'Calling...',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 1),

                // Grid of Avatars
                Expanded(
                  flex: 4,
                  child: GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(16),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: List.generate(6, (index) {
                      return _buildAvatar();
                    }),
                  ),
                ),

                // Calling Time
                const Text(
                  '03:45',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    _buildActionButton(icon: Icons.mic_off),
                    _buildActionButton(icon: Icons.volume_up),
                    _buildActionButton(icon: Icons.speaker),
                    _buildCallButton(icon: Icons.call_end, color: Colors.red),
                  ],
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return const CircleAvatar(
      radius: 60,
      backgroundImage: NetworkImage(
        'https://images.assetsdelivery.com/compings_v2/fizkes/fizkes2011/fizkes201102042.jpg',
      ), // Replace with actual image asset/URL
    );
  }

  Widget _buildActionButton({required IconData icon}) {
    return FloatingActionButton(
      backgroundColor: Colors.grey[700],
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }

  Widget _buildCallButton({required IconData icon, required Color color}) {
    return FloatingActionButton(
      backgroundColor: color,
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}

// Screen 5: Groups_Video_Calling 2
class GroupsVideoCallingScreen2 extends StatelessWidget {
  const GroupsVideoCallingScreen2({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[850],
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // Grid of Avatars
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: 2,
                      padding: const EdgeInsets.all(16),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: List.generate(6, (index) {
                        return Container(
                          height: 100,
                          width: 100,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: NetworkImage('https://images.assetsdelivery.com/compings_v2/fizkes/fizkes2011/fizkes201102042.jpg'),
                              fit: BoxFit.cover,
                            ),
                          ),

                        );
                      }),
                    ),
                  ),
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      _buildActionButton(icon: Icons.mic_off),
                      _buildActionButton(icon: Icons.volume_up),
                      _buildActionButton(icon: Icons.videocam_off),
                      _buildCallButton(icon: Icons.call_end, color: Colors.red),
                    ],
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '03:45',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon}) {
    return FloatingActionButton(
      backgroundColor: Colors.grey[700],
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 25),
    );
  }

  Widget _buildCallButton({required IconData icon, required Color color}) {
    return FloatingActionButton(
      backgroundColor: color,
      onPressed: () {},
      child: Icon(icon, color: Colors.white, size: 30),
    );
  }
}
