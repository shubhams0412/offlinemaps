import 'package:flutter/material.dart';

class SavedLocationsScreen extends StatelessWidget {
  const SavedLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Locations')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.home, color: Colors.blue),
            title: Text('Home'),
            subtitle: Text('123 Main St, Springfield'),
          ),
          ListTile(
            leading: Icon(Icons.work, color: Colors.blue),
            title: Text('Work'),
            subtitle: Text('456 Tech Park, Metropolis'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
