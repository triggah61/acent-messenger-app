import 'package:flutter/material.dart';

class CustommmSearchBarr extends StatelessWidget {

  final String text;
  const CustommmSearchBarr({
    super.key, required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30.0),
        boxShadow: [
          BoxShadow(
            color: Color.fromARGB((0.1 * 255).toInt(), 0, 0, 0),
            blurRadius: 10,
            spreadRadius: 2,
            offset: Offset(0, 4),
          )
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey[600], size: 24),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText:text,
                hintStyle: TextStyle(color: Colors.grey[500]),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.sort, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }
}
