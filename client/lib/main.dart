import 'package:flutter/material.dart';

void main() {
  runApp(const PcKaiserApp());
}

class PcKaiserApp extends StatelessWidget {
  const PcKaiserApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PC Kaiser',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('PC Kaiser'),
        ),
      ),
    );
  }
}
