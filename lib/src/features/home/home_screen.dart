import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Casa Pazza')),
      body: Center(
        child: Text(
          'Willkommen bei Casa Pazza',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
    );
  }
}
