import 'package:flutter/material.dart';

import 'factory/full_factory_form.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FilledButton(
          onPressed: () {
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const FullFactoryFormPage(),
              ),
            );
          },
          child: const Text('Add Factory'),
        ),
      ),
    );
  }
}
