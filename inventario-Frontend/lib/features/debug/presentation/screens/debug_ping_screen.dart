import 'package:flutter/material.dart';

class DebugPingScreen extends StatelessWidget {
  const DebugPingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Debug Ping'),
      ),
      body: const Center(
        child: Text(
          'Flutter render OK',
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
